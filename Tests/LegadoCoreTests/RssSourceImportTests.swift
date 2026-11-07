//
//  RssSourceImportTests.swift
//  LegadoCoreTests
//
//  The tests of the preview of the import of the RSS sources and of the
//  favourites.
//
//  Upstream:
//  - `ui/association/ImportRssSourceViewModel.kt` — the comparison of the
//    imported sources with the local ones and the options of the import,
//  - `ui/rss/read/ReadRssViewModel.kt` — the favourites of an article.
//

import XCTest
@testable import LegadoCore

final class RssSourceImportTests: XCTestCase {

    // MARK: - The preview of the import

    /// A source that is not on the device is new and selected.
    func testNewSourceIsSelected() {
        let source = RssSource(sourceUrl: "https://a.com/rss", sourceName: "A")
        let items = RssSourceImport.items([source], local: [])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.state, .new)
        XCTAssertEqual(items.first?.selected, true)
    }

    /// A source that is newer than the local one is an update and it is
    /// selected — upstream
    /// `checkSources[index] == null || has.lastUpdateTime < it.lastUpdateTime`.
    func testNewerSourceIsAnUpdate() {
        let local = RssSource(sourceUrl: "https://a.com/rss", sourceName: "A", lastUpdateTime: 10)
        let imported = RssSource(sourceUrl: "https://a.com/rss", sourceName: "A2", lastUpdateTime: 20)
        let items = RssSourceImport.items([imported], local: [local])
        XCTAssertEqual(items.first?.state, .update)
        XCTAssertEqual(items.first?.selected, true)
    }

    /// A source that is not newer than the local one exists and it is not
    /// selected.
    func testOlderSourceExists() {
        let local = RssSource(sourceUrl: "https://a.com/rss", sourceName: "A", lastUpdateTime: 20)
        let imported = RssSource(sourceUrl: "https://a.com/rss", sourceName: "A2", lastUpdateTime: 10)
        let items = RssSourceImport.items([imported], local: [local])
        XCTAssertEqual(items.first?.state, .existing)
        XCTAssertEqual(items.first?.selected, false)
    }

    /// A source with the same update time exists — the upstream compares with
    /// `<` only.
    func testSameTimeExists() {
        let local = RssSource(sourceUrl: "https://a.com/rss", lastUpdateTime: 20)
        let imported = RssSource(sourceUrl: "https://a.com/rss", lastUpdateTime: 20)
        let items = RssSourceImport.items([imported], local: [local])
        XCTAssertEqual(items.first?.state, .existing)
        XCTAssertEqual(items.first?.selected, false)
    }

    /// Only the selected sources are inserted.
    func testPrepareSkipsTheUnselected() {
        let imported = RssSource(sourceUrl: "https://a.com/rss", sourceName: "A")
        var items = RssSourceImport.items([imported], local: [])
        items[0].selected = false
        XCTAssertTrue(RssSourceImport.prepare(items, local: [], options: RssSourceImport.Options()).isEmpty)
    }

    /// The name of the local source wins when the option is on.
    func testPrepareKeepsTheName() {
        let local = RssSource(sourceUrl: "https://a.com/rss", sourceName: "本地名", sourceGroup: "本地组", enabled: false, lastUpdateTime: 10, customOrder: 7)
        let imported = RssSource(sourceUrl: "https://a.com/rss", sourceName: "导入名", sourceGroup: "导入组", enabled: true, lastUpdateTime: 20)
        var options = RssSourceImport.Options()
        options.keepName = true
        options.keepGroup = true
        options.keepEnable = true
        let prepared = RssSourceImport.prepare(
            RssSourceImport.items([imported], local: [local]),
            local: [local],
            options: options
        )
        XCTAssertEqual(prepared.count, 1)
        XCTAssertEqual(prepared.first?.sourceName, "本地名")
        XCTAssertEqual(prepared.first?.sourceGroup, "本地组")
        XCTAssertEqual(prepared.first?.enabled, false)
        // The order always comes from the local source.
        XCTAssertEqual(prepared.first?.customOrder, 7)
    }

    /// The imported values win when the options are off.
    func testPrepareKeepsTheImportedValues() {
        let local = RssSource(sourceUrl: "https://a.com/rss", sourceName: "本地名", sourceGroup: "本地组", enabled: false, lastUpdateTime: 10)
        let imported = RssSource(sourceUrl: "https://a.com/rss", sourceName: "导入名", sourceGroup: "导入组", enabled: true, lastUpdateTime: 20)
        let prepared = RssSourceImport.prepare(
            RssSourceImport.items([imported], local: [local]),
            local: [local],
            options: RssSourceImport.Options()
        )
        XCTAssertEqual(prepared.first?.sourceName, "导入名")
        XCTAssertEqual(prepared.first?.sourceGroup, "导入组")
        XCTAssertEqual(prepared.first?.enabled, true)
    }

    /// The group of the options replaces the groups of the source.
    func testPrepareReplacesTheGroup() {
        let imported = RssSource(sourceUrl: "https://a.com/rss", sourceGroup: "旧组")
        var options = RssSourceImport.Options()
        options.groupName = "新组"
        let prepared = RssSourceImport.prepare(
            RssSourceImport.items([imported], local: []),
            local: [],
            options: options
        )
        XCTAssertEqual(prepared.first?.sourceGroup, "新组")
    }

    /// The group of the options is added to the groups of the source when the
    /// "同时添加分组" switch is on.
    func testPrepareAddsTheGroup() {
        let imported = RssSource(sourceUrl: "https://a.com/rss", sourceGroup: "旧组")
        var options = RssSourceImport.Options()
        options.groupName = "新组"
        options.addGroup = true
        let prepared = RssSourceImport.prepare(
            RssSourceImport.items([imported], local: []),
            local: [],
            options: options
        )
        XCTAssertEqual(prepared.first?.sourceGroup, "旧组,新组")
    }

    /// A group that is already there is not added twice.
    func testPrepareAddsTheGroupOnlyOnce() {
        let imported = RssSource(sourceUrl: "https://a.com/rss", sourceGroup: "旧组,新组")
        var options = RssSourceImport.Options()
        options.groupName = "新组"
        options.addGroup = true
        let prepared = RssSourceImport.prepare(
            RssSourceImport.items([imported], local: []),
            local: [],
            options: options
        )
        XCTAssertEqual(prepared.first?.sourceGroup, "旧组,新组")
    }

    /// The parsing of the JSON of the sources.
    func testSourcesFromJSON() throws {
        let json = """
        [{"sourceUrl":"https://a.com/rss","sourceName":"A"},{"sourceUrl":"https://b.com/rss"}]
        """
        let sources = try RssSourceImport.sources(json: json)
        XCTAssertEqual(sources.count, 2)
        XCTAssertEqual(sources.first?.sourceName, "A")
    }

    /// The URLs of a document with a `sourceUrls` member.
    func testSourceURLs() throws {
        let json = """
        {"sourceUrls":["https://a.com/rss","https://b.com/rss"]}
        """
        XCTAssertEqual(try RssSourceImport.sourceURLs(json: json).count, 2)
    }

    /// A document without a `sourceUrls` member has no URL.
    func testSourceURLsOfAnEmptyDocument() throws {
        XCTAssertTrue(try RssSourceImport.sourceURLs(json: "{}").isEmpty)
    }

    /// The absolute URLs are recognised — upstream `isAbsUrl`.
    func testAbsoluteURL() {
        XCTAssertTrue(RssSourceImport.isAbsoluteURL("https://a.com/rss"))
        XCTAssertTrue(RssSourceImport.isAbsoluteURL("http://a.com/rss"))
        XCTAssertFalse(RssSourceImport.isAbsoluteURL("a.com/rss"))
        XCTAssertFalse(RssSourceImport.isAbsoluteURL(""))
    }

    // MARK: - The duplicate addresses

    /// A source file may list the same `sourceUrl` twice. Both rows stay in
    /// the preview, so the list of the UI has to key them by position instead
    /// of by address.
    func testDuplicateAddressesBothAppearInThePreview() {
        let items = RssSourceImport.items(
            [
                RssSource(sourceUrl: "https://a.com/rss", sourceName: "A1"),
                RssSource(sourceUrl: "https://a.com/rss", sourceName: "A2")
            ],
            local: []
        )
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.map(\.id), ["https://a.com/rss", "https://a.com/rss"])
        XCTAssertEqual(items.map(\.source.sourceName), ["A1", "A2"])
    }

    // MARK: - The favourites

    /// The favourite of an article — upstream `RssArticle.toStar()`.
    func testMakeStar() {
        let article = RssArticle(
            origin: "https://a.com/rss",
            sort: "sort",
            title: "标题",
            link: "https://a.com/1",
            pubDate: "2024",
            description: "描述",
            content: "正文",
            image: "https://a.com/1.png"
        )
        let star = RssLibrary.makeStar(article: article)
        XCTAssertEqual(star.origin, "https://a.com/rss")
        XCTAssertEqual(star.title, "标题")
        XCTAssertEqual(star.link, "https://a.com/1")
        XCTAssertEqual(star.group, RssLibrary.defaultGroup)
        XCTAssertGreaterThan(star.starTime, 0)
    }

    /// The favourite of an article may be put into another group.
    func testMakeStarInAGroup() {
        let article = RssArticle(origin: "o", sort: "s", title: "t", link: "l")
        let star = RssLibrary.makeStar(article: article, group: "我的组")
        XCTAssertEqual(star.group, "我的组")
    }

    /// The star of an article is found by its link — upstream
    /// `rssStarDao.get(origin, link)`.
    func testStarOfAnArticle() {
        let article = RssArticle(origin: "o", sort: "s", title: "t", link: "l")
        let star = RssLibrary.makeStar(article: article)
        XCTAssertNotNil(RssLibrary.star(of: article, in: [star]))
        XCTAssertNil(RssLibrary.star(of: RssArticle(origin: "o", sort: "s", title: "t", link: "x"), in: [star]))
    }
}
