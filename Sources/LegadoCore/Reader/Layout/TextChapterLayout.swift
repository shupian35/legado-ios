//
//  TextChapterLayout.swift
//  LegadoCore
//
//  The pagination of a chapter.
//
//  The upstream version lays the chapter out with `StaticLayout` (or the
//  Chinese `ZhLayout`), splits the result into lines and then into pages.
//  This port keeps the same structure but measures the text through the
//  `TextMeasuring` protocol, so it runs on every platform.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/TextChapterLayout.kt
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/ChapterProvider.kt
//

import Foundation

/// Lays a chapter out into pages.
public final class TextChapterLayout {
    /// The chapter the layout belongs to.
    public let chapter: TextChapter
    /// The text of the chapter.
    public let content: String
    /// The reader configuration.
    public let config: ReaderConfig
    /// The geometry of the page.
    public let layout: ReaderLayout
    /// The text measurer.
    public let measurer: TextMeasuring

    public init(
        chapter: TextChapter,
        content: String,
        config: ReaderConfig,
        layout: ReaderLayout,
        measurer: TextMeasuring
    ) {
        self.chapter = chapter
        self.content = content
        self.config = config
        self.layout = layout
        self.measurer = measurer
    }

    /// The title of the chapter, when the title mode shows it.
    public var displayTitle: String {
        config.titleMode == 2 ? "" : chapter.title
    }

    /// Lays the chapter out — upstream `TextChapterLayout.getTextChapter()`.
    ///
    /// The returned pages are appended to the chapter.
    @discardableResult
    public func paginate() -> [TextPage] {
        var pages: [TextPage] = []
        var currentPage = TextPage()
        currentPage.textChapter = chapter
        currentPage.chapterSize = chapter.chaptersSize
        currentPage.chapterIndex = chapter.position
        currentPage.paddingTop = layout.paddingTop
        currentPage.doublePage = layout.doublePage
        var y = 0.0
        var chapterPosition = 0
        var pageIndex = 0

        // The title.
        if !displayTitle.isEmpty {
            let titleLines = measurer.lines(
                of: displayTitle,
                style: config.titleStyle,
                maxWidth: layout.visibleWidth,
                useZhLayout: config.useZhLayout
            )
            for (index, measured) in titleLines.enumerated() {
                let line = makeLine(
                    text: measured.text,
                    measured: measured,
                    style: config.titleStyle,
                    isTitle: true,
                    paragraphNum: 0,
                    chapterPosition: chapterPosition,
                    y: y,
                    x: layout.paddingLeft
                )
                chapterPosition += measured.text.count
                if index == titleLines.count - 1 {
                    y += layout.titleBottomSpacing
                }
                y += layout.titleTextHeight + layout.lineSpacingExtra
                if !append(line, to: &currentPage, pages: &pages, pageIndex: &pageIndex, y: &y) {
                    return finish(pages: pages, currentPage: currentPage, pageIndex: pageIndex)
                }
            }
        }

        // The body.
        let paragraphs = content.components(separatedBy: "\n")
        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            let measuredLines = measurer.lines(
                of: paragraph,
                style: config.contentStyle,
                maxWidth: layout.visibleWidth,
                useZhLayout: config.useZhLayout
            )
            for (lineIndex, measured) in measuredLines.enumerated() {
                let isLastLineOfParagraph = lineIndex == measuredLines.count - 1
                let line = makeLine(
                    text: measured.text,
                    measured: measured,
                    style: config.contentStyle,
                    isTitle: false,
                    paragraphNum: paragraphIndex + 1,
                    chapterPosition: chapterPosition,
                    y: y,
                    x: layout.paddingLeft
                )
                line.isParagraphEnd = isLastLineOfParagraph
                // Upstream counts the paragraph end as one more character
                // (ChapterProvider.kt:631).
                chapterPosition += measured.text.count + (isLastLineOfParagraph ? 1 : 0)
                y += layout.contentTextHeight + layout.lineSpacingExtra
                if isLastLineOfParagraph {
                    y += layout.paragraphSpacing
                }
                if !append(line, to: &currentPage, pages: &pages, pageIndex: &pageIndex, y: &y) {
                    return finish(pages: pages, currentPage: currentPage, pageIndex: pageIndex)
                }
            }
        }

        return finish(pages: pages, currentPage: currentPage, pageIndex: pageIndex)
    }

    /// Adds a line to the current page, starting a new page when it does not fit.
    ///
    /// Returns false when the layout has to stop (the caller then finalises).
    private func append(
        _ line: TextLine,
        to currentPage: inout TextPage,
        pages: inout [TextPage],
        pageIndex: inout Int,
        y: inout Double
    ) -> Bool {
        if !currentPage.lines.isEmpty, line.lineBottom > layout.visibleBottom {
            pages.append(currentPage)
            pageIndex += 1
            var nextPage = TextPage()
            nextPage.textChapter = chapter
            nextPage.chapterSize = chapter.chaptersSize
            nextPage.chapterIndex = chapter.position
            nextPage.index = pageIndex
            nextPage.paddingTop = layout.paddingTop
            nextPage.doublePage = layout.doublePage
            // The new page starts at the top again.
            let shift = line.lineTop - layout.paddingTop
            line.lineTop -= shift
            line.lineBase -= shift
            line.lineBottom -= shift
            currentPage = nextPage
            y -= shift
        }
        if currentPage.lines.isEmpty {
            currentPage.index = pageIndex
            currentPage.height = layout.visibleHeight
        }
        // Upstream keeps the text of the page so that `charSize` (and with it
        // `containPos`) works (TextChapterLayout.kt:320). The paragraph end
        // counts as one more character, exactly like the chapter position
        // accounting does.
        currentPage.text += line.text
        if line.isParagraphEnd {
            currentPage.text += "\n"
        }
        currentPage.addLine(line)
        return true
    }

    private func finish(pages: [TextPage], currentPage: TextPage, pageIndex: Int) -> [TextPage] {
        var result = pages
        if !currentPage.lines.isEmpty {
            var last = currentPage
            last.index = pageIndex
            last.height = layout.visibleHeight
            last.updateRenderHeight()
            last.isCompleted = true
            result.append(last)
        }
        for (index, page) in result.enumerated() {
            page.index = index
            page.textChapter = chapter
            page.chapterSize = chapter.chaptersSize
            page.chapterIndex = chapter.position
            page.isCompleted = true
            page.updateRenderHeight()
            chapter.addPage(page)
        }
        return result
    }

    /// Builds one line with its columns.
    private func makeLine(
        text: String,
        measured: MeasuredLine,
        style: ReaderTextStyle,
        isTitle: Bool,
        paragraphNum: Int,
        chapterPosition: Int,
        y: Double,
        x: Double
    ) -> TextLine {
        let line = TextLine(isTitle: isTitle)
        line.text = text
        line.paragraphNum = paragraphNum
        line.chapterPosition = chapterPosition
        line.startX = x
        let metrics = measurer.metrics(for: style)
        let textHeight = isTitle ? layout.titleTextHeight : layout.contentTextHeight
        let descent = isTitle ? layout.titleDescent : layout.contentDescent
        line.updateTopBottom(
            durY: y,
            textHeight: textHeight,
            descent: descent,
            paddingTop: layout.paddingTop
        )
        var cursor = x
        for character in text {
            let width = measurer.width(of: String(character), style: style)
            line.addColumn(TextColumn(start: cursor, end: cursor + width, charData: String(character)))
            cursor += width
        }
        return line
    }
}
