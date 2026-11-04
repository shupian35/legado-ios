//
//  ImportOldDataTests.swift
//  LegadoCoreTests
//
//  The import of the old Legado data — upstream
//  `help/storage/ImportOldData.kt`.
//

import XCTest
@testable import LegadoCore

final class ImportOldDataTests: XCTestCase {

    // MARK: The bookshelf

    private let oldShelf = """
    [
      {
        "noteUrl": "https://example.com/book/1",
        "tag": "测试源",
        "allowUpdate": true,
        "chapterListSize": 120,
        "durChapter": 7,
        "durChapterName": "第七章",
        "durChapterPage": 12,
        "finalDate": 1600000000000,
        "lastChapterName": "第一百二十章",
        "newChapters": 3,
        "serialNumber": 5,
        "variable": "v_1",
        "useReplaceRule": false,
        "customCoverPath": "/sdcard/cover.jpg",
        "bookInfoBean": {
          "name": "测试书",
          "origin": "旧阅读",
          "author": "作者",
          "chapterUrl": "https://example.com/book/1/toc",
          "coverUrl": "https://example.com/cover.jpg",
          "introduce": "简介",
          "finalRefreshData": 1500000000000,
          "bookSourceType": "TXT"
        }
      }
    ]
    """

    func testTheOldBookshelfIsImported() throws {
        let books = try ImportOldData.importOldBooks(oldShelf)
        XCTAssertEqual(books.count, 1)
        let book = books[0]
        XCTAssertEqual(book.bookUrl, "https://example.com/book/1")
        XCTAssertEqual(book.name, "测试书")
        XCTAssertEqual(book.author, "作者")
        XCTAssertEqual(book.origin, "测试源")
        XCTAssertEqual(book.originName, "旧阅读")
        XCTAssertEqual(book.tocUrl, "https://example.com/book/1/toc")
        XCTAssertEqual(book.coverUrl, "https://example.com/cover.jpg")
        XCTAssertEqual(book.customCoverUrl, "/sdcard/cover.jpg")
        XCTAssertEqual(book.intro, "简介")
        XCTAssertEqual(book.totalChapterNum, 120)
        XCTAssertEqual(book.durChapterIndex, 7)
        XCTAssertEqual(book.durChapterTitle, "第七章")
        XCTAssertEqual(book.durChapterPos, 12)
        XCTAssertEqual(book.durChapterTime, 1_600_000_000_000)
        XCTAssertEqual(book.lastCheckTime, 1_500_000_000_000)
        XCTAssertEqual(book.lastCheckCount, 3)
        XCTAssertEqual(book.latestChapterTitle, "第一百二十章")
        XCTAssertEqual(book.order, 5)
        XCTAssertEqual(book.variable, "v_1")
        XCTAssertTrue(book.canUpdate)
        XCTAssertFalse(book.useReplaceRule)
    }

    func testTheExistingBooksAreSkipped() throws {
        let books = try ImportOldData.importOldBooks(
            oldShelf,
            existingBookUrls: ["https://example.com/book/1"]
        )
        XCTAssertTrue(books.isEmpty)
    }

    func testALocalBookKeepsItsType() throws {
        let json = """
        [{"noteUrl":"file:///a.txt","tag":"loc_book","bookInfoBean":{"name":"本地"}},
         {"noteUrl":"https://example.com/a","tag":"s","bookInfoBean":{"name":"网络","bookSourceType":"AUDIO"}}]
        """
        let books = try ImportOldData.importOldBooks(json)
        XCTAssertEqual(books.count, 2)
        XCTAssertTrue(books[0].isLocal)
        XCTAssertTrue(BookType.contains(books[0].type, BookType.text))
        XCTAssertFalse(books[1].isLocal)
        XCTAssertTrue(BookType.contains(books[1].type, BookType.audio))
    }

    func testABrokenBookshelfThrows() {
        XCTAssertThrowsError(try ImportOldData.importOldBooks("{not json")) { error in
            XCTAssertEqual(error as? ImportOldDataError, .brokenJson)
        }
    }

    // MARK: The rule conversion

    func testTheOldRuleSyntaxIsConverted() {
        // The upstream `toNewRule`: a single `#` is a replacement, a single
        // `|` is a separator and a single `&` is a reference.
        XCTAssertEqual(ImportOldData.toNewRule("<a>#b"), "<a>##b")
        XCTAssertEqual(ImportOldData.toNewRule("<a>|b"), "<a>||b")
        XCTAssertEqual(ImportOldData.toNewRule("<a>&b"), "<a>&&b")
    }

    func testTheRulePrefixesAreKept() {
        XCTAssertEqual(ImportOldData.toNewRule("-<a>"), "-<a>")
        XCTAssertEqual(ImportOldData.toNewRule("+<a>"), "+<a>")
        XCTAssertEqual(ImportOldData.toNewRule("-+<a>"), "-+<a>")
    }

    func testThePrefixesAreDuplicatedByTheUpstreamQuirk() {
        // The upstream converts the replacements with `oldRule.replace(...)`
        // — the rule that still carries the prefix — and adds the prefix
        // again afterwards, so a prefixed rule with a replacement ends up
        // with the prefix twice.  The port reproduces the upstream.
        XCTAssertEqual(ImportOldData.toNewRule("-<a>#b"), "--<a>##b")
        XCTAssertEqual(ImportOldData.toNewRule("+<a>#b"), "++<a>##b")
        XCTAssertEqual(ImportOldData.toNewRule("-+<a>#b"), "-+-+<a>##b")
    }

    func testTheNewRuleSyntaxIsNotTouched() {
        XCTAssertEqual(ImportOldData.toNewRule("@CSS:a#b"), "@CSS:a#b")
        XCTAssertEqual(ImportOldData.toNewRule("@XPath://a#b"), "@XPath://a#b")
        XCTAssertEqual(ImportOldData.toNewRule("##a##b##"), "##a##b##")
        XCTAssertEqual(ImportOldData.toNewRule("//a|b"), "//a|b")
        XCTAssertEqual(ImportOldData.toNewRule(":a|b"), ":a|b")
    }

    func testAnEmptyRuleBecomesNil() {
        XCTAssertNil(ImportOldData.toNewRule(nil))
        XCTAssertNil(ImportOldData.toNewRule(""))
        XCTAssertNil(ImportOldData.toNewRule("   "))
    }

    // MARK: The URL conversion

    func testTheOldUrlIsConverted() {
        let url = ImportOldData.toNewUrl("http://example.com/s?key=searchKey&page=searchPage")
        XCTAssertEqual(url, "http://example.com/s?key={{key}}&page={{page}}")
    }

    func testTheOldUrlKeepsItsHeaderAndCharset() {
        let url = ImportOldData.toNewUrl("@Header:{\"User-Agent\":\"UA\"}http://example.com/s|charset=utf-8")
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.hasPrefix("http://example.com/s,") == true)
        XCTAssertTrue(url?.contains("\"charset\":\"utf-8\"") == true)
        XCTAssertTrue(url?.contains("\\\"User-Agent\\\":\\\"UA\\\"") == true)
    }

    func testTheOldUrlPostBodyIsConverted() {
        let url = ImportOldData.toNewUrl("http://example.com/s@key=searchKey")
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.hasPrefix("http://example.com/s,") == true)
        XCTAssertTrue(url?.contains("\"method\":\"POST\"") == true)
        XCTAssertTrue(url?.contains("\"body\":\"key={{key}}\"") == true)
    }

    func testTheOldUrlPageOffsetIsConverted() {
        XCTAssertEqual(
            ImportOldData.toNewUrl("http://example.com/s?p=searchPage+1"),
            "http://example.com/s?p={{page+1}}"
        )
        XCTAssertEqual(
            ImportOldData.toNewUrl("http://example.com/s?p=<searchPage-1>"),
            "http://example.com/s?p={{page-1}}"
        )
    }

    func testTheOldUrlListIsConverted() {
        let urls = ImportOldData.toNewUrls("http://a/s?key=searchKey&&http://b/s?key=searchKey")
        XCTAssertEqual(urls, "http://a/s?key={{key}}\nhttp://b/s?key={{key}}")
    }

    func testAnEmptyUrlBecomesNil() {
        XCTAssertNil(ImportOldData.toNewUrl(nil))
        XCTAssertNil(ImportOldData.toNewUrl(""))
        XCTAssertNil(ImportOldData.toNewUrls(nil))
        XCTAssertNil(ImportOldData.toNewUrls(""))
    }

    // MARK: The sources

    private let oldSource = """
    {
      "bookSourceUrl": "https://example.com",
      "bookSourceName": "旧源",
      "bookSourceGroup": "分组",
      "bookSourceComment": "备注",
      "httpUserAgent": "UA",
      "enable": true,
      "serialNumber": 3,
      "ruleSearchUrl": "http://example.com/s?key=searchKey",
      "ruleSearchList": "<li>",
      "ruleSearchName": "a.name",
      "ruleSearchAuthor": "a.author",
      "ruleSearchNoteUrl": "a.href",
      "ruleFindUrl": "http://example.com/f?key=searchKey",
      "ruleFindList": "<li>",
      "ruleFindName": "a.name",
      "ruleChapterList": "<a>",
      "ruleChapterName": "a.text",
      "ruleContentUrl": "a.href",
      "ruleBookContent": "<p>#正文"
    }
    """

    func testTheOldSourceIsImported() throws {
        let sources = try ImportOldData.importOldSources("[\(oldSource)]")
        XCTAssertEqual(sources.count, 1)
        let source = sources[0]
        XCTAssertEqual(source.bookSourceUrl, "https://example.com")
        XCTAssertEqual(source.bookSourceName, "旧源")
        XCTAssertEqual(source.bookSourceGroup, "分组")
        XCTAssertEqual(source.bookSourceComment, "备注")
        XCTAssertEqual(source.customOrder, 3)
        XCTAssertTrue(source.enabled)
        XCTAssertTrue(source.enabledExplore)
        XCTAssertEqual(source.searchUrl, "http://example.com/s?key={{key}}")
        XCTAssertEqual(source.exploreUrl, "http://example.com/f?key={{key}}")
        XCTAssertEqual(source.header, "{\"User-Agent\":\"UA\"}")
    }

    func testTheOldSourceRulesAreConverted() throws {
        let sources = try ImportOldData.importOldSources("[\(oldSource)]")
        let source = sources[0]
        let search = try JSONValue.parse(source.ruleSearch ?? "{}")
        XCTAssertEqual(search["bookList"]?.stringValue, "<li>")
        XCTAssertEqual(search["name"]?.stringValue, "a.name")
        XCTAssertEqual(search["author"]?.stringValue, "a.author")
        XCTAssertEqual(search["bookUrl"]?.stringValue, "a.href")
        let content = try JSONValue.parse(source.ruleContent ?? "{}")
        XCTAssertEqual(content["content"]?.stringValue, "<p>##正文")
    }

    func testASourceWithoutAnExploreUrlIsNotExplorable() throws {
        let json = """
        [{"bookSourceUrl":"https://example.com","bookSourceName":"s","ruleFindUrl":""}]
        """
        let sources = try ImportOldData.importOldSources(json)
        XCTAssertFalse(sources[0].enabledExplore)
        // The upstream only disables the exploration, not the source.
        XCTAssertTrue(sources[0].enabled)
    }

    func testASourceWithoutAnUrlIsWrong() {
        let json = """
        [{"bookSourceName":"s"}]
        """
        XCTAssertThrowsError(try ImportOldData.importOldSources(json)) { error in
            XCTAssertEqual(error as? ImportOldDataError, .wrongFormat)
        }
    }

    // MARK: The replace rules

    func testTheOldReplaceRulesAreImported() throws {
        let json = """
        [{"regex":"广告","replaceSummary":"删除广告","replacement":"","useTo":"","enable":true,"serialNumber":1}]
        """
        let rules = try ImportOldData.importOldReplaceRules(json)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].pattern, "广告")
        XCTAssertEqual(rules[0].name, "删除广告")
        XCTAssertTrue(rules[0].isEnabled)
    }
}
