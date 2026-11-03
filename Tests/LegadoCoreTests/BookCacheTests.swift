import XCTest

@testable import LegadoCore

final class BookCacheTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("legado-cache-\(UUID().uuidString)", isDirectory: true)
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

    private func makeChapter(_ index: Int, title: String? = nil, isVolume: Bool = false) -> BookChapter {
        BookChapter(
            url: "https://example.com/chapter/\(index)",
            title: title ?? "第\(index)章",
            isVolume: isVolume,
            bookUrl: "https://example.com/book",
            index: Int64(index)
        )
    }

    private func makeStorage() -> BookCacheStorage {
        BookCacheStorage(layout: BookCacheLayout(root: root))
    }

    // MARK: - Layout

    func testFolderNameStripsIllegalCharactersAndUsesNineChars() {
        let book = makeBook(name: "a/b\\c:d*e?f\"g<h>i|j.k")
        let folder = BookCacheLayout.folderName(for: book)
        // The illegal characters are dropped, then only the first nine remain.
        XCTAssertEqual(folder, "abcdefgh" + "i" + ScriptDigest.md5Encode16(book.bookUrl))
        XCTAssertFalse(folder.contains("/"))
    }

    func testChapterFileNameFormat() {
        let chapter = makeChapter(7, title: "第七章")
        let name = BookCacheLayout.chapterFileName(for: chapter)
        XCTAssertTrue(name.hasPrefix("00007-"))
        XCTAssertTrue(name.hasSuffix(".nb"))
        XCTAssertEqual(name.count, "00007-".count + 16 + ".nb".count)
    }

    // MARK: - Storage

    func testSaveReadDeleteRoundTrip() throws {
        let storage = makeStorage()
        let book = makeBook()
        let chapter = makeChapter(1)

        XCTAssertFalse(storage.hasContent(book: book, chapter: chapter))
        XCTAssertNil(storage.content(book: book, chapter: chapter))

        try storage.saveText(book: book, chapter: chapter, content: "正文")
        XCTAssertTrue(storage.hasContent(book: book, chapter: chapter))
        XCTAssertEqual(storage.content(book: book, chapter: chapter), "正文")

        storage.deleteContent(book: book, chapter: chapter)
        XCTAssertFalse(storage.hasContent(book: book, chapter: chapter))
    }

    func testEmptyContentIsNotWritten() throws {
        let storage = makeStorage()
        let book = makeBook()
        let chapter = makeChapter(1)
        try storage.saveText(book: book, chapter: chapter, content: "")
        XCTAssertFalse(storage.hasContent(book: book, chapter: chapter))
    }

    func testLocalTxtBookAlwaysHasContent() {
        let storage = makeStorage()
        let book = Book(
            bookUrl: "/tmp/a.txt",
            origin: BookType.localTag,
            originName: "a.txt",
            name: "本地",
            type: BookType.local
        )
        XCTAssertTrue(storage.hasContent(book: book, chapter: makeChapter(0)))
        XCTAssertEqual(storage.chapterFileNames(book: book), [])
    }

    func testImageSourcesResolveAgainstChapterURL() {
        let content = "文字<img src=\"/img/a.png\"/>中间<img class='x' src=\"b.jpg\">尾"
        let sources = BookCacheStorage.imageSources(
            in: content,
            chapterURL: "https://example.com/dir/chapter/1"
        )
        XCTAssertEqual(
            sources,
            ["https://example.com/img/a.png", "https://example.com/dir/chapter/b.jpg"]
        )
    }

    func testHasImageContentRequiresEveryImage() throws {
        let storage = makeStorage()
        let book = makeBook()
        let chapter = makeChapter(1)
        let content = "<img src=\"/a.png\"/>"
        try storage.saveText(book: book, chapter: chapter, content: content)

        XCTAssertFalse(storage.hasImageContent(book: book, chapter: chapter))

        try storage.saveImage(book: book, src: "https://example.com/a.png", data: Data([1, 2, 3]))
        XCTAssertTrue(storage.hasImageContent(book: book, chapter: chapter))
    }

    // MARK: - Manager

    private func makeManager(
        chapters: [BookChapter],
        storage: BookCacheStorage,
        content: @escaping @Sendable (BookChapter) async throws -> String,
        images: (@Sendable (String) async throws -> Data)? = nil,
        configuration: CacheBookManager.Configuration = .init(threadCount: 2, retryDelay: 0)
    ) -> CacheBookManager {
        let table = Dictionary(uniqueKeysWithValues: chapters.map { (Int($0.index), $0) })
        return CacheBookManager(
            storage: storage,
            configuration: configuration,
            chapterLoader: { _, index in table[index] },
            contentFetcher: { _, _, chapter in try await content(chapter) },
            imageFetcher: images.map { fetch in { _, src in try await fetch(src) } }
        )
    }

    func testDownloadsEveryChapterIntoTheCache() async throws {
        let storage = makeStorage()
        let book = makeBook()
        let chapters = (0..<4).map { makeChapter($0) }
        let calls = Counter()

        let manager = makeManager(chapters: chapters, storage: storage) { chapter in
            await calls.increment()
            return "正文\(chapter.index)"
        }

        try await manager.start(book: book, source: BookSource(bookSourceUrl: "https://example.com"), start: 0, end: 3)
        await manager.run()

        for chapter in chapters {
            XCTAssertEqual(storage.content(book: book, chapter: chapter), "正文\(chapter.index)")
        }
        let callCount = await calls.value
        XCTAssertEqual(callCount, 4)
        let progress = await manager.progress()
        XCTAssertEqual(progress.succeeded, 4)
        XCTAssertEqual(progress.failed, 0)
        XCTAssertTrue(progress.isIdle)
    }

    func testVolumeChapterIsSkippedButCounted() async throws {
        let storage = makeStorage()
        let book = makeBook()
        let chapters = [makeChapter(0, title: "第一卷", isVolume: true), makeChapter(1)]
        let calls = Counter()

        let manager = makeManager(chapters: chapters, storage: storage) { chapter in
            await calls.increment()
            return "正文\(chapter.index)"
        }

        try await manager.start(book: book, source: BookSource(bookSourceUrl: "https://example.com"), start: 0, end: 1)
        await manager.run()

        let callCount = await calls.value
        XCTAssertEqual(callCount, 1)
        XCTAssertFalse(storage.hasContent(book: book, chapter: chapters[0]))
        XCTAssertEqual(storage.content(book: book, chapter: chapters[1]), "正文1")
        let volumeProgress = await manager.progress()
        XCTAssertEqual(volumeProgress.succeeded, 2)
    }

    func testRetriesThenSucceeds() async throws {
        let storage = makeStorage()
        let book = makeBook()
        let chapters = [makeChapter(0)]
        let calls = Counter()

        let manager = makeManager(chapters: chapters, storage: storage) { _ in
            let attempt = await calls.increment()
            if attempt < 3 {
                throw CacheBookError.emptyContent("boom")
            }
            return "正文"
        }

        try await manager.start(book: book, source: BookSource(bookSourceUrl: "https://example.com"), start: 0, end: 0)
        await manager.run()

        let callCount = await calls.value
        XCTAssertEqual(callCount, 3)
        XCTAssertEqual(storage.content(book: book, chapter: chapters[0]), "正文")
        let retryProgress = await manager.progress()
        XCTAssertEqual(retryProgress.failed, 0)
    }

    func testFailuresAreRecordedAfterRetries() async throws {
        let storage = makeStorage()
        let book = makeBook()
        let chapters = [makeChapter(0)]

        let manager = makeManager(
            chapters: chapters,
            storage: storage,
            content: { _ in throw CacheBookError.emptyContent("一直失败") },
            configuration: .init(threadCount: 1, maxRetries: 2, retryDelay: 0)
        )

        try await manager.start(book: book, source: BookSource(bookSourceUrl: "https://example.com"), start: 0, end: 0)
        await manager.run()

        XCTAssertFalse(storage.hasContent(book: book, chapter: chapters[0]))
        let progress = await manager.progress()
        XCTAssertEqual(progress.failed, 1)
        XCTAssertEqual(progress.succeeded, 0)
        let failures = await manager.failures
        XCTAssertEqual(failures.count, 1)
    }

    func testFullyCachedChapterIsNotFetched() async throws {
        let storage = makeStorage()
        let book = makeBook()
        let chapter = makeChapter(0)
        try storage.saveText(book: book, chapter: chapter, content: "已缓存")

        let calls = Counter()
        let manager = makeManager(chapters: [chapter], storage: storage) { _ in
            await calls.increment()
            return "新内容"
        }

        try await manager.start(book: book, source: BookSource(bookSourceUrl: "https://example.com"), start: 0, end: 0)
        await manager.run()

        let callCount = await calls.value
        XCTAssertEqual(callCount, 0)
        XCTAssertEqual(storage.content(book: book, chapter: chapter), "已缓存")
        let cachedProgress = await manager.progress()
        XCTAssertEqual(cachedProgress.succeeded, 1)
    }

    func testCachedTextRefetchesOnlyMissingImages() async throws {
        let storage = makeStorage()
        let book = makeBook()
        let chapter = makeChapter(0)
        try storage.saveText(book: book, chapter: chapter, content: "<img src=\"/a.png\"/>")

        let textCalls = Counter()
        let imageCalls = Counter()
        let manager = makeManager(
            chapters: [chapter],
            storage: storage,
            content: { _ in
                await textCalls.increment()
                return "不该被调用"
            },
            images: { _ in
                await imageCalls.increment()
                return Data([1])
            }
        )

        try await manager.start(book: book, source: BookSource(bookSourceUrl: "https://example.com"), start: 0, end: 0)
        await manager.run()

        let textCount = await textCalls.value
        XCTAssertEqual(textCount, 0)
        let imageCount = await imageCalls.value
        XCTAssertEqual(imageCount, 1)
        XCTAssertTrue(storage.hasImage(book: book, src: "https://example.com/a.png"))
    }

    func testLocalBookIsNotDownloaded() async throws {
        let storage = makeStorage()
        let book = Book(
            bookUrl: "/tmp/a.txt",
            origin: BookType.localTag,
            originName: "a.txt",
            name: "本地",
            type: BookType.local
        )
        let manager = makeManager(chapters: [makeChapter(0)], storage: storage) { _ in "x" }
        try await manager.start(
            book: book,
            source: BookSource(bookSourceUrl: "https://example.com"),
            start: 0,
            end: 0
        )
        await manager.run()
        let localProgress = await manager.progress()
        XCTAssertEqual(localProgress.succeeded, 0)
    }

    func testStopClearsTheQueue() async throws {
        let storage = makeStorage()
        let book = makeBook()
        let chapters = (0..<3).map { makeChapter($0) }
        let manager = makeManager(chapters: chapters, storage: storage) { _ in "x" }

        try await manager.start(
            book: book,
            source: BookSource(bookSourceUrl: "https://example.com"),
            start: 0,
            end: 2
        )
        await manager.stop(bookUrl: book.bookUrl)
        await manager.run()

        let stoppedProgress = await manager.progress()
        XCTAssertEqual(stoppedProgress.waiting, 0)
        XCTAssertFalse(storage.hasContent(book: book, chapter: chapters[0]))
    }

    func testProgressSummaryFormat() {
        let progress = CacheBookProgress(waiting: 2, downloading: 1, failed: 3, succeeded: 4)
        XCTAssertEqual(progress.summary, "正在下载:1|等待中:2|失败:3|成功:4")
        XCTAssertFalse(progress.isIdle)
    }
}

/// A tiny actor counter the test closures can mutate concurrently.
private actor Counter {
    private(set) var value = 0

    @discardableResult
    func increment() -> Int {
        value += 1
        return value
    }
}
