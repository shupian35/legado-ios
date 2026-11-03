//
//  ContentSearchTests.swift
//  LegadoCoreTests
//
//  Tests for the content search (搜索正文) — the port of
//  `io.legado.app.ui.book.searchContent.SearchContentViewModel`.
//

import XCTest
@testable import LegadoCore

final class ContentSearchTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("legado-content-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Fixtures

    private func makeBook(name: String = "测试书") -> Book {
        Book(
            bookUrl: "https://example.com/book",
            origin: "https://example.com",
            name: name,
            author: "作者"
        )
    }

    private func makeChapter(_ index: Int, title: String? = nil) -> BookChapter {
        BookChapter(
            url: "https://example.com/chapter/\(index)",
            title: title ?? "第\(index)章",
            isVolume: false,
            bookUrl: "https://example.com/book",
            index: Int64(index)
        )
    }

    private func makeStorage() -> BookCacheStorage {
        BookCacheStorage(layout: BookCacheLayout(root: root))
    }

    @discardableResult
    private func cache(_ storage: BookCacheStorage, book: Book, chapter: BookChapter, _ text: String) -> Bool {
        try? storage.saveText(book: book, chapter: chapter, content: text)
        return true
    }

    // MARK: - The positions

    func testTheMatchesDoNotOverlap() {
        // The upstream searches with `indexOf(pattern, index + pattern.length)`,
        // so the matches never overlap.
        XCTAssertEqual(ContentSearcher.positions(of: "aa", in: "aaaa"), [0, 2])
        XCTAssertEqual(ContentSearcher.positions(of: "aa", in: "aaa"), [0])
        XCTAssertEqual(ContentSearcher.positions(of: "x", in: "abc"), [])
        XCTAssertEqual(ContentSearcher.positions(of: "", in: "abc"), [])
    }

    func testTheContextIsTwentyCharactersAroundTheMatch() {
        let content = String(repeating: "a", count: 50) + "needle" + String(repeating: "b", count: 50)
        let constructed = ContentSearcher.resultAndQueryIndex(
            content: content,
            queryIndex: 50,
            query: "needle",
            contextLength: 20
        )
        XCTAssertEqual(constructed.index, 20)
        XCTAssertEqual(constructed.text.count, 6 + 40)
        XCTAssertTrue(constructed.text.contains("needle"))
    }

    func testTheContextIsClampedAtTheEdges() {
        let constructed = ContentSearcher.resultAndQueryIndex(
            content: "needle",
            queryIndex: 0,
            query: "needle",
            contextLength: 20
        )
        XCTAssertEqual(constructed.index, 0)
        XCTAssertEqual(constructed.text, "needle")
    }

    // MARK: - One chapter

    func testTheChapterResultsCarryThePositions() {
        let chapter = makeChapter(3, title: "第三章")
        let results = ContentSearcher.searchChapter(
            query: "宝藏",
            chapter: chapter,
            content: "前面有宝藏，后面也有宝藏。",
            chapterTitle: "第三章"
        )
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].resultCountWithinChapter, 0)
        XCTAssertEqual(results[1].resultCountWithinChapter, 1)
        XCTAssertEqual(results[0].chapterTitle, "第三章")
        XCTAssertEqual(results[0].query, "宝藏")
        XCTAssertEqual(results[0].chapterIndex, 3)
        XCTAssertEqual(results[0].queryIndexInChapter, 3)
        XCTAssertEqual(results[1].queryIndexInChapter, 10)
        XCTAssertTrue(results[0].resultText.contains("宝藏"))
        XCTAssertEqual(results[0].queryIndexInResult, 3)
    }

    // MARK: - The whole book

    func testOnlyTheCachedChaptersAreSearched() {
        let book = makeBook()
        let storage = makeStorage()
        let cached = makeChapter(0, title: "第一章")
        let missing = makeChapter(1, title: "第二章")
        cache(storage, book: book, chapter: cached, "第一章的内容里有宝藏。")
        let results = ContentSearcher.search(
            book: book,
            chapters: [cached, missing],
            query: "宝藏",
            storage: storage
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].chapterTitle, "第一章")
        XCTAssertEqual(results[0].resultCount, 1)
    }

    func testTheResultCountRunsOverAllTheChapters() {
        let book = makeBook()
        let storage = makeStorage()
        let first = makeChapter(0, title: "第一章")
        let second = makeChapter(1, title: "第二章")
        cache(storage, book: book, chapter: first, "宝藏")
        cache(storage, book: book, chapter: second, "宝藏和宝藏")
        let results = ContentSearcher.search(
            book: book,
            chapters: [first, second],
            query: "宝藏",
            storage: storage
        )
        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results.map { $0.resultCount }, [1, 2, 3])
        XCTAssertEqual(results.map { $0.resultCountWithinChapter }, [0, 0, 1])
    }

    func testTheSearchIsCaseSensitive() {
        let book = makeBook()
        let storage = makeStorage()
        let chapter = makeChapter(0, title: "第一章")
        cache(storage, book: book, chapter: chapter, "这里有 Test 和 test。")
        let results = ContentSearcher.search(
            book: book,
            chapters: [chapter],
            query: "Test",
            storage: storage
        )
        XCTAssertEqual(results.count, 1)
        // The searched text is the PROCESSED text: the chapter title, a
        // newline and the paragraph indent come before the content.
        XCTAssertEqual(results[0].queryIndexInChapter, 10)
        let lower = ContentSearcher.search(
            book: book,
            chapters: [chapter],
            query: "TEST",
            storage: storage
        )
        XCTAssertTrue(lower.isEmpty)
    }

    func testTheSearchedTextContainsTheChapterTitle() {
        // The upstream processes the content with `includeTitle = true`, so the
        // title is part of the searched text.
        let book = makeBook()
        let storage = makeStorage()
        let chapter = makeChapter(0, title: "第一章")
        cache(storage, book: book, chapter: chapter, "正文内容")
        let results = ContentSearcher.search(
            book: book,
            chapters: [chapter],
            query: "第一章",
            storage: storage
        )
        XCTAssertEqual(results.count, 1)
    }

    func testTheTitleIsConverted() {
        let book = makeBook()
        let storage = makeStorage()
        let chapter = makeChapter(0, title: "第一章")
        cache(storage, book: book, chapter: chapter, "正文")
        let results = ContentSearcher.search(
            book: book,
            chapters: [chapter],
            query: "正文",
            storage: storage,
            options: ContentSearchOptions(chineseConversionMode: .traditionalToSimplified)
        )
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].chapterTitle, "第一章")
    }

    func testTheReplaceRulesAreAppliedWhenTheyAreEnabled() {
        let book = makeBook()
        let storage = makeStorage()
        let chapter = makeChapter(0, title: "第一章")
        cache(storage, book: book, chapter: chapter, "他走进了房间。")
        let rule = ReplaceRule(
            name: "替换",
            pattern: "房间",
            replacement: "屋子",
            isEnabled: true,
            isRegex: false
        )
        let withoutRules = ContentSearcher.search(
            book: book,
            chapters: [chapter],
            query: "房间",
            storage: storage
        )
        XCTAssertEqual(withoutRules.count, 1)
        let withRules = ContentSearcher.search(
            book: book,
            chapters: [chapter],
            query: "屋子",
            storage: storage,
            contentRules: [rule],
            options: ContentSearchOptions(useReplaceRule: true)
        )
        XCTAssertEqual(withRules.count, 1)
    }

    func testAnEmptyQueryFindsNothing() {
        let book = makeBook()
        let storage = makeStorage()
        let chapter = makeChapter(0, title: "第一章")
        cache(storage, book: book, chapter: chapter, "正文")
        let results = ContentSearcher.search(
            book: book,
            chapters: [chapter],
            query: "",
            storage: storage
        )
        XCTAssertTrue(results.isEmpty)
    }
}
