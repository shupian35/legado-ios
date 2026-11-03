//
//  PipelineTests.swift
//  LegadoCoreTests
//
//  Tests for the book-source flow — the port of `io.legado.app.model.webBook`.
//

import XCTest
@testable import LegadoCore

final class PipelineTests: XCTestCase {

    // MARK: - Fixtures

    private func makeSource(
        search: String? = nil,
        explore: String? = nil,
        bookInfo: String? = nil,
        toc: String? = nil,
        content: String? = nil,
        url: String = "https://example.com"
    ) -> BookSource {
        BookSource(
            bookSourceUrl: url,
            bookSourceName: "Test",
            ruleExplore: explore,
            ruleSearch: search,
            ruleBookInfo: bookInfo,
            ruleToc: toc,
            ruleContent: content
        )
    }

    private func makeAnalyzeUrl(_ url: String = "https://example.com/search") -> AnalyzeUrl {
        AnalyzeUrl(url: url, baseUrl: "https://example.com")
    }

    // MARK: - Book list

    func testSearchResultListIsParsed() throws {
        let html = """
        <div class="book">
          <h3><a href="/book/1">Book One</a></h3>
          <span class="author">Author One</span>
          <p class="intro">Intro one</p>
        </div>
        <div class="book">
          <h3><a href="/book/2">Book Two</a></h3>
          <span class="author">Author Two</span>
        </div>
        """
        let source = makeSource(search: """
        {"bookList":"div.book","name":"h3 a@text","author":"span.author@text","intro":"p.intro@text","bookUrl":"h3 a@href"}
        """)
        let ruleData = RuleDataBox()
        let result = try BookListAssembler.analyzeBookList(
            bookSource: source,
            ruleData: ruleData,
            analyzeUrl: makeAnalyzeUrl(),
            baseUrl: "https://example.com/search",
            body: html,
            isSearch: true
        )
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "Book One")
        XCTAssertEqual(result[0].author, "Author One")
        XCTAssertEqual(result[0].intro, "Intro one")
        XCTAssertEqual(result[0].bookUrl, "https://example.com/book/1")
        XCTAssertEqual(result[1].name, "Book Two")
        XCTAssertEqual(result[1].bookUrl, "https://example.com/book/2")
    }

    func testSearchResultListRespectsTheFilter() throws {
        let html = """
        <div class="book"><h3><a href="/book/1">Book One</a></h3></div>
        <div class="book"><h3><a href="/book/2">Book Two</a></h3></div>
        """
        let source = makeSource(search: """
        {"bookList":"div.book","name":"h3 a@text","bookUrl":"h3 a@href"}
        """)
        let result = try BookListAssembler.analyzeBookList(
            bookSource: source,
            ruleData: RuleDataBox(),
            analyzeUrl: makeAnalyzeUrl(),
            baseUrl: "https://example.com/search",
            body: html,
            isSearch: true,
            filter: { name, _ in name == "Book Two" }
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "Book Two")
    }

    func testSearchResultListDropsEntriesWithoutAName() throws {
        let html = """
        <div class="book"><h3><a href="/book/1">Book One</a></h3></div>
        <div class="book"><span class="author">No title</span></div>
        """
        let source = makeSource(search: """
        {"bookList":"div.book","name":"h3 a@text","bookUrl":"h3 a@href"}
        """)
        let result = try BookListAssembler.analyzeBookList(
            bookSource: source,
            ruleData: RuleDataBox(),
            analyzeUrl: makeAnalyzeUrl(),
            baseUrl: "https://example.com/search",
            body: html,
            isSearch: true
        )
        XCTAssertEqual(result.count, 1)
    }

    func testTheReversePrefixFlipsTheList() throws {
        let html = """
        <div class="book"><h3><a href="/1">One</a></h3></div>
        <div class="book"><h3><a href="/2">Two</a></h3></div>
        """
        let source = makeSource(search: """
        {"bookList":"-div.book","name":"h3 a@text","bookUrl":"h3 a@href"}
        """)
        let result = try BookListAssembler.analyzeBookList(
            bookSource: source,
            ruleData: RuleDataBox(),
            analyzeUrl: makeAnalyzeUrl(),
            baseUrl: "https://example.com/search",
            body: html,
            isSearch: true
        )
        XCTAssertEqual(result.map(\.name), ["Two", "One"])
    }

    func testAnEmptyListFallsBackToTheDetailPage() throws {
        let html = "<h1 class=\"name\">The Book</h1><span class=\"author\">The Author</span>"
        let source = makeSource(
            search: "{\"bookList\":\"div.book\",\"name\":\"h1.name@text\"}",
            bookInfo: "{\"name\":\"h1.name@text\",\"author\":\"span.author@text\"}"
        )
        let result = try BookListAssembler.analyzeBookList(
            bookSource: source,
            ruleData: RuleDataBox(),
            analyzeUrl: makeAnalyzeUrl(),
            baseUrl: "https://example.com/book/1",
            body: html,
            isSearch: true
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "The Book")
        XCTAssertEqual(result[0].author, "The Author")
    }

    // MARK: - Detail page

    func testTheDetailPageIsParsed() throws {
        let html = """
        <h1 class="name">Detail Book</h1>
        <span class="author">Detail Author</span>
        <p class="intro">Detail intro</p>
        <a class="cover"><img src="/cover.jpg"></a>
        <a class="toc" href="/toc">目录</a>
        """
        let source = makeSource(bookInfo: """
        {"name":"h1.name@text","author":"span.author@text","intro":"p.intro@text","coverUrl":"a.cover img@src","tocUrl":"a.toc@href"}
        """)
        var book = Book()
        book.bookUrl = "https://example.com/book/1"
        let result = try BookInfoAssembler.analyzeBookInfo(
            bookSource: source,
            book: book,
            baseUrl: "https://example.com/book/1",
            redirectUrl: "https://example.com/book/1",
            body: html,
            canReName: true
        )
        XCTAssertEqual(result.name, "Detail Book")
        XCTAssertEqual(result.author, "Detail Author")
        XCTAssertEqual(result.intro, "Detail intro")
        XCTAssertEqual(result.coverUrl, "https://example.com/cover.jpg")
        XCTAssertEqual(result.tocUrl, "https://example.com/toc")
    }

    func testTheDetailPageKeepsTheOldNameWhenTheNewOneIsEmpty() throws {
        let html = "<span class=\"author\">Only The Author</span>"
        let source = makeSource(bookInfo: """
        {"name":"h1.name@text","author":"span.author@text"}
        """)
        var book = Book()
        book.name = "Old Name"
        let result = try BookInfoAssembler.analyzeBookInfo(
            bookSource: source,
            book: book,
            baseUrl: "https://example.com/book/1",
            redirectUrl: "https://example.com/book/1",
            body: html,
            canReName: false
        )
        XCTAssertEqual(result.name, "Old Name")
        XCTAssertEqual(result.author, "Only The Author")
    }

    /// Regression test: the upstream writes the parsed detail page back into
    /// the book; Swift has to return the parsed copy.
    func testTheNetworkDetailPageReturnsTheParsedBook() async throws {
        let html = """
        <h1 class="name">Detail Book</h1>
        <span class="author">Detail Author</span>
        <a class="toc" href="/toc">目录</a>
        """
        let source = makeSource(bookInfo: """
        {"name":"h1.name@text","author":"span.author@text","tocUrl":"a.toc@href"}
        """)
        var book = Book()
        book.bookUrl = "https://example.com/book/1"
        let client = StubHttpClient { request in
            HttpResponse(url: request.url, body: html)
        }
        let result = try await WebBook.getBookInfo(
            bookSource: source,
            book: book,
            dependencies: AnalyzeUrlDependencies(httpClient: client)
        )
        XCTAssertEqual(result.name, "Detail Book")
        XCTAssertEqual(result.author, "Detail Author")
        XCTAssertEqual(result.tocUrl, "https://example.com/toc")
    }

    // MARK: - Table of contents

    func testTheTableOfContentsIsParsed() async throws {
        let html = """
        <div class="list"><a href="/c1">Chapter 1</a><a href="/c2">Chapter 2</a></div>
        """
        let source = makeSource(toc: """
        {"chapterList":"div.list a","chapterName":"text","chapterUrl":"href"}
        """)
        var book = Book()
        book.bookUrl = "https://example.com/book/1"
        book.tocUrl = "https://example.com/book/1"
        let result = try await BookChapterListAssembler.analyzeChapterList(
            bookSource: source,
            book: book,
            baseUrl: "https://example.com/book/1",
            redirectUrl: "https://example.com/book/1",
            body: html
        )
        let chapters = result.chapters
        XCTAssertEqual(chapters.count, 2)
        // The list is reversed (the upstream default) and then reversed back.
        XCTAssertEqual(chapters.map(\.title), ["Chapter 1", "Chapter 2"])
        // Upstream stores the raw chapter URL — it is not resolved.
        XCTAssertEqual(chapters[0].url, "/c1")
        XCTAssertEqual(chapters[0].index, 0)
        XCTAssertEqual(chapters[1].index, 1)
        // The chapter-count fields travel back with the list.
        XCTAssertEqual(result.book.totalChapterNum, 2)
        XCTAssertEqual(result.book.latestChapterTitle, "Chapter 2")
    }

    func testTheTableOfContentsFollowsTheNextPage() async throws {
        let firstPage = """
        <div class="list"><a href="/c1">Chapter 1</a></div>
        <a class="next" href="/toc2">Next</a>
        """
        let secondPage = """
        <div class="list"><a href="/c2">Chapter 2</a></div>
        """
        let source = makeSource(toc: """
        {"chapterList":"div.list a","chapterName":"text","chapterUrl":"href","nextTocUrl":"a.next@href"}
        """)
        var book = Book()
        book.bookUrl = "https://example.com/book/1"
        book.tocUrl = "https://example.com/book/1"
        let result = try await BookChapterListAssembler.analyzeChapterList(
            bookSource: source,
            book: book,
            baseUrl: "https://example.com/book/1",
            redirectUrl: "https://example.com/book/1",
            body: firstPage,
            fetch: { url in
                XCTAssertEqual(url, "https://example.com/toc2")
                return secondPage
            }
        )
        let chapters = result.chapters
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters.map(\.title), ["Chapter 1", "Chapter 2"])
    }

    func testAnEmptyTableOfContentsThrows() async throws {
        let source = makeSource(toc: """
        {"chapterList":"div.list a","chapterName":"text","chapterUrl":"href"}
        """)
        var book = Book()
        book.bookUrl = "https://example.com/book/1"
        book.tocUrl = "https://example.com/book/1"
        do {
            _ = try await BookChapterListAssembler.analyzeChapterList(
                bookSource: source,
                book: book,
                baseUrl: "https://example.com/book/1",
                redirectUrl: "https://example.com/book/1",
                body: "<html><body></body></html>"
            )
            XCTFail("expected an empty table of contents to throw")
        } catch let error as PipelineError {
            XCTAssertEqual(error, .tocEmpty)
        }
    }

    // MARK: - Chapter content

    func testTheChapterContentIsParsed() async throws {
        let html = "<div class=\"content\"><p>First line.</p><p>Second line.</p></div>"
        let source = makeSource(content: """
        {"content":"div.content@html"}
        """)
        var book = Book()
        book.bookUrl = "https://example.com/book/1"
        book.tocUrl = "https://example.com/book/1"
        var chapter = BookChapter()
        chapter.url = "https://example.com/book/1/c1"
        chapter.title = "Chapter 1"
        chapter.bookUrl = book.bookUrl
        let content = try await BookContentAssembler.analyzeContent(
            bookSource: source,
            book: book,
            bookChapter: chapter,
            baseUrl: "https://example.com/book/1/c1",
            redirectUrl: "https://example.com/book/1/c1",
            body: html,
            nextChapterUrl: nil
        )
        XCTAssertTrue(content.contains("First line."))
        XCTAssertTrue(content.contains("Second line."))
    }

    func testTheContentReplacementIsApplied() async throws {
        let html = "<div class=\"content\"><p>alpha beta</p></div>"
        let source = makeSource(content: """
        {"content":"div.content@html","replaceRegex":"##beta##gamma"}
        """)
        var book = Book()
        book.bookUrl = "https://example.com/book/1"
        book.tocUrl = "https://example.com/book/1"
        var chapter = BookChapter()
        chapter.url = "https://example.com/book/1/c1"
        chapter.title = "Chapter 1"
        chapter.bookUrl = book.bookUrl
        let content = try await BookContentAssembler.analyzeContent(
            bookSource: source,
            book: book,
            bookChapter: chapter,
            baseUrl: "https://example.com/book/1/c1",
            redirectUrl: "https://example.com/book/1/c1",
            body: html,
            nextChapterUrl: nil
        )
        XCTAssertTrue(content.contains("alpha gamma"))
    }

    func testAnEmptyContentThrows() async throws {
        let source = makeSource(content: """
        {"content":"div.missing@html"}
        """)
        var book = Book()
        book.bookUrl = "https://example.com/book/1"
        book.tocUrl = "https://example.com/book/1"
        var chapter = BookChapter()
        chapter.url = "https://example.com/book/1/c1"
        chapter.title = "Chapter 1"
        chapter.bookUrl = book.bookUrl
        do {
            _ = try await BookContentAssembler.analyzeContent(
                bookSource: source,
                book: book,
                bookChapter: chapter,
                baseUrl: "https://example.com/book/1/c1",
                redirectUrl: "https://example.com/book/1/c1",
                body: "<html><body></body></html>",
                nextChapterUrl: nil
            )
            XCTFail("expected an empty content to throw")
        } catch let error as PipelineError {
            XCTAssertEqual(error, .contentEmpty)
        }
    }
}
