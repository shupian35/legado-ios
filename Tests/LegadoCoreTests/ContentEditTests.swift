import XCTest

@testable import LegadoCore

/// The content editor of the reader — upstream
/// `ui/book/read/ContentEditDialog.kt` — and the "a tip may be used only
/// once" rule of `TipConfigDialog.clearRepeat`.
final class ContentEditTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("legado-content-edit-\(UUID().uuidString)", isDirectory: true)
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

    private func makeChapter(_ index: Int, title: String = "第一章") -> BookChapter {
        BookChapter(
            url: "https://example.com/chapter/\(index)",
            title: title,
            isVolume: false,
            bookUrl: "https://example.com/book",
            index: Int64(index)
        )
    }

    private func makeStorage() -> BookCacheStorage {
        BookCacheStorage(layout: BookCacheLayout(root: root))
    }

    // MARK: - Loading

    func testLoadContentReturnsNilWhenTheChapterWasNeverDownloaded() {
        let book = makeBook()
        let chapter = makeChapter(1)
        let storage = makeStorage()
        XCTAssertNil(
            ContentEditService.loadContent(
                book: book,
                chapter: chapter,
                storage: storage
            )
        )
    }

    func testLoadContentReturnsTheCachedContent() throws {
        let book = makeBook()
        let chapter = makeChapter(1)
        let storage = makeStorage()
        try storage.saveText(book: book, chapter: chapter, content: "正文第一段")

        let content = ContentEditService.loadContent(
            book: book,
            chapter: chapter,
            storage: storage
        )
        XCTAssertEqual(content, "　　正文第一段")
    }

    /// The upstream shows the PROCESSED content — the title is not part of it
    /// (`ContentProcessor.getContent(book, chapter, content, includeTitle = false)`).
    func testLoadContentRemovesTheDuplicatedTitle() throws {
        let book = makeBook(name: "书名")
        let chapter = makeChapter(1, title: "第一章")
        let storage = makeStorage()
        try storage.saveText(book: book, chapter: chapter, content: "第一章\n正文内容")

        let content = ContentEditService.loadContent(
            book: book,
            chapter: chapter,
            storage: storage
        )
        XCTAssertEqual(content, "　　正文内容")
    }

    /// The replace rules of the content are applied — upstream
    /// `ContentProcessor.getContent` runs the content rules.
    func testLoadContentAppliesTheContentReplaceRules() throws {
        let book = makeBook()
        let chapter = makeChapter(1, title: "第一章")
        let storage = makeStorage()
        try storage.saveText(book: book, chapter: chapter, content: "这是一段正文")

        let rule = ReplaceRule(
            name: "替换",
            pattern: "正文",
            replacement: "内容",
            scopeContent: true
        )
        let content = ContentEditService.loadContent(
            book: book,
            chapter: chapter,
            storage: storage,
            contentRules: [rule]
        )
        XCTAssertEqual(content, "　　这是一段内容")
    }

    /// `book.useReplaceRule` is false ⇒ the rules are not applied.
    func testLoadContentSkipsTheRulesWhenTheBookOptsOut() throws {
        var book = makeBook()
        book.useReplaceRule = false
        let chapter = makeChapter(1, title: "第一章")
        let storage = makeStorage()
        try storage.saveText(book: book, chapter: chapter, content: "这是一段正文")

        let rule = ReplaceRule(
            name: "替换",
            pattern: "正文",
            replacement: "内容",
            scopeContent: true
        )
        let content = ContentEditService.loadContent(
            book: book,
            chapter: chapter,
            storage: storage,
            contentRules: [rule]
        )
        XCTAssertEqual(content, "　　这是一段正文")
    }

    // MARK: - Saving

    func testSaveContentWritesIntoTheCache() throws {
        let book = makeBook()
        let chapter = makeChapter(1)
        let storage = makeStorage()

        try ContentEditService.saveContent(
            book: book,
            chapter: chapter,
            content: "修改后的正文",
            storage: storage
        )
        XCTAssertEqual(storage.content(book: book, chapter: chapter), "修改后的正文")
        XCTAssertTrue(storage.hasContent(book: book, chapter: chapter))
    }

    func testSaveContentOverwritesTheOldContent() throws {
        let book = makeBook()
        let chapter = makeChapter(1)
        let storage = makeStorage()
        try storage.saveText(book: book, chapter: chapter, content: "旧的正文")

        try ContentEditService.saveContent(
            book: book,
            chapter: chapter,
            content: "新的正文",
            storage: storage
        )
        XCTAssertEqual(storage.content(book: book, chapter: chapter), "新的正文")
    }

    // MARK: - Resetting

    /// The reset deletes the cached content — for a local book there is
    /// nothing to download, so the content is simply gone.
    func testResetContentDeletesTheCacheOfALocalBook() async throws {
        var book = makeBook()
        book.origin = "loc_book::local"
        book.type = BookType.local
        let chapter = makeChapter(1)
        let storage = makeStorage()
        try storage.saveText(book: book, chapter: chapter, content: "正文")

        let content = await ContentEditService.resetContent(
            book: book,
            chapter: chapter,
            storage: storage,
            source: nil
        )
        XCTAssertNil(content)
        XCTAssertFalse(storage.hasContent(book: book, chapter: chapter))
    }

    // MARK: - The tip rule

    /// Upstream `TipConfigDialog.clearRepeat` — a tip may be used only once.
    func testClearRepeatedTipClearsTheOtherSlots() {
        var config = ReaderConfig()
        config.tipHeaderLeft = ReaderTipType.chapterTitle.rawValue
        config.tipHeaderRight = ReaderTipType.chapterTitle.rawValue
        config.tipFooterLeft = ReaderTipType.page.rawValue

        config.clearRepeatedTip(ReaderTipType.chapterTitle.rawValue)

        XCTAssertEqual(config.tipHeaderLeft, ReaderTipType.none.rawValue)
        XCTAssertEqual(config.tipHeaderRight, ReaderTipType.none.rawValue)
        // The other tips are not touched.
        XCTAssertEqual(config.tipFooterLeft, ReaderTipType.page.rawValue)
    }

    func testClearRepeatedTipKeepsTheNoneValue() {
        var config = ReaderConfig()
        config.tipHeaderLeft = ReaderTipType.chapterTitle.rawValue

        config.clearRepeatedTip(ReaderTipType.none.rawValue)

        XCTAssertEqual(config.tipHeaderLeft, ReaderTipType.chapterTitle.rawValue)
    }
}
