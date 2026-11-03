//
//  TextMeasuring.swift
//  LegadoCore
//
//  The text measurement abstraction of the reader.
//
//  Android measures the text with `android.text.StaticLayout` and `Paint`;
//  iOS measures it with CoreText. Both are platform specific, so the reader
//  core talks to this protocol instead. A simple approximation is provided
//  for the platforms (and the unit tests) that have neither.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/TextMeasure.kt
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/ChapterProvider.kt
//

import Foundation

/// The vertical metrics of a font.
public struct ReaderFontMetrics: Equatable {
    /// The distance from the baseline to the top of the line.
    public var ascent: Double
    /// The distance from the baseline to the bottom of the line.
    public var descent: Double
    /// The distance between two baselines.
    public var lineHeight: Double

    public init(ascent: Double, descent: Double, lineHeight: Double) {
        self.ascent = ascent
        self.descent = descent
        self.lineHeight = lineHeight
    }
}

/// The style of the measured text.
public struct ReaderTextStyle: Equatable, Hashable {
    /// The font size in points.
    public var fontSize: Double
    /// The extra letter spacing, in ems.
    ///
    /// The upstream stores it in `Paint.letterSpacing`, which Android
    /// interprets in ems — the real distance is `letterSpacing * fontSize`.
    public var letterSpacing: Double
    /// Whether the text is bold.
    public var isBold: Bool
    /// Whether the text is italic.
    public var isItalic: Bool

    public init(fontSize: Double = 20, letterSpacing: Double = 0, isBold: Bool = false, isItalic: Bool = false) {
        self.fontSize = fontSize
        self.letterSpacing = letterSpacing
        self.isBold = isBold
        self.isItalic = isItalic
    }
}

/// Measures text — the platform independent half of the reader.
public protocol TextMeasuring: AnyObject {
    /// The metrics of the font.
    func metrics(for style: ReaderTextStyle) -> ReaderFontMetrics
    /// The natural width of a string, without any wrapping.
    func width(of text: String, style: ReaderTextStyle) -> Double
    /// The clusters of a string with their widths.
    ///
    /// A cluster is a base character together with the zero width characters
    /// that follow it — the upstream `measureTextSplit`.
    func clusterWidths(of text: String, style: ReaderTextStyle) -> [TextCluster]
    /// Breaks a string into the lines that fit into `maxWidth`.
    ///
    /// The result keeps the original characters, so the caller can map every
    /// line back to the position in the source text.
    func lines(of text: String, style: ReaderTextStyle, maxWidth: Double, useZhLayout: Bool) -> [MeasuredLine]
}

extension TextMeasuring {

    /// The default line breaking — the Chinese rules of the upstream
    /// `ZhLayout` when they are wanted, the simple break otherwise.
    public func lines(
        of text: String,
        style: ReaderTextStyle,
        maxWidth: Double,
        useZhLayout: Bool
    ) -> [MeasuredLine] {
        guard !text.isEmpty else { return [] }
        let clusters = clusterWidths(of: text, style: style)
        let broken: [BrokenTextLine]
        if useZhLayout {
            broken = ZhLineBreaker.breakLines(
                clusters: clusters,
                maxWidth: maxWidth,
                cnCharWidth: width(of: "我", style: style)
            )
        } else {
            broken = ZhLineBreaker.breakLinesSimple(clusters: clusters, maxWidth: maxWidth)
        }
        let characters = Array(text)
        return broken.map { line in
            let start = min(line.startIndex, characters.count)
            let end = min(line.endIndex, characters.count)
            let slice = end > start ? String(characters[start..<end]) : ""
            return MeasuredLine(
                text: slice,
                width: line.width,
                startIndex: start,
                endIndex: end
            )
        }
    }

    /// Breaks a string into the lines that fit into `maxWidth`.
    public func lines(
        of text: String,
        style: ReaderTextStyle,
        maxWidth: Double
    ) -> [MeasuredLine] {
        lines(of: text, style: style, maxWidth: maxWidth, useZhLayout: false)
    }
}

/// One measured line.
public struct MeasuredLine: Equatable {
    /// The text of the line.
    public var text: String
    /// The width of the line.
    public var width: Double
    /// The index of the first character of the line in the source string.
    public var startIndex: Int
    /// The index after the last character of the line in the source string.
    public var endIndex: Int

    public init(text: String, width: Double, startIndex: Int, endIndex: Int) {
        self.text = text
        self.width = width
        self.startIndex = startIndex
        self.endIndex = endIndex
    }
}

/// A simple measurement that does not need a font engine.
///
/// Every CJK character is as wide as the font, every other character is half
/// as wide. It is only accurate enough for the layout maths and the tests.
public final class ApproximateTextMeasurer: TextMeasuring {
    public init() {}

    public func metrics(for style: ReaderTextStyle) -> ReaderFontMetrics {
        ReaderFontMetrics(
            ascent: style.fontSize * 0.8,
            descent: style.fontSize * 0.2,
            lineHeight: style.fontSize * 1.2
        )
    }

    public func width(of text: String, style: ReaderTextStyle) -> Double {
        var total = 0.0
        for character in text {
            total += characterWidth(character, style: style)
        }
        return total
    }

    public func clusterWidths(of text: String, style: ReaderTextStyle) -> [TextCluster] {
        let characters = Array(text)
        var widths: [Double] = []
        widths.reserveCapacity(characters.count)
        for character in characters {
            widths.append(characterWidth(character, style: style))
        }
        return ZhLineBreaker.clusters(text: text) { index in
            widths[index]
        }
    }

    private func characterWidth(_ character: Character, style: ReaderTextStyle) -> Double {
        // The zero width characters have no width of their own — upstream
        // `isZeroWidthChar`.
        if ZhLineBreaker.isZeroWidthCharacter(character) { return 0 }
        let base: Double
        if character.isCJKLike {
            base = style.fontSize
        } else if character == " " {
            base = style.fontSize * 0.3
        } else {
            base = style.fontSize * 0.5
        }
        // The upstream letter spacing is in ems — `paint.letterSpacing *
        // paint.textSize`.
        return base + style.letterSpacing * style.fontSize
    }
}

extension Character {
    /// Whether the character is a full width character.
    ///
    /// The CJK blocks, the Hangul syllables, the Kana, the full width forms
    /// and the CJK punctuation.
    var isCJKLike: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x1100...0x115F, // Hangul Jamo
             0x2E80...0x303E, // CJK radicals, Kangxi, CJK symbols
             0x3041...0x33FF, // Kana, Hangul compat, CJK compat
             0x3400...0x4DBF, // CJK extension A
             0x4E00...0x9FFF, // CJK unified ideographs
             0xA000...0xA4CF, // Yi
             0xAC00...0xD7A3, // Hangul syllables
             0xF900...0xFAFF, // CJK compatibility ideographs
             0xFE30...0xFE4F, // CJK compatibility forms
             0xFF00...0xFF60, // full width forms
             0xFFE0...0xFFE6:
            return true
        default:
            return false
        }
    }
}
