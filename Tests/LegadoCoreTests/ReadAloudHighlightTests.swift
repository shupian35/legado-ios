//
//  ReadAloudHighlightTests.swift
//  LegadoCoreTests
//
//  Tests for the read-aloud highlight: the mapping of the spoken paragraph
//  onto the visible page and the highlight itself.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/ReadBookActivity.kt:1658-1682
//  app/src/main/java/io/legado/app/ui/book/read/page/entities/TextPage.kt:206-220
//

import XCTest
@testable import LegadoCore

final class ReadAloudHighlightTests: XCTestCase {

    // MARK: - Helpers

    /// A chapter with two pages of ten characters each.
    private func makeChapter() -> TextChapter {
        let chapter = TextChapter(
            chapter: BookChapter(url: "https://example.com/1", title: "第一章"),
            position: 0,
            title: "第一章",
            chaptersSize: 1,
            sameTitleRemoved: false,
            isVip: false,
            isPay: false
        )
        for index in 0..<2 {
            let page = TextPage()
            page.index = index
            page.chapterIndex = 0
            page.chapterSize = 1
            let line = TextLine()
            line.text = String(repeating: "字", count: 10)
            line.chapterPosition = index * 10
            page.addLine(line)
            // The page holds the text of its lines — the upstream builds it
            // while the lines are added.
            page.text = line.text
            page.isCompleted = true
            chapter.addPage(page)
        }
        chapter.isCompleted = true
        return chapter
    }

    // MARK: - The position mapping

    func testThePageThatHoldsTheOffset() {
        let chapter = makeChapter()
        XCTAssertEqual(ReadAloudPosition.pageIndex(forChapterOffset: 0, in: chapter), 0)
        XCTAssertEqual(ReadAloudPosition.pageIndex(forChapterOffset: 9, in: chapter), 0)
        XCTAssertEqual(ReadAloudPosition.pageIndex(forChapterOffset: 10, in: chapter), 1)
        XCTAssertEqual(ReadAloudPosition.pageIndex(forChapterOffset: 19, in: chapter), 1)
    }

    func testTheSpanStartIsRelativeToThePage() {
        let chapter = makeChapter()
        // Upstream `aloudSpanStart = chapterStart - getReadLength(pageIndex)`.
        XCTAssertEqual(ReadAloudPosition.aloudSpanStart(chapterOffset: 2, in: chapter), 0)
        XCTAssertEqual(ReadAloudPosition.aloudSpanStart(chapterOffset: 12, in: chapter), 10)
    }

    func testTheChapterOffsetOfAParagraph() {
        let paragraph = ReadAloudParagraph(index: 1, text: "第二段", start: 12, end: 15)
        XCTAssertEqual(ReadAloudPosition.chapterOffset(of: paragraph), 12)
    }

    // MARK: - The highlight

    func testTheHighlightCoversTheWholeParagraph() {
        let page = TextPage()
        // Three lines; the second one ends the paragraph.
        for (index, text) in ["甲甲甲", "乙乙乙", "丙丙丙"].enumerated() {
            let line = TextLine()
            line.text = text
            line.chapterPosition = index * 3
            line.isParagraphEnd = index == 1
            page.addLine(line)
        }
        // The span starts in the second line — the whole paragraph (the
        // second line and the line before it) is highlighted.
        page.updatePageAloudSpan(aloudSpanStart: 4)
        XCTAssertTrue(page.lines[0].isReadAloud)
        XCTAssertTrue(page.lines[1].isReadAloud)
        XCTAssertFalse(page.lines[2].isReadAloud)
        // The highlight is removed again.
        page.removePageAloudSpan()
        XCTAssertFalse(page.lines[0].isReadAloud)
        XCTAssertFalse(page.lines[1].isReadAloud)
    }

    func testTheHighlightOfTheLastParagraphStopsAtTheEnd() {
        let page = TextPage()
        for (index, text) in ["甲甲甲", "乙乙乙"].enumerated() {
            let line = TextLine()
            line.text = text
            line.chapterPosition = index * 3
            line.isParagraphEnd = index == 1
            page.addLine(line)
        }
        page.updatePageAloudSpan(aloudSpanStart: 4)
        XCTAssertTrue(page.lines[0].isReadAloud)
        XCTAssertTrue(page.lines[1].isReadAloud)
    }

    // MARK: - The reading position follows the speech

    func testMovingToAPositionUpdatesThePositionAndThePage() async {
        let content = (0..<20).map { _ in String(repeating: "字", count: 10) }.joined(separator: "\n")
        let provider = StubHighlightContentProvider(contents: [0: content])
        var book = Book()
        book.name = "测试书"
        book.bookUrl = "book://1"
        book.origin = "book://1"
        book.type = BookType.text
        let chapters = (0..<3).map { index -> BookChapter in
            var chapter = BookChapter()
            chapter.index = Int64(index)
            chapter.title = "第\(index + 1)章"
            chapter.url = "/c\(index)"
            chapter.bookUrl = "book://1"
            return chapter
        }
        let readBook = ReadBook(
            book: book,
            chapterList: chapters,
            contentProvider: provider,
            measurer: ApproximateTextMeasurer(),
            configProvider: { ReaderConfig() },
            layoutProvider: { HighlightLayout.make() }
        )
        await readBook.loadCurrentChapter()
        let pageCount = readBook.curTextChapter?.pageSize ?? 0
        XCTAssertGreaterThan(pageCount, 1)

        // Upstream `ReadBook.durChapterPos = chapterStart`.
        readBook.moveToPosition(120)
        XCTAssertEqual(readBook.durChapterPos, 120)
        let expectedPage = readBook.curTextChapter?.pageIndex(forCharacterIndex: 120) ?? -1
        XCTAssertEqual(readBook.pageIndex, expectedPage)
        XCTAssertGreaterThan(readBook.pageIndex, 0)

        // A negative position is clamped.
        readBook.moveToPosition(-5)
        XCTAssertEqual(readBook.durChapterPos, 0)
    }
}

/// The content provider of the tests.
private final class StubHighlightContentProvider: ChapterContentProviding {
    var contents: [Int: String]

    init(contents: [Int: String]) {
        self.contents = contents
    }

    func chapterContent(book: Book, chapter: BookChapter) async throws -> String? {
        contents[Int(chapter.index)]
    }
}

/// A small page so that the content is split over several pages.
private enum HighlightLayout {
    static func make() -> ReaderLayout {
        var config = ReaderConfig()
        config.paddingTop = 0
        config.paddingBottom = 0
        config.paddingLeft = 0
        config.paddingRight = 0
        config.lineSpacingExtra = 0
        config.paragraphSpacing = 0
        config.titleTopSpacing = 0
        config.titleBottomSpacing = 0
        config.textSize = 20
        return ReaderLayout(
            config: config,
            size: CGSizeLike(width: 300, height: 120),
            measurer: ApproximateTextMeasurer()
        )
    }
}
