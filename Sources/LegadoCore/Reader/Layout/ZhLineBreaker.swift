//
//  ZhLineBreaker.swift
//  LegadoCore
//
//  The Chinese line breaking rules of the upstream reader.
//
//  The upstream lays the text out with `ZhLayout` when the preference
//  `useZhLayout` is on. `ZhLayout` is a `Layout` subclass that breaks the
//  lines the way a Chinese reader expects: a line may not start with a
//  closing punctuation and may not end with an opening punctuation.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/ZhLayout.kt
//

import Foundation

/// One measured cluster of text — a base character together with the zero
/// width characters that follow it (the upstream `measureTextSplit`).
public struct TextCluster: Equatable {
    /// The text of the cluster.
    public var text: String
    /// The width of the cluster.
    public var width: Double

    public init(text: String, width: Double) {
        self.text = text
        self.width = width
    }
}

/// One broken line — the range of the characters and the width.
public struct BrokenTextLine: Equatable {
    /// The index of the first character of the line.
    public var startIndex: Int
    /// The index after the last character of the line.
    public var endIndex: Int
    /// The width of the line.
    public var width: Double

    public init(startIndex: Int, endIndex: Int, width: Double) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.width = width
    }
}

/// The line breaking of the reader.
public enum ZhLineBreaker {

    /// The punctuation that must not start a line — upstream `postPanc`.
    public static let postPunctuation: Set<String> = [
        "，", "。", "：", "？", "！", "、", "”", "’", "）", "》", "}", "】",
        ")", ">", "]", ",", ".", "?", "!", ":", "」", "；", ";"
    ]

    /// The punctuation that must not end a line — upstream `prePanc`.
    public static let prePunctuation: Set<String> = [
        "“", "（", "《", "【", "‘", "(", "<", "[", "{", "「"
    ]

    /// The break modes of the upstream `ZhLayout.BreakMod`.
    private enum BreakMode: Int, Comparable {
        case normal = 0
        case breakOneChar = 1
        case breakMoreChar = 2
        case compressPost = 3
        case compressPre = 4
        case compressMixed = 5

        static func < (lhs: BreakMode, rhs: BreakMode) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Breaks the clusters into the lines that fit into `maxWidth`.
    ///
    /// The result is the port of the upstream `ZhLayout`: the lines are the
    /// ranges of the characters, `indentSize` is the number of the indent
    /// characters at the start of the first line (they must not be split).
    public static func breakLines(
        clusters: [TextCluster],
        maxWidth: Double,
        cnCharWidth: Double,
        indentSize: Int = 0
    ) -> [BrokenTextLine] {
        guard !clusters.isEmpty else { return [] }
        var starts: [Int] = [0]
        var widths: [Double] = [0]
        var line = 0
        var lineWidth: Double = 0
        var previousWidth: Double = 0
        var length = 0
        var breakCharCount = 0

        for (index, cluster) in clusters.enumerated() {
            let width = cluster.width
            var offset: Double = 0
            var didBreak = false
            lineWidth += width

            if lineWidth > maxWidth {
                var mode: BreakMode
                if index >= 1 && isPrePunctuation(clusters[index - 1].text) {
                    // The line would end with an opening punctuation.
                    mode = (index >= 2 && isPrePunctuation(clusters[index - 2].text))
                        ? .compressPre
                        : .breakOneChar
                } else if isPostPunctuation(cluster.text) {
                    // The line would start with a closing punctuation.
                    if index >= 1 && isPostPunctuation(clusters[index - 1].text) {
                        mode = .compressPost
                    } else if index >= 2 && isPrePunctuation(clusters[index - 2].text) {
                        mode = .compressMixed
                    } else {
                        mode = .breakOneChar
                    }
                } else {
                    mode = .normal
                }

                // The compression is only possible when the characters are
                // wide enough to be squeezed.
                var recheck = false
                var breakIndex = 0
                if mode == .compressPost,
                   isIncompressible(clusters[index].width, cnCharWidth)
                    || isIncompressible(clusters[index - 1].width, cnCharWidth) {
                    recheck = true
                }
                if mode == .compressPre,
                   isIncompressible(clusters[index - 1].width, cnCharWidth)
                    || isIncompressible(clusters[index - 2].width, cnCharWidth) {
                    recheck = true
                }
                if mode == .compressMixed,
                   isIncompressible(clusters[index].width, cnCharWidth)
                    || isIncompressible(clusters[index - 2].width, cnCharWidth) {
                    recheck = true
                }
                if mode > .breakMoreChar,
                   index < clusters.count - 1,
                   isPostPunctuation(clusters[index + 1].text) {
                    recheck = true
                }

                // The special characters make the compression unreliable, so
                // the line is broken at the last position that is allowed.
                var breakLength = 0
                if recheck && index > 2 {
                    let startPosition = line == 0 ? indentSize : starts[line]
                    mode = .normal
                    if index >= 1 + startPosition {
                        var i = index
                        while i >= 1 + startPosition {
                            if i == index {
                                breakIndex = 0
                                previousWidth = 0
                            } else {
                                breakIndex += 1
                                breakLength += clusters[i].text.count
                                previousWidth += clusters[i].width
                            }
                            if !isPostPunctuation(clusters[i].text)
                                && !isPrePunctuation(clusters[i - 1].text) {
                                mode = .breakMoreChar
                                break
                            }
                            i -= 1
                        }
                    }
                }

                switch mode {
                case .normal:
                    offset = width
                    setStart(&starts, line + 1, length)
                    breakCharCount = 1
                case .breakOneChar:
                    offset = width + previousWidth
                    setStart(&starts, line + 1, length - clusters[index - 1].text.count)
                    breakCharCount = 2
                case .breakMoreChar:
                    offset = width + previousWidth
                    setStart(&starts, line + 1, length - breakLength)
                    breakCharCount = breakIndex + 1
                case .compressPost, .compressPre, .compressMixed:
                    offset = 0
                    setStart(&starts, line + 1, length + cluster.text.count)
                    breakCharCount = 0
                }
                didBreak = true
            }

            if didBreak {
                setWidth(&widths, line, lineWidth - offset)
                lineWidth = offset
                line += 1
            }

            if index == clusters.count - 1 {
                if !didBreak {
                    offset = 0
                    setStart(&starts, line + 1, length + cluster.text.count)
                    setWidth(&widths, line, lineWidth - offset)
                    lineWidth = offset
                    line += 1
                } else if breakCharCount > 0 {
                    // The line was full and some characters have to move to
                    // the next line — the upstream adds one more line.
                    setStart(&starts, line + 1, starts[line] + breakCharCount)
                    setWidth(&widths, line, lineWidth)
                    line += 1
                }
            }
            length += cluster.text.count
            previousWidth = width
        }

        let count = max(line, 1)
        var result: [BrokenTextLine] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let start = index < starts.count ? starts[index] : 0
            let end = index + 1 < starts.count ? starts[index + 1] : length
            let width = index < widths.count ? widths[index] : 0
            result.append(BrokenTextLine(startIndex: start, endIndex: end, width: width))
        }
        return result
    }

    /// Breaks the clusters into the lines without the Chinese rules — the
    /// simple break at every character that the reader uses when the
    /// preference `useZhLayout` is off.
    public static func breakLinesSimple(
        clusters: [TextCluster],
        maxWidth: Double
    ) -> [BrokenTextLine] {
        guard !clusters.isEmpty else { return [] }
        var result: [BrokenTextLine] = []
        var start = 0
        var firstCluster = 0
        var width: Double = 0
        var offset = 0
        for (index, cluster) in clusters.enumerated() {
            if width + cluster.width > maxWidth, index > firstCluster {
                // The line is full — the cluster starts the next line.
                result.append(BrokenTextLine(startIndex: start, endIndex: offset, width: width))
                start = offset
                firstCluster = index
                width = 0
            }
            width += cluster.width
            offset += cluster.text.count
        }
        result.append(BrokenTextLine(
            startIndex: start,
            endIndex: offset,
            width: width
        ))
        return result
    }

    /// Splits the text into the clusters — the upstream `measureTextSplit`.
    ///
    /// A cluster is a base character together with the zero width characters
    /// that follow it.
    public static func clusters(text: String, widths: (Int) -> Double) -> [TextCluster] {
        var result: [TextCluster] = []
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let base = index
            index += 1
            while index < characters.count,
                  widths(index) == 0,
                  !isZeroWidthCharacter(characters[index]) {
                index += 1
            }
            result.append(TextCluster(
                text: String(characters[base..<index]),
                width: widths(base)
            ))
        }
        return result
    }

    /// Whether the character has no width of its own — upstream
    /// `isZeroWidthChar`.
    public static func isZeroWidthCharacter(_ character: Character) -> Bool {
        switch character.unicodeScalars.first?.value {
        case 0x200B, 0x200C, 0x200D, 0x2068:
            return true
        default:
            return false
        }
    }

    private static func isPostPunctuation(_ text: String) -> Bool {
        postPunctuation.contains(text)
    }

    private static func isPrePunctuation(_ text: String) -> Bool {
        prePunctuation.contains(text)
    }

    /// Whether the character is too narrow to be squeezed — upstream
    /// `inCompressible`.
    private static func isIncompressible(_ width: Double, _ cnCharWidth: Double) -> Bool {
        width < cnCharWidth
    }

    private static func setStart(_ starts: inout [Int], _ index: Int, _ value: Int) {
        if index < starts.count {
            starts[index] = value
        } else {
            starts.append(value)
        }
    }

    private static func setWidth(_ widths: inout [Double], _ index: Int, _ value: Double) {
        if index < widths.count {
            widths[index] = value
        } else {
            widths.append(value)
        }
    }
}
