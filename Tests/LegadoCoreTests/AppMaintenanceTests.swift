//
//  AppMaintenanceTests.swift
//  LegadoCoreTests
//
//  The cleanup that runs when the application starts — upstream `App.onCreate`
//  (`App.kt:93-126`) and `DefaultData.upVersion` (`DefaultData.kt:24-43`).
//

import XCTest
@testable import LegadoCore

final class AppMaintenanceTests: XCTestCase {

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        try store.seedDefaultGroups()
        return store
    }

    private func makeSettings(autoClearExpired: Bool = true) -> AppSettings {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.autoClearExpired = autoClearExpired
        return settings
    }

    // MARK: - The expired caches

    func testTheExpiredCachesAreRemoved() throws {
        // Upstream `App.kt:102` — `appDb.cacheDao.clearDeadline(now)`.
        let store = try makeStore()
        try store.putCache("expired", value: "old", deadline: 1_000)
        try store.putCache("kept", value: "new", deadline: 0)
        let report = try AppMaintenance.cleanUp(
            store: store,
            settings: makeSettings(),
            now: 2_000
        )
        XCTAssertTrue(report.clearedCaches)
        XCTAssertNil(try store.cache("expired", now: 2_000))
        XCTAssertEqual(try store.cache("kept", now: 2_000), "new")
    }

    func testTheExpiredSearchResultsAreRemovedOnlyWhenThePreferenceIsOn() throws {
        // Upstream `App.kt:104-106` — the search results of the last day are
        // removed when `PreferKey.autoClearExpired` is on.
        let store = try makeStore()
        let old = SearchBook(bookUrl: "https://book.example/1", name: "Old", time: 1_000)
        try store.insert([old])

        let off = try AppMaintenance.cleanUp(
            store: store,
            settings: makeSettings(autoClearExpired: false),
            now: 86_400_000 + 2_000
        )
        XCTAssertFalse(off.clearedSearchBooks)
        XCTAssertEqual(try store.searchBooks(origin: "").count, 1)

        let on = try AppMaintenance.cleanUp(
            store: store,
            settings: makeSettings(autoClearExpired: true),
            now: 86_400_000 + 2_000
        )
        XCTAssertTrue(on.clearedSearchBooks)
        XCTAssertEqual(try store.searchBooks(origin: "").count, 0)
    }

    func testTheDefaultOfTheExpiredCleanupIsOn() {
        // Upstream `App.kt:104` — `getPrefBoolean(PreferKey.autoClearExpired, true)`.
        let settings = AppSettings(store: InMemorySettingsStore())
        XCTAssertTrue(settings.autoClearExpired)
    }

    // MARK: - The cache of the deleted books

    func testTheCacheFoldersOfTheDeletedBooksAreRemoved() throws {
        // Upstream `BookHelp.clearInvalidCache` — every cache folder whose
        // name is not the folder of a book of the database is deleted.
        let store = try makeStore()
        let book = Book(bookUrl: "https://book.example/1", name: "Kept", author: "A")
        try store.insert(book)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("legado-cache-\(UUID().uuidString)")
        let layout = BookCacheLayout(root: root)
        let storage = BookCacheStorage(layout: layout)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let kept = layout.folder(for: book)
        try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)
        let orphan = root.appendingPathComponent("orphan", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)

        let deleted = try AppMaintenance.clearInvalidBookCaches(store: store, cacheStorage: storage)
        XCTAssertEqual(deleted, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - The sort numbers of the sources

    func testTheSortNumbersAreRenumberedWhenTheyCollide() throws {
        // Upstream `SourceHelp.adjustSortNumber` — the sources are renumbered
        // from 0 when two of them share the same number.
        let store = try makeStore()
        try store.insert(BookSource(bookSourceUrl: "https://a.example", bookSourceName: "A", customOrder: 7))
        try store.insert(BookSource(bookSourceUrl: "https://b.example", bookSourceName: "B", customOrder: 7))

        let report = try AppMaintenance.cleanUp(store: store, settings: makeSettings())
        XCTAssertTrue(report.adjustedSourceOrder)
        let orders = try store.allSources().map(\.customOrder).sorted()
        XCTAssertEqual(orders, [0, 1])
    }

    func testTheSortNumbersAreKeptWhenTheyAreFine() throws {
        let store = try makeStore()
        try store.insert(BookSource(bookSourceUrl: "https://a.example", bookSourceName: "A", customOrder: 3))
        try store.insert(BookSource(bookSourceUrl: "https://b.example", bookSourceName: "B", customOrder: 9))

        let report = try AppMaintenance.cleanUp(store: store, settings: makeSettings())
        XCTAssertFalse(report.adjustedSourceOrder)
        let orders = try store.allSources().map(\.customOrder).sorted()
        XCTAssertEqual(orders, [3, 9])
    }

    func testTheSortNumbersAreRenumberedWhenTheyAreOutOfRange() throws {
        // Upstream `SourceHelp.adjustSortNumber` — a number above 99999 or
        // below -99999 is out of range.
        let store = try makeStore()
        try store.insert(BookSource(bookSourceUrl: "https://a.example", bookSourceName: "A", customOrder: 120_000))

        _ = try AppMaintenance.cleanUp(store: store, settings: makeSettings())
        XCTAssertEqual(try store.allSources().map(\.customOrder), [0])
    }

    // MARK: - The default data

    func testTheDefaultDataIsImportedAfterAnUpgrade() throws {
        // Upstream `DefaultData.upVersion` — the HTTP TTS engines, the TXT
        // table of contents rules, the RSS sources and the dictionary rules
        // are imported when the version of the app grew.
        let store = try makeStore()
        let config = LocalConfig(store: InMemorySettingsStore())

        let imported = try AppMaintenance.importDefaultsAfterUpgrade(store: store, localConfig: config)
        XCTAssertEqual(Set(imported), ["httpTTS", "txtTocRule", "rssSources", "dictRules"])
        XCTAssertFalse(try store.allHttpTTS().isEmpty)
        XCTAssertFalse(try store.allTxtTocRules().isEmpty)
        XCTAssertFalse(try store.allRssSources().isEmpty)
        XCTAssertFalse(try store.allDictRules().isEmpty)
    }

    func testTheDefaultDataIsNotImportedTwice() throws {
        // Upstream `LocalConfig.isLastVersion` — the version counters are
        // raised, so the data is imported only once.
        let store = try makeStore()
        let config = LocalConfig(store: InMemorySettingsStore())

        _ = try AppMaintenance.importDefaultsAfterUpgrade(store: store, localConfig: config)
        let second = try AppMaintenance.importDefaultsAfterUpgrade(store: store, localConfig: config)
        XCTAssertTrue(second.isEmpty)
    }
}
