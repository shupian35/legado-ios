//
//  ReaderTests.swift
//  LegadoCoreTests
//
//  Tests for the reading engine: the position model, the layout model, the
//  pagination and the page cursor.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/page/entities/*.kt
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/*.kt
//

import XCTest
@testable import LegadoCore

// MARK: - Helpers

private func makeChapter(
    title: String = "第一章",
    url: String = "https://example.com/1",
    position: Int = 0,
    chaptersSize: Int = 1
) -> TextChapter {
    TextChapter(
        chapter: BookChapter(url: url, title: title),
        position: position,
        title: title,
        chaptersSize: chaptersSize,
        sameTitleRemoved: false,
        isVip: false,
        isPay: false
    )
}

private func makeLayout(width: Double = 200, height: Double = 300) -> ReaderLayout {
    var config = ReaderConfig()
    config.textSize = 20
    config.titleSize = 20
    config.paddingTop = 0
    config.paddingBottom = 0
    config.paddingLeft = 0
    config.paddingRight = 0
    config.titleTopSpacing = 0
    config.titleBottomSpacing = 0
    config.paragraphSpacing = 0
    return ReaderLayout(
        config: config,
        size: CGSizeLike(width: width, height: height),
        measurer: ApproximateTextMeasurer()
    )
}

/// A data source with three chapters of three pages each.
private final class StubDataSource: ReaderDataSource {
    var pageIndex = 0
    var chapters: [TextChapter] = []
    var currentIndex = 0

    init(chapters: [TextChapter]) {
        self.chapters = chapters
    }

    var currentChapter: TextChapter? {
        chapters.indices.contains(currentIndex) ? chapters[currentIndex] : nil
    }

    var nextChapter: TextChapter? {
        chapters.indices.contains(currentIndex + 1) ? chapters[currentIndex + 1] : nil
    }

    var prevChapter: TextChapter? {
        currentIndex > 0 ? chapters[currentIndex - 1] : nil
    }

    func hasNextChapter() -> Bool { nextChapter != nil }
    func hasPrevChapter() -> Bool { prevChapter != nil }

    @discardableResult
    func moveToNextChapter() -> Bool {
        guard hasNextChapter() else { return false }
        currentIndex += 1
        pageIndex = 0
        return true
    }

    @discardableResult
    func moveToPrevChapter() -> Bool {
        guard hasPrevChapter() else { return false }
        currentIndex -= 1
        pageIndex = max(0, (chapters[currentIndex].pageSize) - 1)
        return true
    }
}

// MARK: - The position model

final class TextPosTests: XCTestCase {

    func testCompareOrdersThePagesFirst() {
        let pos = TextPos(relativePagePos: 0, lineIndex: 5, columnIndex: 5)
        XCTAssertEqual(pos.compare(TextPos(relativePagePos: 1, lineIndex: 0, columnIndex: 0)), -3)
        XCTAssertEqual(pos.compare(TextPos(relativePagePos: -1, lineIndex: 0, columnIndex: 0)), 3)
    }

    func testCompareOrdersTheLinesThenTheColumns() {
        let pos = TextPos(relativePagePos: 0, lineIndex: 5, columnIndex: 5)
        XCTAssertEqual(pos.compare(TextPos(relativePagePos: 0, lineIndex: 6, columnIndex: 0)), -2)
        XCTAssertEqual(pos.compare(TextPos(relativePagePos: 0, lineIndex: 4, columnIndex: 0)), 2)
        XCTAssertEqual(pos.compare(TextPos(relativePagePos: 0, lineIndex: 5, columnIndex: 6)), -1)
        XCTAssertEqual(pos.compare(TextPos(relativePagePos: 0, lineIndex: 5, columnIndex: 4)), 1)
        XCTAssertEqual(pos.compare(TextPos(relativePagePos: 0, lineIndex: 5, columnIndex: 5)), 0)
    }

    func testCompareWithTheComponents() {
        let pos = TextPos(relativePagePos: 0, lineIndex: 5, columnIndex: 5)
        XCTAssertEqual(pos.compare(relativePos: 0, lineIndex: 6, charIndex: 0), -2)
        XCTAssertEqual(pos.compare(relativePos: 0, lineIndex: 5, charIndex: 5), 0)
    }

    func testResetAndSelection() {
        var pos = TextPos(relativePagePos: 2, lineIndex: 3, columnIndex: 4)
        XCTAssertTrue(pos.isSelected)
        pos.reset()
        XCTAssertFalse(pos.isSelected)
        XCTAssertEqual(pos.relativePagePos, 0)
        XCTAssertEqual(pos.lineIndex, -1)
    }
}

// MARK: - The pagination

final class TextChapterLayoutTests: XCTestCase {

    func testTheChapterIsSplitIntoPages() {
        let chapter = makeChapter()
        let layout = makeLayout(width: 100, height: 100)
        let measurer = ApproximateTextMeasurer()
        // 5 CJK characters per line (20 pt each), 24 pt per line.
        let content = String(repeating: "字", count: 100)
        let chapterLayout = TextChapterLayout(
            chapter: chapter,
            content: content,
            config: ReaderConfig(),
            layout: layout,
            measurer: measurer
        )
        let pages = chapterLayout.paginate()
        XCTAssertGreaterThan(pages.count, 1)
        XCTAssertEqual(chapter.pageSize, pages.count)
        XCTAssertTrue(chapter.isCompleted == false || chapter.pages.count == pages.count)
    }

    func testEveryCharacterEndsUpOnExactlyOnePage() {
        let chapter = makeChapter()
        let layout = makeLayout(width: 100, height: 100)
        let content = String(repeating: "字", count: 60)
        let chapterLayout = TextChapterLayout(
            chapter: chapter,
            content: content,
            config: ReaderConfig(),
            layout: layout,
            measurer: ApproximateTextMeasurer()
        )
        let pages = chapterLayout.paginate()
        // The title line is not part of the content.
        let total = pages
            .flatMap { $0.lines }
            .filter { !$0.isTitle }
            .reduce(0) { $0 + $1.charSize }
        XCTAssertEqual(total, content.count)
    }

    func testTheTitleIsTheFirstLineOfTheFirstPage() {
        let chapter = makeChapter(title: "书名")
        var config = ReaderConfig()
        config.titleMode = 0
        let chapterLayout = TextChapterLayout(
            chapter: chapter,
            content: "正文",
            config: config,
            layout: makeLayout(),
            measurer: ApproximateTextMeasurer()
        )
        let pages = chapterLayout.paginate()
        let first = try? XCTUnwrap(pages.first)
        XCTAssertEqual(first?.lines.first?.text, "书名")
        XCTAssertEqual(first?.lines.first?.isTitle, true)
    }

    func testTheTitleIsHiddenWhenTheTitleModeSaysSo() {
        let chapter = makeChapter(title: "书名")
        var config = ReaderConfig()
        config.titleMode = 2
        let chapterLayout = TextChapterLayout(
            chapter: chapter,
            content: "正文",
            config: config,
            layout: makeLayout(),
            measurer: ApproximateTextMeasurer()
        )
        let pages = chapterLayout.paginate()
        XCTAssertEqual(pages.first?.lines.first?.text, "正文")
    }

    func testTheParagraphsAreNumbered() {
        let chapter = makeChapter()
        let chapterLayout = TextChapterLayout(
            chapter: chapter,
            content: "第一段\n第二段",
            config: ReaderConfig(),
            layout: makeLayout(),
            measurer: ApproximateTextMeasurer()
        )
        let pages = chapterLayout.paginate()
        let numbers = pages.flatMap { $0.lines }.map(\.paragraphNum)
        // The title line has no paragraph number (upstream filters
        // `paragraphNum > 0`).
        XCTAssertEqual(numbers, [0, 1, 2])
    }

    func testTheLastLineOfAParagraphIsMarked() {
        let chapter = makeChapter()
        let chapterLayout = TextChapterLayout(
            chapter: chapter,
            content: "第一段\n第二段",
            config: ReaderConfig(),
            layout: makeLayout(),
            measurer: ApproximateTextMeasurer()
        )
        let pages = chapterLayout.paginate()
        let lines = pages.flatMap { $0.lines }
        // lines[0] is the title, lines[1] ends the first paragraph and
        // lines[2] ends the second one.
        XCTAssertEqual(lines[0].isParagraphEnd, false)
        XCTAssertEqual(lines[1].isParagraphEnd, true)
        XCTAssertEqual(lines[2].isParagraphEnd, true)
    }

    func testTheColumnsCarryTheCharacters() {
        let chapter = makeChapter()
        let chapterLayout = TextChapterLayout(
            chapter: chapter,
            content: "ABC",
            config: ReaderConfig(),
            layout: makeLayout(),
            measurer: ApproximateTextMeasurer()
        )
        let pages = chapterLayout.paginate()
        let columns = pages
            .flatMap { $0.lines }
            .filter { !$0.isTitle }
            .flatMap { $0.columns }
        XCTAssertEqual(columns.compactMap { ($0 as? TextColumn)?.charData }.joined(), "ABC")
        XCTAssertEqual(columns.first?.start, 0)
        XCTAssertGreaterThan(columns.last?.end ?? 0, 0)
    }
}

// MARK: - The page model

final class TextPageTests: XCTestCase {

    private func makePage(lines: [String]) -> TextPage {
        let page = TextPage()
        var position = 0
        for (index, text) in lines.enumerated() {
            let line = TextLine()
            line.text = text
            line.chapterPosition = position
            line.paragraphNum = index + 1
            line.lineTop = Double(index) * 10
            line.lineBottom = Double(index) * 10 + 10
            for character in text {
                line.addColumn(TextColumn(start: 0, end: 10, charData: String(character)))
            }
            page.addLine(line)
            page.text += text
            position += text.count
        }
        return page
    }

    func testThePositionOfALineAndColumn() {
        let page = makePage(lines: ["abc", "de"])
        XCTAssertEqual(page.position(lineIndex: 1, columnIndex: 1), 4)
        XCTAssertEqual(page.position(lineIndex: 0, columnIndex: 2), 2)
    }

    func testContainsPosition() {
        let page = makePage(lines: ["abc", "de"])
        XCTAssertTrue(page.contains(position: 0))
        XCTAssertTrue(page.contains(position: 4))
        XCTAssertFalse(page.contains(position: 5))
    }

    func testTheReadProgress() {
        let page = TextPage()
        page.chapterSize = 0
        XCTAssertEqual(page.readProgress, "0.0%")
    }

    func testTheReadAloudSpanIsMarked() {
        let page = makePage(lines: ["abc", "de"])
        page.updatePageAloudSpan(aloudSpanStart: 1)
        XCTAssertTrue(page.lines[0].isReadAloud)
        page.removePageAloudSpan()
        XCTAssertFalse(page.lines[0].isReadAloud)
    }
}

// MARK: - The page cursor

final class TextPageFactoryTests: XCTestCase {

    private func makeChapters() -> [TextChapter] {
        (0..<3).map { index in
            let chapter = makeChapter(title: "第\(index)章", position: index, chaptersSize: 3)
            for page in 0..<3 {
                let textPage = TextPage()
                textPage.index = page
                textPage.chapterIndex = index
                textPage.chapterSize = 3
                let line = TextLine()
                line.text = "page \(page)"
                line.chapterPosition = page * 10
                textPage.addLine(line)
                textPage.isCompleted = true
                chapter.addPage(textPage)
            }
            chapter.isCompleted = true
            return chapter
        }
    }

    func testTheCurrentPage() {
        let source = StubDataSource(chapters: makeChapters())
        let factory = TextPageFactory(dataSource: source)
        XCTAssertEqual(factory.currentPage.index, 0)
        source.pageIndex = 1
        XCTAssertEqual(factory.currentPage.index, 1)
    }

    func testHasPrevAndNext() {
        let source = StubDataSource(chapters: makeChapters())
        let factory = TextPageFactory(dataSource: source)
        XCTAssertFalse(factory.hasPrev)
        XCTAssertTrue(factory.hasNext)
        source.pageIndex = 2
        XCTAssertTrue(factory.hasPrev)
    }

    func testMovingToTheNextPage() {
        let source = StubDataSource(chapters: makeChapters())
        let factory = TextPageFactory(dataSource: source)
        XCTAssertTrue(factory.moveToNext())
        XCTAssertEqual(source.pageIndex, 1)
        XCTAssertTrue(factory.moveToNext())
        XCTAssertEqual(source.pageIndex, 2)
    }

    func testMovingPastTheLastPageMovesToTheNextChapter() {
        let source = StubDataSource(chapters: makeChapters())
        let factory = TextPageFactory(dataSource: source)
        source.pageIndex = 2
        XCTAssertTrue(factory.moveToNext())
        XCTAssertEqual(source.currentIndex, 1)
        XCTAssertEqual(source.pageIndex, 0)
    }

    func testMovingToThePreviousPage() {
        let source = StubDataSource(chapters: makeChapters())
        let factory = TextPageFactory(dataSource: source)
        source.pageIndex = 1
        XCTAssertTrue(factory.moveToPrev())
        XCTAssertEqual(source.pageIndex, 0)
    }

    func testTheNextAndPreviousPages() {
        let source = StubDataSource(chapters: makeChapters())
        let factory = TextPageFactory(dataSource: source)
        XCTAssertEqual(factory.nextPage.index, 1)
        source.pageIndex = 1
        XCTAssertEqual(factory.prevPage.index, 0)
        // The page two pages ahead does not exist in this chapter (three
        // pages, the second one is the current one), so it comes from the next
        // chapter — upstream `TextPageFactory.nextPlusPage`.
        XCTAssertEqual(factory.nextPlusPage.index, 0)
        source.pageIndex = 0
        XCTAssertEqual(factory.nextPlusPage.index, 2)
    }

    func testMoveToFirstAndLast() {
        let source = StubDataSource(chapters: makeChapters())
        let factory = TextPageFactory(dataSource: source)
        factory.moveToLast()
        XCTAssertEqual(source.pageIndex, 2)
        factory.moveToFirst()
        XCTAssertEqual(source.pageIndex, 0)
    }
}
