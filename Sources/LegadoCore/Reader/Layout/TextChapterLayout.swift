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
    /// The inline images of the chapter, keyed by the raw `src` of the tag.
    ///
    /// Upstream `ChapterProvider.setTypeImage` asks `ImageProvider` for the
    /// size of every image; the port resolves the images before the layout.
    public var images: [String: ReaderImage]
    /// How the images are displayed — upstream `Book.getImageStyle()`.
    public var imageStyle: BookImageStyle

    public init(
        chapter: TextChapter,
        content: String,
        config: ReaderConfig,
        layout: ReaderLayout,
        measurer: TextMeasuring,
        images: [String: ReaderImage] = [:],
        imageStyle: BookImageStyle = .standard
    ) {
        self.chapter = chapter
        self.content = content
        self.config = config
        self.layout = layout
        self.measurer = measurer
        self.images = images
        self.imageStyle = imageStyle
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
        //
        // Upstream `ChapterProvider.setType` splits the content on
        // `AppPattern.imgPattern`: the text between the images is laid out as
        // text and every image becomes a line of its own
        // (`ChapterProvider.setTypeImage`, :345-463). The `TEXT` image style
        // replaces the image with ▣ and lays it out as text (:200-228).
        let segments: [ChapterImageSplitter.Segment]
        if imageStyle == .text {
            segments = [.text(ChapterImageSplitter.textEmbedded(content))]
        } else {
            segments = ChapterImageSplitter.split(content)
        }
        var paragraphIndex = 0
        for segment in segments {
            switch segment {
            case .text(let text):
                for paragraph in text.components(separatedBy: "\n") {
                    paragraphIndex += 1
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
                            paragraphNum: paragraphIndex,
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
            case .image(let src):
                guard let line = makeImageLine(
                    src: src,
                    chapterPosition: chapterPosition,
                    y: y,
                    x: layout.paddingLeft
                ) else { continue }
                // The upstream appends a space to the page text for an image so
                // that the index arithmetic stays right (ChapterProvider.kt:459).
                chapterPosition += 1
                y += line.height
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
        if line.isImage {
            // The upstream appends a space for an image so that the page text
            // and the chapter position stay in sync
            // (ChapterProvider.kt:459).
            currentPage.text += " "
        }
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

    /// Builds the line of an inline image — upstream `ChapterProvider.setTypeImage`
    /// (`ChapterProvider.kt:345-463`).
    ///
    /// The size of the image comes from the resolved image; the style decides
    /// how it is scaled:
    /// - `FULL` — the image fills the width of the page,
    /// - `SINGLE` — the image fills the width and is clamped to the page,
    /// - the default — the image keeps its size but never exceeds the page.
    private func makeImageLine(
        src: String,
        chapterPosition: Int,
        y: Double,
        x: Double
    ) -> TextLine? {
        guard let image = images[src] else { return nil }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        var width = size.width
        var height = size.height
        switch imageStyle {
        case .full:
            width = layout.visibleWidth
            height = size.height * layout.visibleWidth / size.width
        case .single:
            width = layout.visibleWidth
            height = size.height * layout.visibleWidth / size.width
            if height > layout.visibleHeight {
                width = width * layout.visibleHeight / height
                height = layout.visibleHeight
            }
        case .text:
            return nil
        case .standard:
            if width > layout.visibleWidth {
                height = height * layout.visibleWidth / width
                width = layout.visibleWidth
            }
            if height > layout.visibleHeight {
                width = width * layout.visibleHeight / height
                height = layout.visibleHeight
            }
        }
        let line = TextLine(isTitle: false)
        line.text = ""
        line.isImage = true
        line.chapterPosition = chapterPosition
        line.startX = x
        line.lineTop = layout.paddingTop + y
        line.lineBottom = line.lineTop + height
        line.lineBase = line.lineBottom
        // The image is centred in the page.
        let inset = width < layout.visibleWidth ? (layout.visibleWidth - width) / 2 : 0
        line.addColumn(ImageColumn(
            start: x + inset,
            end: x + inset + width,
            src: image.src,
            imageData: image.data
        ))
        return line
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
