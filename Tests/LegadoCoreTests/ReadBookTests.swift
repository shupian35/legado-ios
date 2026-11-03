//
//  ReadBookTests.swift
//  LegadoCoreTests
//
//  Tests for `Reader/ReadBook.swift` and `Reader/ChapterProvider.swift`.
//

import XCTest
@testable import LegadoCore

/// Hands the chapter text back from a dictionary.
private final class StubContentProvider: ChapterContentProviding {
    var contents: [Int: String]
    private(set) var requested: [Int] = []

    init(contents: [Int: String]) {
        self.contents = contents
    }

    func chapterContent(book: Book, chapter: BookChapter) async throws -> String? {
        requested.append(Int(chapter.index))
        return contents[Int(chapter.index)]
    }
}

/// Records the persisted books.
private final class StubPersister: ReadProgressPersisting {
    private(set) var saved: [Book] = []

    func saveBook(_ book: Book) throws {
        saved.append(book)
    }

    func loadChapters(bookUrl: String) throws -> [BookChapter] {
        []
    }
}

private final class StubDelegate: ReadBookDelegate {
    private(set) var loaded: [Int] = []
    private(set) var pageIndexes: [Int] = []
    private(set) var failed: [Error] = []

    func readBook(_ readBook: ReadBook, didLoad chapter: TextChapter, position: Int) {
        loaded.append(position)
    }

    func readBook(_ readBook: ReadBook, didChangePageIndex index: Int) {
        pageIndexes.append(index)
    }

    func readBook(_ readBook: ReadBook, didSaveProgress book: Book) {}

    func readBook(_ readBook: ReadBook, didFail error: Error) {
        failed.append(error)
    }
}

private func makeBook(chapterIndex: Int = 0, chapterPos: Int = 0) -> Book {
    var book = Book()
    book.name = "测试书"
    book.author = "作者"
    book.bookUrl = "book://1"
    book.origin = "book://1"
    book.type = BookType.text
    book.durChapterIndex = Int64(chapterIndex)
    book.durChapterPos = Int64(chapterPos)
    return book
}

private func makeChapters(count: Int = 3) -> [BookChapter] {
    (0..<count).map { index in
        var chapter = BookChapter()
        chapter.index = Int64(index)
        chapter.title = "第\(index + 1)章"
        chapter.url = "/c\(index)"
        chapter.bookUrl = "book://1"
        return chapter
    }
}

private func makeLayout(width: Double = 300, height: Double = 400) -> ReaderLayout {
    var config = ReaderConfig()
    config.paddingTop = 0
    config.paddingBottom = 0
    config.paddingLeft = 0
    config.paddingRight = 0
    config.lineSpacingExtra = 0
    config.paragraphSpacing = 0
    config.titleTopSpacing = 0
    config.titleBottomSpacing = 0
    return ReaderLayout(
        config: config,
        size: CGSizeLike(width: width, height: height),
        measurer: ApproximateTextMeasurer()
    )
}

final class ReadBookTests: XCTestCase {
    func testLoadsTheCurrentChapter() async {
        let provider = StubContentProvider(contents: [0: "第一章的内容", 1: "第二章的内容"])
        let readBook = ReadBook(
            book: makeBook(),
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout() }
        )

        await readBook.loadCurrentChapter()

        XCTAssertNotNil(readBook.curTextChapter)
        XCTAssertEqual(readBook.curTextChapter?.pageSize, 1)
        XCTAssertEqual(readBook.pageIndex, 0)
        XCTAssertEqual(readBook.durChapterTitle, "第1章")
    }

    // MARK: - The new chapters (upstream `ReadBook.upToc`)

    func testTheNewChapterCheckReplacesTheListWhenItGrew() async {
        let provider = StubContentProvider(contents: [0: "第一章的内容"])
        var book = makeBook()
        book.canUpdate = true
        book.lastCheckTime = 0
        let readBook = ReadBook(
            book: book,
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout() }
        )

        let refreshed = await readBook.checkForNewChapters { _ in makeChapters(count: 5) }

        XCTAssertEqual(refreshed, 5)
        XCTAssertEqual(readBook.chapterList.count, 5)
        // The check time is stamped before the request.
        XCTAssertGreaterThan(readBook.book.lastCheckTime, 0)
    }

    func testTheNewChapterCheckIsSkippedWhenThreeChaptersAreLeft() async {
        let provider = StubContentProvider(contents: [0: "第一章的内容"])
        var book = makeBook(chapterIndex: 0)
        book.canUpdate = true
        book.lastCheckTime = 0
        let readBook = ReadBook(
            book: book,
            chapterList: makeChapters(count: 5),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout() }
        )

        let refreshed = await readBook.checkForNewChapters { _ in makeChapters(count: 9) }

        XCTAssertNil(refreshed)
        XCTAssertEqual(readBook.chapterList.count, 5)
    }

    func testTheNewChapterCheckIsSkippedWithoutARefresher() async {
        let provider = StubContentProvider(contents: [0: "第一章的内容"])
        let readBook = ReadBook(
            book: makeBook(),
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout() }
        )
        let refreshed = await readBook.checkForNewChapters(refresher: nil)
        XCTAssertNil(refreshed)
    }

    func testRestoresThePageFromTheSavedPosition() async {
        // Ten paragraphs of ten characters each; with a 400 pt page that is
        // several pages, so the saved position lands on a page after the first.
        let content = (0..<20).map { _ in String(repeating: "字", count: 10) }.joined(separator: "\n")
        let provider = StubContentProvider(contents: [0: content])
        var book = makeBook(chapterPos: 200)
        book.durChapterPos = 200
        let readBook = ReadBook(
            book: book,
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout(height: 100) }
        )

        await readBook.loadCurrentChapter()

        let chapter = try? XCTUnwrap(readBook.curTextChapter)
        XCTAssertGreaterThan(chapter?.pageSize ?? 0, 1)
        XCTAssertGreaterThan(readBook.pageIndex, 0)
    }

    /// The page size changed (the device was rotated) — the chapter is laid
    /// out again with the new layout and the reading position is kept.
    func testReloadingTheChapterUsesTheNewLayout() async {
        // The paragraphs are wider than the narrow page, so they are split
        // into several lines — on the wide page they fit on one line.
        let content = (0..<20).map { _ in String(repeating: "字", count: 40) }.joined(separator: "\n")
        let provider = StubContentProvider(contents: [0: content])
        var book = makeBook(chapterPos: 200)
        book.durChapterPos = 200
        var layout = makeLayout(width: 300, height: 100)
        let readBook = ReadBook(
            book: book,
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { layout }
        )

        await readBook.loadCurrentChapter()
        let narrowPages = readBook.curTextChapter?.pageSize ?? 0

        // The device was rotated — the page is wider now.
        layout = makeLayout(width: 900, height: 100)
        await readBook.reloadCurrentChapter()

        let widePages = readBook.curTextChapter?.pageSize ?? 0
        XCTAssertLessThan(widePages, narrowPages)
        // The reading position is kept — the page that holds it is restored
        // (the page index itself changes, the pages are different).
        XCTAssertEqual(readBook.durChapterPos, 200)
        XCTAssertEqual(readBook.pageIndex, readBook.curTextChapter?.pageIndex(forCharacterIndex: 200))
    }

    func testMovesToTheNextAndPreviousChapter() async {
        let provider = StubContentProvider(contents: [0: "a", 1: "b", 2: "c"])
        let readBook = ReadBook(
            book: makeBook(),
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout() }
        )

        await readBook.loadCurrentChapter()
        let moved = await readBook.moveToNextChapter()
        XCTAssertTrue(moved)
        XCTAssertEqual(readBook.durChapterIndex, 1)

        let back = await readBook.moveToPrevChapter()
        XCTAssertTrue(back)
        XCTAssertEqual(readBook.durChapterIndex, 0)

        let beyond = await readBook.moveToPrevChapter()
        XCTAssertFalse(beyond)
    }

    func testTheLastChapterCannotMoveForward() async {
        let provider = StubContentProvider(contents: [2: "c"])
        var book = makeBook(chapterIndex: 2)
        book.durChapterIndex = 2
        let readBook = ReadBook(
            book: book,
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout() }
        )

        await readBook.loadCurrentChapter()
        let moved = await readBook.moveToNextChapter()
        XCTAssertFalse(moved)
        XCTAssertEqual(readBook.durChapterIndex, 2)
    }

    func testSavingTheProgressPersistsTheBook() async {
        let provider = StubContentProvider(contents: [0: "内容"])
        let persister = StubPersister()
        let readBook = ReadBook(
            book: makeBook(),
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout() }
        )
        readBook.persister = persister

        await readBook.loadCurrentChapter()
        await readBook.saveRead(pageChanged: true)

        XCTAssertEqual(persister.saved.count, 1)
        XCTAssertEqual(persister.saved.first?.durChapterIndex, 0)
        XCTAssertEqual(persister.saved.first?.durChapterTitle, "第1章")
        XCTAssertGreaterThan(persister.saved.first?.durChapterTime ?? 0, 0)
    }

    func testMergingARemoteProgress() async {
        let provider = StubContentProvider(contents: [0: "a", 1: "b", 2: "c"])
        let readBook = ReadBook(
            book: makeBook(),
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout() }
        )

        // A further remote progress wins.
        let further = BookProgress(
            name: "测试书",
            author: "作者",
            durChapterIndex: 2,
            durChapterPos: 10,
            durChapterTime: 1,
            durChapterTitle: "第3章"
        )
        XCTAssertTrue(readBook.mergeRemoteProgress(further))
        XCTAssertEqual(readBook.durChapterIndex, 2)

        // A closer local progress beats an older remote one.
        let behind = BookProgress(
            name: "测试书",
            author: "作者",
            durChapterIndex: 0,
            durChapterPos: 0,
            durChapterTime: 1,
            durChapterTitle: "第1章"
        )
        XCTAssertFalse(readBook.mergeRemoteProgress(behind))
        XCTAssertEqual(readBook.durChapterIndex, 2)
    }

    func testPreloadingLoadsTheNeighbours() async {
        let provider = StubContentProvider(contents: [0: "a", 1: "b", 2: "c"])
        var book = makeBook(chapterIndex: 1)
        book.durChapterIndex = 1
        let readBook = ReadBook(
            book: book,
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout() }
        )

        await readBook.loadCurrentChapter()
        await readBook.preloadNeighbours()

        XCTAssertNotNil(readBook.nextTextChapter)
        XCTAssertNotNil(readBook.prevTextChapter)
        XCTAssertTrue(provider.requested.contains(0))
        XCTAssertTrue(provider.requested.contains(2))
    }

    func testMovingThePageIndexUpdatesThePosition() async {
        let content = (0..<20).map { _ in String(repeating: "字", count: 10) }.joined(separator: "\n")
        let provider = StubContentProvider(contents: [0: content])
        let readBook = ReadBook(
            book: makeBook(),
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout(height: 100) }
        )

        await readBook.loadCurrentChapter()
        readBook.updatePageIndex(1)

        XCTAssertEqual(readBook.pageIndex, 1)
        XCTAssertGreaterThan(readBook.durChapterPos, 0)
        XCTAssertGreaterThan(readBook.progress, 0)
    }

    func testAnEmptyChapterStillProducesAPage() async {
        let provider = StubContentProvider(contents: [0: ""])
        let readBook = ReadBook(
            book: makeBook(),
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout() }
        )

        await readBook.loadCurrentChapter()

        XCTAssertNotNil(readBook.curTextChapter)
        XCTAssertGreaterThanOrEqual(readBook.curTextChapter?.pageSize ?? 0, 1)
    }

    func testTheDelegateHearsTheLoadAndThePageChange() async {
        let provider = StubContentProvider(contents: [0: "内容"])
        let delegate = StubDelegate()
        let readBook = ReadBook(
            book: makeBook(),
            chapterList: makeChapters(),
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { makeLayout() }
        )
        readBook.delegate = delegate

        await readBook.loadCurrentChapter()

        XCTAssertEqual(delegate.loaded.count, 1)
        XCTAssertEqual(delegate.pageIndexes, [0])
        XCTAssertTrue(delegate.failed.isEmpty)
    }
}

final class ChapterProviderTests: XCTestCase {
    func testBuildsAPaginatedChapter() async throws {
        let chapter = makeChapters(count: 1)[0]
        let provider = StubContentProvider(contents: [0: "第一段\n第二段"])

        let textChapter = try await ChapterProvider.textChapter(
            book: makeBook(),
            chapter: chapter,
            chaptersSize: 1,
            contentProvider: provider,
            config: ReaderConfig(),
            layout: makeLayout(),
            measurer: ApproximateTextMeasurer()
        )

        XCTAssertGreaterThanOrEqual(textChapter.pageSize, 1)
        XCTAssertTrue(textChapter.isCompleted)
        XCTAssertEqual(textChapter.position, 0)
        XCTAssertEqual(textChapter.title, "第1章")
    }

    func testTheTitleBecomesTheFirstLine() async throws {
        let chapter = makeChapters(count: 1)[0]
        let provider = StubContentProvider(contents: [0: "内容"])

        let textChapter = try await ChapterProvider.textChapter(
            book: makeBook(),
            chapter: chapter,
            chaptersSize: 1,
            contentProvider: provider,
            config: ReaderConfig(),
            layout: makeLayout(),
            measurer: ApproximateTextMeasurer()
        )

        XCTAssertEqual(textChapter.page(at: 0)?.lines.first?.text, "第1章")
        XCTAssertEqual(textChapter.page(at: 0)?.lines.first?.isTitle, true)
    }

    func testTheTitleModeTwoHidesTheTitle() async throws {
        var config = ReaderConfig()
        config.titleMode = 2
        let chapter = makeChapters(count: 1)[0]
        let provider = StubContentProvider(contents: [0: "内容"])

        let textChapter = try await ChapterProvider.textChapter(
            book: makeBook(),
            chapter: chapter,
            chaptersSize: 1,
            contentProvider: provider,
            config: config,
            layout: makeLayout(),
            measurer: ApproximateTextMeasurer()
        )

        // With `includeTitle = false` every paragraph is indented — including
        // the first one (ContentProcessor.kt:196-200).
        XCTAssertEqual(textChapter.page(at: 0)?.lines.first?.text, "　　内容")
    }

    func testAMissingContentProducesAnEmptyChapter() async throws {
        let chapter = makeChapters(count: 1)[0]
        let provider = StubContentProvider(contents: [:])

        let textChapter = try await ChapterProvider.textChapter(
            book: makeBook(),
            chapter: chapter,
            chaptersSize: 1,
            contentProvider: provider,
            config: ReaderConfig(),
            layout: makeLayout(),
            measurer: ApproximateTextMeasurer()
        )

        XCTAssertGreaterThanOrEqual(textChapter.pageSize, 1)
    }

    func testTheReplaceRulesAreApplied() async throws {
        let chapter = makeChapters(count: 1)[0]
        let provider = StubContentProvider(contents: [0: "广告内容"])
        var rule = ReplaceRule()
        rule.pattern = "广告"
        rule.replacement = ""
        rule.scopeContent = true
        rule.isEnabled = true

        let textChapter = try await ChapterProvider.textChapter(
            book: makeBook(),
            chapter: chapter,
            chaptersSize: 1,
            contentProvider: provider,
            contentRules: [rule],
            config: ReaderConfig(),
            layout: makeLayout(),
            measurer: ApproximateTextMeasurer()
        )

        let text = textChapter.page(at: 0)?.lines.map(\.text).joined() ?? ""
        XCTAssertFalse(text.contains("广告"))
        XCTAssertEqual(textChapter.effectiveReplaceRules?.count, 1)
    }

    func testTheDisplayTitleHonoursTheTitleMode() {
        let chapter = makeChapters(count: 1)[0]
        var config = ReaderConfig()
        XCTAssertEqual(
            ChapterProvider.displayTitle(
                book: makeBook(),
                chapter: chapter,
                titleRules: [],
                scriptEngine: nil,
                config: config
            ),
            "第1章"
        )
        config.titleMode = 2
        XCTAssertEqual(
            ChapterProvider.displayTitle(
                book: makeBook(),
                chapter: chapter,
                titleRules: [],
                scriptEngine: nil,
                config: config
            ),
            ""
        )
    }
}
