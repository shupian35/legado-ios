//
//  BookSourceImportTests.swift
//  LegadoCoreTests
//
//  The tests of the preview of the import of the book sources.
//
//  Upstream:
//  - `ui/association/ImportBookSourceViewModel.kt` — the comparison of the
//    imported sources with the local ones and the options of the import.
//

import XCTest
@testable import LegadoCore

final class BookSourceImportTests: XCTestCase {

    /// Builds a source.
    private func source(
        url: String = "https://a.com",
        name: String = "A",
        group: String? = nil,
        enabled: Bool = true,
        enabledExplore: Bool = true,
        customOrder: Int64 = 0,
        lastUpdateTime: Int64 = 0
    ) -> BookSource {
        var source = BookSource(bookSourceUrl: url)
        source.bookSourceName = name
        source.bookSourceGroup = group
        source.enabled = enabled
        source.enabledExplore = enabledExplore
        source.customOrder = customOrder
        source.lastUpdateTime = lastUpdateTime
        return source
    }

    // MARK: - The preview of the import

    /// A source that is not on the device is new and selected.
    func testNewSourceIsSelected() {
        let items = BookSourceImport.items([source()], local: [])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.state, .new)
        XCTAssertEqual(items.first?.selected, true)
        XCTAssertEqual(items.first?.id, "https://a.com")
    }

    /// A source that is newer than the local one is an update and selected.
    func testNewerSourceIsAnUpdate() {
        let local = source(name: "A", lastUpdateTime: 10)
        let imported = source(name: "A2", lastUpdateTime: 20)
        let items = BookSourceImport.items([imported], local: [local])
        XCTAssertEqual(items.first?.state, .update)
        XCTAssertEqual(items.first?.selected, true)
    }

    /// A source that is older than the local one exists and is not selected.
    func testOlderSourceExists() {
        let local = source(lastUpdateTime: 20)
        let imported = source(lastUpdateTime: 10)
        let items = BookSourceImport.items([imported], local: [local])
        XCTAssertEqual(items.first?.state, .existing)
        XCTAssertEqual(items.first?.selected, false)
    }

    /// The same update time is not an update — the upstream compares `<`.
    func testSameTimeExists() {
        let local = source(lastUpdateTime: 20)
        let imported = source(lastUpdateTime: 20)
        let items = BookSourceImport.items([imported], local: [local])
        XCTAssertEqual(items.first?.state, .existing)
    }

    /// The states of a mixed batch.
    func testMixedBatch() {
        let local = [
            source(url: "https://a.com", lastUpdateTime: 20),
            source(url: "https://b.com", lastUpdateTime: 5)
        ]
        let imported = [
            source(url: "https://a.com", lastUpdateTime: 10),
            source(url: "https://b.com", lastUpdateTime: 15),
            source(url: "https://c.com")
        ]
        let items = BookSourceImport.items(imported, local: local)
        XCTAssertEqual(items.map(\.state), [.existing, .update, .new])
        XCTAssertEqual(items.map(\.selected), [false, true, true])
    }

    // MARK: - The options of the import

    /// The name of the local source wins when the option is on — upstream
    /// `if (keepName) source.bookSourceName = it.bookSourceName`.
    func testKeepName() {
        let local = source(name: "本地名")
        let imported = source(name: "导入名", lastUpdateTime: 10)
        var options = BookSourceImport.Options()
        options.keepName = true
        let prepared = BookSourceImport.prepare(
            BookSourceImport.items([imported], local: [local]),
            local: [local],
            options: options
        )
        XCTAssertEqual(prepared.first?.bookSourceName, "本地名")
    }

    /// Without the option the imported name wins.
    func testImportedNameWinsByDefault() {
        let local = source(name: "本地名")
        let imported = source(name: "导入名", lastUpdateTime: 10)
        let prepared = BookSourceImport.prepare(
            BookSourceImport.items([imported], local: [local]),
            local: [local],
            options: BookSourceImport.Options()
        )
        XCTAssertEqual(prepared.first?.bookSourceName, "导入名")
    }

    /// The local group wins when the option is on.
    func testKeepGroup() {
        let local = source(group: "本地组")
        let imported = source(group: "导入组", lastUpdateTime: 10)
        var options = BookSourceImport.Options()
        options.keepGroup = true
        let prepared = BookSourceImport.prepare(
            BookSourceImport.items([imported], local: [local]),
            local: [local],
            options: options
        )
        XCTAssertEqual(prepared.first?.bookSourceGroup, "本地组")
    }

    /// `importKeepEnable` keeps BOTH the enabled and the enabledExplore flag —
    /// upstream `source.enabled = it.enabled; source.enabledExplore =
    /// it.enabledExplore`.
    func testKeepEnableKeepsBothFlags() {
        let local = source(enabled: false, enabledExplore: false)
        let imported = source(enabled: true, enabledExplore: true, lastUpdateTime: 10)
        var options = BookSourceImport.Options()
        options.keepEnable = true
        let prepared = BookSourceImport.prepare(
            BookSourceImport.items([imported], local: [local]),
            local: [local],
            options: options
        )
        XCTAssertEqual(prepared.first?.enabled, false)
        XCTAssertEqual(prepared.first?.enabledExplore, false)
    }

    /// The order ALWAYS comes from the local source — upstream
    /// `source.customOrder = it.customOrder` is outside the keep checks.
    func testOrderAlwaysComesFromTheLocalSource() {
        let local = source(customOrder: 7)
        let imported = source(customOrder: 42, lastUpdateTime: 10)
        let prepared = BookSourceImport.prepare(
            BookSourceImport.items([imported], local: [local]),
            local: [local],
            options: BookSourceImport.Options()
        )
        XCTAssertEqual(prepared.first?.customOrder, 7)
    }

    /// A new source keeps its own order.
    func testNewSourceKeepsItsOrder() {
        let imported = source(customOrder: 42)
        let prepared = BookSourceImport.prepare(
            BookSourceImport.items([imported], local: []),
            local: [],
            options: BookSourceImport.Options()
        )
        XCTAssertEqual(prepared.first?.customOrder, 42)
    }

    /// The unselected sources are dropped.
    func testUnselectedSourcesAreDropped() {
        let local = source(lastUpdateTime: 100)
        let imported = source(lastUpdateTime: 10)
        let prepared = BookSourceImport.prepare(
            BookSourceImport.items([imported], local: [local]),
            local: [local],
            options: BookSourceImport.Options()
        )
        XCTAssertTrue(prepared.isEmpty)
    }

    // MARK: - The group of the import

    /// The group of the options replaces the groups of the source.
    func testGroupReplacesTheGroups() {
        let imported = source(group: "旧组")
        var options = BookSourceImport.Options()
        options.groupName = "新组"
        let prepared = BookSourceImport.prepare(
            BookSourceImport.items([imported], local: []),
            local: [],
            options: options
        )
        XCTAssertEqual(prepared.first?.bookSourceGroup, "新组")
    }

    /// With `addGroup` the group is appended to the existing ones.
    func testAddGroupAppends() {
        let imported = source(group: "旧组")
        var options = BookSourceImport.Options()
        options.groupName = "新组"
        options.addGroup = true
        let prepared = BookSourceImport.prepare(
            BookSourceImport.items([imported], local: []),
            local: [],
            options: options
        )
        XCTAssertEqual(prepared.first?.bookSourceGroup, "旧组,新组")
    }

    /// A group that is already there is not added twice.
    func testAddGroupDoesNotDuplicate() {
        let imported = source(group: "旧组")
        var options = BookSourceImport.Options()
        options.groupName = "旧组"
        options.addGroup = true
        let prepared = BookSourceImport.prepare(
            BookSourceImport.items([imported], local: []),
            local: [],
            options: options
        )
        XCTAssertEqual(prepared.first?.bookSourceGroup, "旧组")
    }

    /// A blank group of the options is ignored.
    func testBlankGroupIsIgnored() {
        let imported = source(group: "旧组")
        var options = BookSourceImport.Options()
        options.groupName = "  "
        let prepared = BookSourceImport.prepare(
            BookSourceImport.items([imported], local: []),
            local: [],
            options: options
        )
        XCTAssertEqual(prepared.first?.bookSourceGroup, "旧组")
    }

    // MARK: - The group splitting

    /// The upstream `AppPattern.splitGroupRegex` splits on `[,;，；]`.
    func testSplitGroups() {
        XCTAssertEqual(
            BookSourceImport.splitGroups("a,b;c，d；e"),
            ["a", "b", "c", "d", "e"]
        )
        XCTAssertEqual(BookSourceImport.splitGroups("  a , b  "), ["a", "b"])
        XCTAssertEqual(BookSourceImport.splitGroups(""), [])
        XCTAssertEqual(BookSourceImport.splitGroups(nil), [])
    }

    // MARK: - The parsing

    /// A JSON array of the sources is parsed.
    func testParseArray() throws {
        let json = """
        [{"bookSourceUrl":"https://a.com","bookSourceName":"A"},
         {"bookSourceUrl":"https://b.com","bookSourceName":"B"}]
        """
        let sources = try BookSourceImport.sources(json: json)
        XCTAssertEqual(sources.map(\.bookSourceUrl), ["https://a.com", "https://b.com"])
    }

    /// A single JSON object is parsed.
    func testParseObject() throws {
        let json = #"{"bookSourceUrl":"https://a.com","bookSourceName":"A"}"#
        let sources = try BookSourceImport.sources(json: json)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.bookSourceName, "A")
    }

    /// A source without an address is rejected — upstream "不是书源".
    func testSourceWithoutUrlIsRejected() {
        let json = #"[{"bookSourceName":"A"}]"#
        XCTAssertThrowsError(try BookSourceImport.sources(json: json))
    }

    /// A non JSON document is rejected.
    func testWrongFormatIsRejected() {
        XCTAssertThrowsError(try BookSourceImport.sources(json: "not json"))
    }

    /// The `sourceUrls` member of a document is read.
    func testSourceURLs() throws {
        let json = #"{"sourceUrls":["https://a.com/s.json","https://b.com/s.json"]}"#
        XCTAssertEqual(
            try BookSourceImport.sourceURLs(json: json),
            ["https://a.com/s.json", "https://b.com/s.json"]
        )
    }

    /// A document without `sourceUrls` has no urls.
    func testNoSourceURLs() throws {
        let json = #"[{"bookSourceUrl":"https://a.com"}]"#
        XCTAssertEqual(try BookSourceImport.sourceURLs(json: json), [])
    }

    /// The absolute url check.
    func testIsAbsoluteURL() {
        XCTAssertTrue(BookSourceImport.isAbsoluteURL("https://a.com/s.json"))
        XCTAssertTrue(BookSourceImport.isAbsoluteURL("http://a.com"))
        XCTAssertFalse(BookSourceImport.isAbsoluteURL("a.com"))
        XCTAssertFalse(BookSourceImport.isAbsoluteURL("file:///tmp/a.json"))
        XCTAssertFalse(BookSourceImport.isAbsoluteURL("  "))
    }
}
