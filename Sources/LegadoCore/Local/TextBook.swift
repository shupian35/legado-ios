//
//  TextBook.swift
//  LegadoCore
//
//  TXT local-book parser.
//
//  Upstream: app/src/main/java/io/legado/app/model/localBook/TextFile.kt
//
//  The upstream parser streams the file in 512 KB blocks and cuts it into
//  chapters with a user supplied regular expression (the "TXT 目录规则").
//  When no rule matches it falls back to splitting every 10 KB at the next
//  newline.  Chapter offsets are byte offsets into the file so that the
//  content of a chapter can be read back later without re-parsing.
//
//  The port keeps the byte offsets, the block arithmetic and the three
//  "match" branches of the upstream `analyze(pattern)` implementation.
//

import Foundation

public final class TextBook {

    // MARK: - Constants (upstream TextFile.kt)

    private static let padPattern = "^[\\n\\s]+"
    private static let txtBufferSize = 8 * 1024 * 1024
    private static let bufferSize = 512_000
    private static let maxLengthWithNoToc = 10 * 1024
    private static let maxLengthWithToc = 102_400
    private static let blank: UInt8 = 0x0a

    public enum TextBookError: Error, Equatable {
        case emptyFile
        case fileNotFound(String)
    }

    /// The result of a table-of-contents parse.
    public struct ParsedToc {
        public var chapters: [BookChapter]
        public var wordCount: Int
        /// The leading "前言" text of the book (upstream `book.intro`).
        public var intro: String?
        /// The pattern that produced the table of contents (upstream `book.tocUrl`).
        public var tocPattern: String?
    }

    // MARK: - State

    private let fileURL: URL
    private var charset: String.Encoding
    private let splitLongChapter: Bool

    /// The byte offset of the first byte of the UTF-8 BOM, if any.
    private var bomLength: Int = 0

    // MARK: - Init

    /// - Parameters:
    ///   - fileURL: the local file of the book.
    ///   - charset: `nil` → the encoding is detected from the file content.
    ///   - splitLongChapter: upstream `book.getSplitLongChapter()`.
    public init(fileURL: URL, charset: String.Encoding? = nil, splitLongChapter: Bool = false) {
        self.fileURL = fileURL
        self.charset = charset ?? .utf8
        self.splitLongChapter = splitLongChapter
    }

    // MARK: - Public API

    /// Parse the table of contents.
    ///
    /// - Parameter tocRules: the enabled TXT TOC rules, highest `serialNumber` last
    ///   (upstream `getTocRules().reversed()` iterates them from the highest serial number).
    /// - Parameter ruleOverride: when set, this pattern is used instead of detecting one.
    public func chapterList(tocRules: [TxtTocRule], ruleOverride: String? = nil) throws -> ParsedToc {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw TextBookError.fileNotFound(fileURL.path)
        }
        defer { try? handle.close() }

        // The first block decides the encoding and the TOC rule.
        let head = try read(handle: handle, offset: 0, count: TextBook.bufferSize)
        guard !head.isEmpty else { throw TextBookError.emptyFile }

        if bomLength == 0 {
            bomLength = TextBook.hasUtf8Bom(head) ? 3 : 0
        }

        let detected = EncodingDetector.detect(head)
        charset = detected.stringEncoding

        var tocPattern = ruleOverride ?? ""
        if tocPattern.isEmpty {
            let blockContent = EncodingDetector.decode(head, encoding: detected)
            tocPattern = TextBook.detectTocRule(content: blockContent, rules: tocRules) ?? ""
        }

        var parsed: ParsedToc
        if tocPattern.isEmpty {
            let result = try analyzeWithoutRule(handle: handle)
            parsed = ParsedToc(chapters: result.chapters, wordCount: result.wordCount, intro: nil, tocPattern: nil)
        } else {
            var pattern: NSRegularExpression?
            if let regex = try? NSRegularExpression(pattern: tocPattern, options: [.anchorsMatchLines]) {
                pattern = regex
            }
            parsed = try analyze(handle: handle, pattern: pattern)
        }
        parsed.tocPattern = tocPattern.isEmpty ? nil : tocPattern
        return parsed
    }

    /// Read the content of a chapter.
    ///
    /// - Parameters:
    ///   - chapter: a chapter produced by `chapterList`.
    ///   - start: the byte offset of the chapter (upstream `chapter.start`).
    ///   - end: the byte offset of the end of the chapter (upstream `chapter.end`).
    public func content(chapter: BookChapter, start: Int64, end: Int64) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            throw TextBookError.fileNotFound(fileURL.path)
        }
        defer { try? handle.close() }

        let count = Int(max(0, end - start))
        let bytes = try read(handle: handle, offset: start, count: count)
        let text = EncodingDetector.decode(bytes, encoding: charset)
        // Upstream: `String(buffer, charset).substringAfter(chapter.title).replace(padRegex, "　　")`
        var body = text
        let title = chapter.title
        if !title.isEmpty, let range = text.range(of: title) {
            body = String(text[range.upperBound...])
        }
        return TextBook.replacePad(body)
    }

    // MARK: - TOC rule detection

    /// Upstream `getTocRule(content)`: pick the rule that matches the most titles.
    public static func detectTocRule(content: String, rules: [TxtTocRule]) -> String? {
        var maxNum = 1
        var tocPattern: String?
        for rule in rules.reversed() {
            guard let regex = try? NSRegularExpression(pattern: rule.rule, options: [.anchorsMatchLines]) else {
                continue
            }
            let range = NSRange(content.startIndex..<content.endIndex, in: content)
            var start = 0
            var num = 0
            var searchRange = range
            while let match = regex.firstMatch(in: content, options: [], range: searchRange) {
                let matchStart = match.range.location
                if start == 0 || matchStart - start > 1000 {
                    num += 1
                    start = match.range.location + match.range.length
                }
                if match.range.location + match.range.length >= range.length { break }
                searchRange = NSRange(location: match.range.location + match.range.length, length: range.length - (match.range.location + match.range.length))
            }
            if num >= maxNum {
                maxNum = num
                tocPattern = rule.rule
            }
        }
        return tocPattern
    }

    // MARK: - analyze(pattern) — upstream TextFile.kt:146

    private func analyze(handle: FileHandle, pattern: NSRegularExpression?) throws -> ParsedToc {
        var toc: [BookChapter] = []
        var bookWordCount = 0
        var intro: String?

        var buffer = [UInt8](repeating: 0, count: TextBook.bufferSize)
        var bufferStart = 3
        var curOffset: Int64 = 0
        var lastChapterWordCount = 0

        // Read the first three bytes to look for a UTF-8 BOM.
        let bom = try read(handle: handle, offset: 0, count: 3)
        for (index, byte) in bom.enumerated() {
            buffer[index] = byte
        }
        if TextBook.hasUtf8Bom(bom) {
            bufferStart = 0
            curOffset = 3
        }

        var fileOffset: Int64 = 3
        while true {
            let capacity = TextBook.bufferSize - bufferStart
            guard capacity > 0 else { break }
            let chunk = try read(handle: handle, offset: fileOffset, count: capacity)
            if chunk.isEmpty { break }
            fileOffset += Int64(chunk.count)

            for (index, byte) in chunk.enumerated() {
                buffer[bufferStart + index] = byte
            }
            var length = chunk.count
            var end = bufferStart + length
            if end == TextBook.bufferSize {
                var index = bufferStart + length - 1
                while index >= 0 {
                    if buffer[index] == TextBook.blank {
                        end = index
                        break
                    }
                    index -= 1
                }
            }
            let blockContent = EncodingDetector.decode(
                Data(buffer[0..<end]),
                encoding: charset
            )
            // Move the tail to the front for the next round.
            let tail = Array(buffer[end..<(bufferStart + length)])
            for (index, byte) in tail.enumerated() {
                buffer[index] = byte
            }
            bufferStart = bufferStart + length - end
            length = end

            let nsBlock = blockContent as NSString
            var seekPos = 0
            let searchRange = NSRange(location: 0, length: nsBlock.length)
            var matches: [NSTextCheckingResult] = []
            if let pattern {
                pattern.enumerateMatches(in: blockContent, options: [], range: searchRange) { result, _, _ in
                    if let result { matches.append(result) }
                }
            }
            for match in matches {
                let chapterStart = match.range.location
                let chapterContent = nsBlock.substring(with: NSRange(location: seekPos, length: chapterStart - seekPos))
                let chapterLength = Int64(chapterContent.data(using: charset)?.count ?? chapterContent.length)
                let lastStart = toc.last?.start ?? curOffset
                if splitLongChapter && curOffset + chapterLength - lastStart > Int64(TextBook.maxLengthWithToc) {
                    // The chapter is too long — split it.
                    toc[toc.count - 1].end = toc[toc.count - 1].start
                    toc[toc.count - 1].tag = nil
                    let lastTitle = toc.last?.title
                    let lastTitleLength = Int64(lastTitle?.data(using: charset)?.count ?? 0)
                    let (chapters, wordCount) = try analyzeWithoutRule(
                        handle: handle,
                        fileStart: lastStart + lastTitleLength,
                        fileEnd: curOffset + chapterLength
                    )
                    for (index, var chapter) in chapters.enumerated() {
                        if let lastTitle {
                            chapter.title = "\(lastTitle)(\(index + 1))"
                        }
                    }
                    toc.append(contentsOf: chapters)
                    bookWordCount += wordCount
                    var curChapter = BookChapter()
                    curChapter.title = nsBlock.substring(with: match.range)
                    curChapter.start = curOffset + chapterLength
                    curChapter.end = curChapter.start
                    toc.append(curChapter)
                    lastChapterWordCount = 0
                } else if seekPos == 0 && chapterStart != 0 {
                    if toc.isEmpty {
                        // The first block is the prologue.
                        if !chapterContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            var qyChapter = BookChapter()
                            qyChapter.title = "前言"
                            qyChapter.start = curOffset
                            qyChapter.end = curOffset + chapterLength
                            qyChapter.wordCount = TextFormat.wordCountFormat(chapterContent.count)
                            toc.append(qyChapter)
                            intro = chapterContent.count <= 500
                                ? chapterContent
                                : String(chapterContent.prefix(500))
                        }
                        var curChapter = BookChapter()
                        curChapter.title = nsBlock.substring(with: match.range)
                        curChapter.start = curOffset + chapterLength
                        curChapter.end = curChapter.start
                        toc.append(curChapter)
                    } else {
                        // The tail of the previous chapter.
                        // NOTE: BookChapter is a struct — mutate the array element in place.
                        let lastIndex = toc.count - 1
                        let afterTitle: String
                        if let range = chapterContent.range(of: toc[lastIndex].title) {
                            afterTitle = String(chapterContent[range.upperBound...])
                        } else {
                            afterTitle = chapterContent
                        }
                        toc[lastIndex].isVolume = afterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        toc[lastIndex].end = (toc[lastIndex].end ?? 0) + chapterLength
                        lastChapterWordCount += chapterContent.count
                        toc[lastIndex].wordCount = TextFormat.wordCountFormat(lastChapterWordCount)
                        var curChapter = BookChapter()
                        curChapter.title = nsBlock.substring(with: match.range)
                        curChapter.start = toc[lastIndex].end ?? 0
                        curChapter.end = curChapter.start
                        toc.append(curChapter)
                    }
                    bookWordCount += chapterContent.count
                    lastChapterWordCount = 0
                } else {
                    if !toc.isEmpty {
                        // NOTE: BookChapter is a struct — mutate the array element in place.
                        let lastIndex = toc.count - 1
                        let afterTitle: String
                        if let range = chapterContent.range(of: toc[lastIndex].title) {
                            afterTitle = String(chapterContent[range.upperBound...])
                        } else {
                            afterTitle = chapterContent
                        }
                        toc[lastIndex].isVolume = afterTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        toc[lastIndex].end = (toc[lastIndex].start ?? 0) + chapterLength
                        toc[lastIndex].wordCount = TextFormat.wordCountFormat(chapterContent.count)
                        var curChapter = BookChapter()
                        curChapter.title = nsBlock.substring(with: match.range)
                        curChapter.start = toc[lastIndex].end ?? 0
                        curChapter.end = curChapter.start
                        toc.append(curChapter)
                    } else {
                        var curChapter = BookChapter()
                        curChapter.title = nsBlock.substring(with: match.range)
                        curChapter.start = curOffset
                        curChapter.end = curOffset
                        curChapter.wordCount = TextFormat.wordCountFormat(chapterContent.count)
                        toc.append(curChapter)
                    }
                    bookWordCount += chapterContent.count
                    lastChapterWordCount = 0
                }
                seekPos += chapterContent.length
            }
            let wordCount = nsBlock.length - seekPos
            bookWordCount += wordCount
            lastChapterWordCount += wordCount
            curOffset += Int64(length)
            if !toc.isEmpty {
                toc[toc.count - 1].end = curOffset
                toc[toc.count - 1].wordCount = TextFormat.wordCountFormat(lastChapterWordCount)
            }
        }

        // A trailing chapter that is too long is split as well.
        if let last = toc.last, splitLongChapter, let lastEnd = last.end, let lastStart = last.start,
           lastEnd - lastStart > Int64(TextBook.maxLengthWithToc) {
            let end = lastEnd
            toc[toc.count - 1].end = lastStart
            toc[toc.count - 1].tag = nil
            let lastTitle = last.title
            let lastTitleLength = Int64(lastTitle.data(using: charset)?.count ?? 0)
            let (chapters, _) = try analyzeWithoutRule(
                handle: handle,
                fileStart: lastStart + lastTitleLength,
                fileEnd: end
            )
            for (index, var chapter) in chapters.enumerated() {
                chapter.title = "\(lastTitle)(\(index + 1))"
            }
            toc.append(contentsOf: chapters)
        }

        return ParsedToc(chapters: toc, wordCount: bookWordCount, intro: intro, tocPattern: nil)
    }

    // MARK: - analyze(fileStart:fileEnd:) — upstream TextFile.kt:335

    private func analyzeWithoutRule(
        handle: FileHandle,
        fileStart: Int64 = 0,
        fileEnd: Int64 = Int64.max
    ) throws -> (chapters: [BookChapter], wordCount: Int) {
        var toc: [BookChapter] = []
        var bookWordCount = 0
        var buffer = [UInt8](repeating: 0, count: TextBook.bufferSize)
        var blockPos = 0
        var curOffset: Int64 = 0
        var chapterPos = 0
        var length = 0
        var lastChapterWordCount = 0
        var bufferStart = 3

        if fileStart == 0 {
            let bom = try read(handle: handle, offset: 0, count: 3)
            for (index, byte) in bom.enumerated() {
                buffer[index] = byte
            }
            if TextBook.hasUtf8Bom(bom) {
                bufferStart = 0
                curOffset = 3
            }
        } else {
            curOffset = fileStart
            bufferStart = 0
        }

        var fileOffset: Int64 = fileStart
        while fileEnd - curOffset - Int64(bufferStart) > 0 {
            let capacity = Int(min(Int64(TextBook.bufferSize - bufferStart), fileEnd - curOffset - Int64(bufferStart)))
            guard capacity > 0 else { break }
            let chunk = try read(handle: handle, offset: fileOffset, count: capacity)
            if chunk.isEmpty { break }
            fileOffset += Int64(chunk.count)
            for (index, byte) in chunk.enumerated() {
                buffer[bufferStart + index] = byte
            }
            blockPos += 1
            var chapterOffset = 0
            length += bufferStart
            var strLength = length
            chapterPos = 0
            while strLength > 0 {
                chapterPos += 1
                if strLength > TextBook.maxLengthWithNoToc {
                    var end = length
                    var index = chapterOffset + TextBook.maxLengthWithNoToc
                    while index < length {
                        if buffer[index] == TextBook.blank {
                            end = index
                            break
                        }
                        index += 1
                    }
                    let content = EncodingDetector.decode(
                        Data(buffer[chapterOffset..<end]),
                        encoding: charset
                    )
                    bookWordCount += content.count
                    lastChapterWordCount = content.count
                    var chapter = BookChapter()
                    chapter.title = "第\(blockPos)章(\(chapterPos))"
                    chapter.start = toc.last?.end ?? curOffset
                    chapter.end = (chapter.start ?? 0) + Int64(end - chapterOffset)
                    chapter.wordCount = TextFormat.wordCountFormat(content.count)
                    toc.append(chapter)
                    strLength -= (end - chapterOffset)
                    chapterOffset = end
                } else {
                    let remaining = Array(buffer[(length - strLength)..<length])
                    for (index, byte) in remaining.enumerated() {
                        buffer[index] = byte
                    }
                    length -= strLength
                    bufferStart = strLength
                    strLength = 0
                }
            }
            curOffset += Int64(length)
        }

        let trailing = EncodingDetector.decode(Data(buffer[0..<bufferStart]), encoding: charset)
        bookWordCount += trailing.count
        if bufferStart > 100 || toc.isEmpty {
            var chapter = BookChapter()
            chapter.title = "第\(blockPos)章(\(chapterPos))"
            chapter.start = toc.last?.end ?? curOffset
            chapter.end = (chapter.start ?? 0) + Int64(bufferStart)
            chapter.wordCount = TextFormat.wordCountFormat(trailing.count)
            toc.append(chapter)
        } else {
            let wordCount = lastChapterWordCount + trailing.count
            if var last = toc.last {
                last.end = (last.end ?? 0) + Int64(bufferStart)
                last.wordCount = TextFormat.wordCountFormat(wordCount)
            }
        }
        return (toc, bookWordCount)
    }

    // MARK: - Helpers

    private func read(handle: FileHandle, offset: Int64, count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        try handle.seek(toOffset: UInt64(max(0, offset)))
        guard let data = try handle.read(upToCount: count) else { return Data() }
        return data
    }

    private static func hasUtf8Bom(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(3))
        return bytes.count == 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF
    }

    /// Replace the leading whitespace of every line with the ideographic indent.
    private static func replacePad(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: padPattern) else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "　　")
    }
}
