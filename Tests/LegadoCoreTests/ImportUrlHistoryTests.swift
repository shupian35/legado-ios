//
//  ImportUrlHistoryTests.swift
//  LegadoCoreTests
//
//  The history of the urls the documents were imported from.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/book/source/manage/BookSourceActivity.kt:585-614
//  app/src/main/java/io/legado/app/ui/rss/source/manage/RssSourceActivity.kt:350-375
//  app/src/main/java/io/legado/app/ui/replace/ReplaceRuleActivity.kt:270-300
//  app/src/main/java/io/legado/app/ui/dict/rule/DictRuleActivity.kt:205-235
//

import XCTest
@testable import LegadoCore

final class ImportUrlHistoryTests: XCTestCase {

    // MARK: - The cache keys

    func testTheCacheKeysMatchTheUpstream() {
        XCTAssertEqual(ImportUrlHistory.Kind.bookSource.rawValue, "bookSourceRecordKey")
        XCTAssertEqual(ImportUrlHistory.Kind.rssSource.rawValue, "rssSourceRecordKey")
        XCTAssertEqual(ImportUrlHistory.Kind.replaceRule.rawValue, "replaceRuleRecordKey")
        XCTAssertEqual(ImportUrlHistory.Kind.dictRule.rawValue, "dictRuleUrls")
    }

    func testTheKindOfAnImportIsMapped() {
        XCTAssertEqual(ImportUrlHistory.Kind(importKind: .bookSource), .bookSource)
        XCTAssertEqual(ImportUrlHistory.Kind(importKind: .rssSource), .rssSource)
        XCTAssertEqual(ImportUrlHistory.Kind(importKind: .replaceRule), .replaceRule)
        XCTAssertEqual(ImportUrlHistory.Kind(importKind: .dictRule), .dictRule)
        XCTAssertNil(ImportUrlHistory.Kind(importKind: .theme))
    }

    // MARK: - The history

    func testTheHistoryIsEmptyByDefault() throws {
        let store = try makeStore()
        XCTAssertTrue(ImportUrlHistory.urls(.bookSource, store: store).isEmpty)
    }

    func testAnUrlIsRemembered() throws {
        let store = try makeStore()
        ImportUrlHistory.add("https://a.com/s.json", .bookSource, store: store)
        XCTAssertEqual(
            ImportUrlHistory.urls(.bookSource, store: store),
            ["https://a.com/s.json"]
        )
    }

    func testTheNewestUrlIsAtTheFront() throws {
        let store = try makeStore()
        ImportUrlHistory.add("https://a.com/1.json", .bookSource, store: store)
        ImportUrlHistory.add("https://a.com/2.json", .bookSource, store: store)
        XCTAssertEqual(
            ImportUrlHistory.urls(.bookSource, store: store),
            ["https://a.com/2.json", "https://a.com/1.json"]
        )
    }

    func testTheSameUrlIsNotAddedTwice() throws {
        let store = try makeStore()
        ImportUrlHistory.add("https://a.com/1.json", .bookSource, store: store)
        ImportUrlHistory.add("https://a.com/1.json", .bookSource, store: store)
        XCTAssertEqual(ImportUrlHistory.urls(.bookSource, store: store).count, 1)
    }

    func testATextThatIsNotAnUrlIsRefused() throws {
        let store = try makeStore()
        ImportUrlHistory.add("not an url", .bookSource, store: store)
        XCTAssertTrue(ImportUrlHistory.urls(.bookSource, store: store).isEmpty)
    }

    func testAnUrlIsRemoved() throws {
        let store = try makeStore()
        ImportUrlHistory.add("https://a.com/1.json", .bookSource, store: store)
        ImportUrlHistory.add("https://a.com/2.json", .bookSource, store: store)
        ImportUrlHistory.remove("https://a.com/1.json", .bookSource, store: store)
        XCTAssertEqual(
            ImportUrlHistory.urls(.bookSource, store: store),
            ["https://a.com/2.json"]
        )
    }

    func testTheHistoryOfEveryKindIsSeparate() throws {
        let store = try makeStore()
        ImportUrlHistory.add("https://a.com/1.json", .bookSource, store: store)
        XCTAssertTrue(ImportUrlHistory.urls(.rssSource, store: store).isEmpty)
    }

    func testTheHistoryIsStoredInTheCacheTable() throws {
        let store = try makeStore()
        ImportUrlHistory.add("https://a.com/1.json", .bookSource, store: store)
        let raw = try store.cache("bookSourceRecordKey", now: 0)
        XCTAssertEqual(raw, "https://a.com/1.json")
    }

    func testTheEmptyEntriesAreDropped() {
        XCTAssertEqual(
            ImportUrlHistory.split("https://a.com/1.json, ,https://a.com/2.json"),
            ["https://a.com/1.json", "https://a.com/2.json"]
        )
    }

    // MARK: - The helpers

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        return store
    }
}
