//
//  BookUpdateTests.swift
//  LegadoCoreTests
//
//  The table-of-contents update — upstream `ui/main/MainViewModel.updateToc`.
//

import XCTest
@testable import LegadoCore

final class BookUpdateTests: XCTestCase {

    // MARK: - The helpers

    /// A store with one book and one source.
    private func makeStore() throws -> (LegadoStore, Book, BookSource) {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        let source = BookSource(
            bookSourceUrl: "https://example.com",
            bookSourceName: "示例书源",
            searchUrl: "https://example.com/search?key={{key}}",
            ruleSearch: "{\"bookList\":\"class.item\"}",
            ruleToc: "{\"chapterList\":\"class.chapter\",\"chapterName\":\"text\",\"chapterUrl\":\"a@href\"}"
        )
        try store.insert(source)
        let book = Book(
            bookUrl: "https://example.com/book/1",
            tocUrl: "https://example.com/book/1/toc",
            origin: source.bookSourceUrl,
            name: "测试书",
            author: "作者",
            type: BookType.text,
            totalChapterNum: 2,
            durChapterIndex: 1,
            durChapterPos: 100,
            durChapterTime: 1_700_000_000_000,
            canUpdate: true
        )
        try store.insert(book)
        let chapters = [
            BookChapter(url: "c1", title: "第一章", bookUrl: book.bookUrl, index: 0),
            BookChapter(url: "c2", title: "第二章", bookUrl: book.bookUrl, index: 1)
        ]
        try store.insert(chapters)
        return (store, book, source)
    }

    // MARK: - The update

    func testTheMissingSourceMarksTheBookAsUpdateFailed() async throws {
        let (store, book, _) = try makeStore()
        // The source of the book is not in the store.
        var orphan = book
        orphan.origin = "https://example.com/missing"
        try store.update(orphan)
        let result = await BookUpdater.update(
            book: orphan,
            source: nil,
            store: store,
            dependencies: AnalyzeUrlDependencies()
        )
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.message, "书源不存在")
        XCTAssertTrue(result.book.type & BookType.updateError > 0)
        // The bit is persisted.
        let stored = try XCTUnwrap(store.book(url: book.bookUrl))
        XCTAssertTrue(stored.type & BookType.updateError > 0)
    }

    func testTheUpdateFailureMarksTheBookAsUpdateFailed() async throws {
        let (store, book, source) = try makeStore()
        // The stub answers nothing, so the TOC request fails.
        let result = await BookUpdater.update(
            book: book,
            source: source,
            store: store,
            dependencies: AnalyzeUrlDependencies(httpClient: StubClient())
        )
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.message.hasPrefix("更新目录失败"))
        XCTAssertTrue(result.book.type & BookType.updateError > 0)
    }

    func testTheUpdateReplacesTheChapters() async throws {
        let (store, book, source) = try makeStore()
        let client = StubClient(
            answers: [
                "https://example.com/book/1/toc": """
                <html><body>
                <a class="chapter" href="/book/1/1">第一章</a>
                <a class="chapter" href="/book/1/2">第二章</a>
                <a class="chapter" href="/book/1/3">第三章</a>
                </body></html>
                """
            ]
        )
        let result = await BookUpdater.update(
            book: book,
            source: source,
            store: store,
            dependencies: AnalyzeUrlDependencies(httpClient: client)
        )
        XCTAssertTrue(result.isSuccess, result.message)
        XCTAssertEqual(result.newChapterCount, 3)
        // The stored count was 2, so there is one new chapter.
        XCTAssertEqual(result.newChapterCountDelta, 1)
        XCTAssertTrue(result.hasNewChapters)
        // The chapters were replaced.
        let stored = try store.chapters(bookUrl: book.bookUrl)
        XCTAssertEqual(stored.count, 3)
        XCTAssertEqual(stored.last?.title, "第三章")
        // The book was written.
        let updated = try XCTUnwrap(store.book(url: book.bookUrl))
        XCTAssertEqual(updated.totalChapterNum, 3)
        XCTAssertEqual(updated.lastCheckCount, 1)
    }

    func testTheUpdateKeepsTheReadingProgress() async throws {
        let (store, book, source) = try makeStore()
        let client = StubClient(
            answers: [
                "https://example.com/book/1/toc": """
                <html><body>
                <a class="chapter" href="/book/1/1">第一章</a>
                <a class="chapter" href="/book/1/2">第二章</a>
                </body></html>
                """
            ]
        )
        let result = await BookUpdater.update(
            book: book,
            source: source,
            store: store,
            dependencies: AnalyzeUrlDependencies(httpClient: client)
        )
        XCTAssertTrue(result.isSuccess, result.message)
        // The progress of the stored book survives the update.
        XCTAssertEqual(result.book.durChapterIndex, 1)
        XCTAssertEqual(result.book.durChapterPos, 100)
        XCTAssertEqual(result.book.durChapterTime, 1_700_000_000_000)
    }

    func testTheUpdateClearsTheUpdateFailedBit() async throws {
        let (store, book, source) = try makeStore()
        var broken = book
        broken.type = broken.type | BookType.updateError
        try store.update(broken)
        let client = StubClient(
            answers: [
                "https://example.com/book/1/toc": """
                <html><body>
                <a class="chapter" href="/book/1/1">第一章</a>
                </body></html>
                """
            ]
        )
        let result = await BookUpdater.update(
            book: broken,
            source: source,
            store: store,
            dependencies: AnalyzeUrlDependencies(httpClient: client)
        )
        XCTAssertTrue(result.isSuccess, result.message)
        XCTAssertEqual(result.book.type & BookType.updateError, 0)
    }

    // MARK: - The batch update

    func testTheBatchUpdateSkipsTheLocalBooksAndTheOnesThatCannotBeUpdated() async throws {
        let (store, book, _) = try makeStore()
        var local = book
        local.bookUrl = "local"
        local.origin = BookType.localTag
        local.type = BookType.local
        try store.insert(local)
        var blocked = book
        blocked.bookUrl = "blocked"
        blocked.canUpdate = false
        try store.insert(blocked)
        let results = await BookUpdater.updateAll(
            books: [local, blocked, book],
            store: store,
            dependencies: AnalyzeUrlDependencies()
        )
        // Only the third book is updated.
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.bookUrl, book.bookUrl)
    }

    // MARK: - The reader check

    func testTheReaderCheckNeedsThreeUnreadChapters() {
        var book = Book(bookUrl: "https://example.com/book/1", canUpdate: true)
        book.lastCheckTime = 0
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertTrue(BookUpdater.shouldCheckForNewChapters(book: book, unreadChapters: 2, now: now))
        XCTAssertFalse(BookUpdater.shouldCheckForNewChapters(book: book, unreadChapters: 3, now: now))
    }

    func testTheReaderCheckIsThrottledToTenMinutes() {
        var book = Book(bookUrl: "https://example.com/book/1", canUpdate: true)
        let now = Date(timeIntervalSince1970: 1_000_000)
        book.lastCheckTime = Int64(now.timeIntervalSince1970 * 1000) - 60_000
        XCTAssertFalse(BookUpdater.shouldCheckForNewChapters(book: book, unreadChapters: 0, now: now))
        book.lastCheckTime = Int64(now.timeIntervalSince1970 * 1000) - 601_000
        XCTAssertTrue(BookUpdater.shouldCheckForNewChapters(book: book, unreadChapters: 0, now: now))
    }

    func testTheReaderCheckNeedsCanUpdate() {
        var book = Book(bookUrl: "https://example.com/book/1", canUpdate: false)
        book.lastCheckTime = 0
        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertFalse(BookUpdater.shouldCheckForNewChapters(book: book, unreadChapters: 0, now: now))
    }
}

/// A stub HTTP client — it answers from a table and records the requests.
final class StubClient: HttpClient, @unchecked Sendable {

    private let answers: [String: String]
    private let lock = NSLock()
    private var recorded: [String] = []

    init(answers: [String: String] = [:]) {
        self.answers = answers
    }

    var requested: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        lock.lock()
        recorded.append(request.url)
        lock.unlock()
        if let body = answers[request.url] {
            return HttpResponse(url: request.url, body: body, code: 200)
        }
        // A response that contains the URL, so the stub can answer a page
        // whose URL was rewritten.
        for (key, value) in answers where request.url.contains(key) {
            return HttpResponse(url: request.url, body: value, code: 200)
        }
        throw HttpError.invalidURL(request.url)
    }
}
