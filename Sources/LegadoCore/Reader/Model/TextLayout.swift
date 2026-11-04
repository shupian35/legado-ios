//
//  TextLayout.swift
//  LegadoCore
//
//  The layout model of the reader: the columns, the lines, the pages and the
//  chapter. It is the platform independent part of the upstream renderer —
//  the Android version draws the columns onto a `Canvas`, the iOS version
//  draws them with SwiftUI / CoreText.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/page/entities/TextPage.kt
//  app/src/main/java/io/legado/app/ui/book/read/page/entities/TextLine.kt
//  app/src/main/java/io/legado/app/ui/book/read/page/entities/TextChapter.kt
//  app/src/main/java/io/legado/app/ui/book/read/page/entities/TextParagraph.kt
//  app/src/main/java/io/legado/app/ui/book/read/page/entities/column/*.kt
//

import Foundation

// MARK: - Columns

/// A piece of content inside a line — upstream `BaseColumn`.
public protocol ReaderColumn: AnyObject {
    var start: Double { get set }
    var end: Double { get set }
    var textLine: TextLine? { get set }
}

/// A single character — upstream `TextColumn`.
public final class TextColumn: ReaderColumn {
    public var start: Double
    public var end: Double
    public let charData: String
    public weak var textLine: TextLine?

    /// Whether the character is part of the current selection.
    public var selected = false {
        didSet { if selected != oldValue { textLine?.invalidate() } }
    }

    /// Whether the character is a search result.
    public var isSearchResult = false {
        didSet {
            guard isSearchResult != oldValue else { return }
            textLine?.invalidate()
            if isSearchResult {
                textLine?.searchResultColumnCount += 1
            } else {
                textLine?.searchResultColumnCount -= 1
            }
        }
    }

    public init(start: Double, end: Double, charData: String) {
        self.start = start
        self.end = end
        self.charData = charData
    }
}

/// An inline image — upstream `ImageColumn`.
public final class ImageColumn: ReaderColumn {
    public var start: Double
    public var end: Double
    /// The source of the image — upstream `ImageColumn.src`.
    public let src: String
    public let imageData: Data?
    public weak var textLine: TextLine?

    public init(start: Double, end: Double, src: String = "", imageData: Data? = nil) {
        self.start = start
        self.end = end
        self.src = src
        self.imageData = imageData
    }
}

// MARK: - Lines

/// One laid out line — upstream `TextLine`.
public final class TextLine {
    public var text: String = ""
    public var lineTop: Double = 0
    public var lineBase: Double = 0
    public var lineBottom: Double = 0
    public var indentWidth: Double = 0
    public var paragraphNum: Int = 0
    public var chapterPosition: Int = 0
    public var pagePosition: Int = 0
    public let isTitle: Bool
    public var isParagraphEnd: Bool = false
    public var isImage: Bool = false
    public var startX: Double = 0
    public var indentSize: Int = 0
    public var extraLetterSpacing: Double = 0
    public var extraLetterSpacingOffsetX: Double = 0
    public var wordSpacing: Double = 0
    public var exceed: Bool = false
    public var onlyTextColumn: Bool = true

    private var textColumns: [ReaderColumn] = []

    /// The number of search results inside the line.
    public var searchResultColumnCount = 0
    /// Whether the line is currently being read aloud.
    public var isReadAloud = false {
        didSet {
            if isReadAloud != oldValue { invalidate() }
            if isReadAloud { textPage?.hasReadAloudSpan = true }
        }
    }
    /// The page the line belongs to.
    public weak var textPage: TextPage?
    public var isLeftLine = true

    public init(isTitle: Bool = false) {
        self.isTitle = isTitle
    }

    public var columns: [ReaderColumn] { textColumns }
    public var charSize: Int { text.count }
    public var lineStart: Double { textColumns.first?.start ?? 0 }
    public var lineEnd: Double { textColumns.last?.end ?? 0 }
    public var chapterIndices: Range<Int> { chapterPosition..<(chapterPosition + charSize) }
    public var height: Double { lineBottom - lineTop }

    public func addColumn(_ column: ReaderColumn) {
        if !(column is TextColumn) { onlyTextColumn = false }
        column.textLine = self
        textColumns.append(column)
    }

    public func column(at index: Int) -> ReaderColumn {
        textColumns.indices.contains(index) ? textColumns[index] : (textColumns.last ?? TextColumn(start: 0, end: 0, charData: ""))
    }

    public func columnReverse(at index: Int, offset: Int = 0) -> ReaderColumn {
        let position = textColumns.count - 1 - offset - index
        return textColumns[position]
    }

    public var columnsCount: Int { textColumns.count }

    /// Positions the line — upstream `upTopBottom(durY, textHeight, fontMetrics)`.
    public func updateTopBottom(durY: Double, textHeight: Double, descent: Double, paddingTop: Double) {
        lineTop = paddingTop + durY
        lineBottom = lineTop + textHeight
        lineBase = lineBottom - descent
    }

    /// Whether the point touches the line — upstream `isTouch(x, y, relativeOffset)`.
    public func isTouch(x: Double, y: Double, relativeOffset: Double) -> Bool {
        y > lineTop + relativeOffset
            && y < lineBottom + relativeOffset
            && x >= lineStart
            && x <= lineEnd
    }

    public func isTouchY(y: Double, relativeOffset: Double) -> Bool {
        y > lineTop + relativeOffset && y < lineBottom + relativeOffset
    }

    /// Whether the line is (mostly) visible — upstream `isVisible(relativeOffset)`.
    public func isVisible(relativeOffset: Double, visibleTop: Double, visibleBottom: Double) -> Bool {
        let top = lineTop + relativeOffset
        let bottom = lineBottom + relativeOffset
        let width = bottom - top
        if top >= visibleTop && bottom <= visibleBottom { return true }
        if top <= visibleTop && bottom >= visibleBottom { return true }
        if top < visibleTop && bottom > visibleTop && bottom < visibleBottom {
            if isImage { return true }
            return (bottom - visibleTop) / width > 0.6
        }
        if top > visibleTop && top < visibleBottom && bottom > visibleBottom {
            if isImage { return true }
            return (visibleBottom - top) / width > 0.6
        }
        return false
    }

    public func invalidate() {
        textPage?.invalidate()
    }
}

// MARK: - Paragraphs

/// A paragraph — upstream `TextParagraph`.
public final class TextParagraph {
    public var num: Int
    public var textLines: [TextLine] = []

    public init(num: Int) {
        self.num = num
    }
}

// MARK: - Pages

/// One page of the chapter — upstream `TextPage`.
public final class TextPage {
    public var index: Int = 0
    public var text: String = ""
    public var title: String = ""
    public var chapterSize: Int = 0
    public var chapterIndex: Int = 0
    public var height: Double = 0
    public var leftLineSize: Int = 0
    public var renderHeight: Int = 0
    public var isMsgPage = false
    public var doublePage = false
    public var paddingTop: Double = 0
    public var isCompleted = false
    public var hasReadAloudSpan = false
    /// The chapter the page belongs to.
    public weak var textChapter: TextChapter?

    private var textLines: [TextLine] = []

    public init() {}

    public var lines: [TextLine] { textLines }
    public var lineSize: Int { textLines.count }
    public var charSize: Int { max(text.count, 1) }
    public var chapterPosition: Int { textLines.first?.chapterPosition ?? 0 }
    /// The search results of the page.
    public var searchResult: Set<ObjectIdentifier> = []

    public func addLine(_ line: TextLine) {
        line.textPage = self
        textLines.append(line)
    }

    public func line(at index: Int) -> TextLine? {
        textLines.indices.contains(index) ? textLines[index] : textLines.last
    }

    /// The offset of the first character of every line inside `text`.
    ///
    /// The page text is the concatenation of the line texts and a paragraph
    /// end adds a newline (`TextChapterLayout.append`), so the offsets are the
    /// positions of the lines in `text`.
    public var lineOffsets: [Int] {
        var result: [Int] = []
        var offset = 0
        for line in textLines {
            result.append(offset)
            offset += line.text.count
            if line.isParagraphEnd { offset += 1 }
        }
        return result
    }

    /// The offset of the first character of the line at `index` inside `text`.
    public func characterOffset(ofLineAt index: Int) -> Int {
        let offsets = lineOffsets
        guard offsets.indices.contains(index) else { return offsets.last ?? 0 }
        return offsets[index]
    }

    /// The index of the line at the given vertical position.
    ///
    /// The port's hit test for the long press — the upstream uses the exact
    /// glyph bounds (`ContentTextView`), the port uses the line boxes.
    public func lineIndex(atY y: Double) -> Int? {
        for (index, line) in textLines.enumerated() {
            if y >= line.lineTop && y <= line.lineBottom { return index }
        }
        // Fall back to the closest line.
        var best: Int?
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, line) in textLines.enumerated() {
            let distance = abs(line.lineTop - y)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }

    /// The paragraphs of the page — upstream `paragraphsInternal`.
    public var paragraphs: [TextParagraph] {
        var result: [TextParagraph] = []
        let lines = textLines.filter { $0.paragraphNum > 0 }
        guard let first = lines.first else { return [] }
        let offset = first.paragraphNum - 1
        for line in lines {
            if result.count < line.paragraphNum - offset {
                result.append(TextParagraph(num: line.paragraphNum))
            }
            result[line.paragraphNum - offset - 1].textLines.append(line)
        }
        return result
    }

    /// Removes the read-aloud highlight — upstream `removePageAloudSpan()`.
    @discardableResult
    public func removePageAloudSpan() -> TextPage {
        guard hasReadAloudSpan else { return self }
        hasReadAloudSpan = false
        for line in textLines { line.isReadAloud = false }
        return self
    }

    /// Highlights the read-aloud span — upstream `upPageAloudSpan(aloudSpanStart)`.
    public func updatePageAloudSpan(aloudSpanStart: Int) {
        removePageAloudSpan()
        var lineStart = 0
        for (index, textLine) in textLines.enumerated() {
            let lineLength = textLine.text.count + (textLine.isParagraphEnd ? 1 : 0)
            if aloudSpanStart >= lineStart && aloudSpanStart < lineStart + lineLength {
                var i = index - 1
                while i >= 0 {
                    if textLines[i].isParagraphEnd { break }
                    textLines[i].isReadAloud = true
                    i -= 1
                }
                for i in index..<textLines.count {
                    textLines[i].isReadAloud = true
                    if textLines[i].isParagraphEnd { break }
                }
                break
            }
            lineStart += lineLength
        }
    }

    /// The reading progress — upstream `readProgress`.
    public var readProgress: String {
        let pageSize = textChapter?.pageSize ?? 0
        if chapterSize == 0 || (pageSize == 0 && chapterIndex == 0) {
            return "0.0%"
        }
        if pageSize == 0 {
            return String(format: "%.1f%%", Double(chapterIndex + 1) / Double(chapterSize) * 100)
        }
        var percent = Double(chapterIndex) / Double(chapterSize)
            + 1.0 / Double(chapterSize) * Double(index + 1) / Double(pageSize)
        var text = String(format: "%.1f%%", percent * 100)
        if text == "100.0%" && (chapterIndex + 1 != chapterSize || index + 1 != pageSize) {
            text = "99.9%"
        }
        return text
    }

    /// The character offset of a line / column — upstream `getPosByLineColumn`.
    public func position(lineIndex: Int, columnIndex: Int) -> Int {
        var length = 0
        let maxIndex = min(lineIndex, lineSize - 1)
        guard maxIndex >= 0 else { return 0 }
        for index in 0..<maxIndex {
            length += textLines[index].charSize
            if textLines[index].isParagraphEnd { length += 1 }
        }
        let columns = textLines[maxIndex].columns
        for index in 0..<min(columnIndex, columns.count) {
            if let column = columns[index] as? TextColumn {
                length += column.charData.count
            }
        }
        return length
    }

    /// Whether the character offset is on this page — upstream `containPos`.
    public func contains(position chapterPos: Int) -> Bool {
        guard let first = lines.first else { return false }
        let startPos = first.chapterPosition
        return chapterPos >= startPos && chapterPos < startPos + charSize
    }

    public func hasImageOrEmpty() -> Bool {
        textLines.contains { $0.isImage } || textLines.isEmpty
    }

    /// Updates the render height — upstream `upRenderHeight()`.
    public func updateRenderHeight() {
        guard let last = lines.last else { return }
        renderHeight = Int(ceil(last.lineBottom))
        if leftLineSize > 0 && leftLineSize != lines.count {
            let left = lines[leftLineSize - 1]
            renderHeight = max(renderHeight, Int(ceil(left.lineBottom)))
        }
    }

    public func invalidate() {}
}

// MARK: - Chapters

/// The laid out chapter — upstream `TextChapter`.
public final class TextChapter {
    public let chapter: BookChapter
    public let position: Int
    public let title: String
    public let chaptersSize: Int
    public let sameTitleRemoved: Bool
    public let isVip: Bool
    public let isPay: Bool
    /// The replace rules that changed the content.
    public let effectiveReplaceRules: [ReplaceRule]?

    private var textPages: [TextPage] = []
    public var isCompleted = false

    public init(
        chapter: BookChapter,
        position: Int,
        title: String,
        chaptersSize: Int,
        sameTitleRemoved: Bool,
        isVip: Bool,
        isPay: Bool,
        effectiveReplaceRules: [ReplaceRule]? = nil
    ) {
        self.chapter = chapter
        self.position = position
        self.title = title
        self.chaptersSize = chaptersSize
        self.sameTitleRemoved = sameTitleRemoved
        self.isVip = isVip
        self.isPay = isPay
        self.effectiveReplaceRules = effectiveReplaceRules
    }

    public var pages: [TextPage] { textPages }
    public var pageSize: Int { textPages.count }
    public var lastIndex: Int { textPages.count - 1 }
    public var lastPage: TextPage? { textPages.last }

    public func addPage(_ page: TextPage) {
        page.textChapter = self
        textPages.append(page)
    }

    public func page(at index: Int) -> TextPage? {
        textPages.indices.contains(index) ? textPages[index] : nil
    }

    public func page(byReadPosition readPos: Int) -> TextPage? {
        page(at: pageIndex(forCharacterIndex: readPos))
    }

    /// The page that holds a character offset.
    public func pageIndex(forCharacterIndex charIndex: Int) -> Int {
        var low = 0
        var high = textPages.count - 1
        var result = 0
        while low <= high {
            let mid = (low + high) / 2
            let page = textPages[mid]
            let start = page.chapterPosition
            let end = start + page.charSize
            if charIndex < start {
                high = mid - 1
            } else if charIndex >= end {
                low = mid + 1
            } else {
                return mid
            }
            result = mid
        }
        return max(0, min(result, textPages.count - 1))
    }

    /// The read length of a page — upstream `getReadLength(pageIndex)`.
    public func readLength(pageIndex: Int) -> Int {
        guard pageIndex >= 0, !textPages.isEmpty else { return 0 }
        return textPages[min(pageIndex, lastIndex)].chapterPosition
    }

    public var lastReadLength: Int { readLength(pageIndex: lastIndex) }

    public func isLastIndex(_ index: Int) -> Bool {
        isCompleted && index >= textPages.count - 1
    }

    public func isLastIndexCurrent(_ index: Int) -> Bool {
        index >= textPages.count - 1
    }

    /// The paragraphs of the whole chapter — upstream `paragraphsInternal`.
    public var paragraphs: [TextParagraph] {
        var result: [TextParagraph] = []
        for page in textPages {
            for line in page.lines {
                guard line.paragraphNum > 0 else { continue }
                if result.count < line.paragraphNum {
                    result.append(TextParagraph(num: line.paragraphNum))
                }
                result[line.paragraphNum - 1].textLines.append(line)
            }
        }
        return result
    }
}

// MARK: - The empty instances

extension TextLine {
    /// The shared empty line — upstream `TextLine.emptyTextLine`.
    public static let empty = TextLine()
}

extension TextPage {
    /// The shared empty page — upstream `TextPage.emptyTextPage`.
    public static let empty = TextPage()
}
