//
//  CoreTextMeasurer.swift
//  LegadoCore
//
//  The measurer that uses the real font metrics of the platform.
//
//  Android measures the text with `android.text.StaticLayout` and a `Paint`;
//  iOS measures it with CoreText (`NSAttributedString` + `UIFont`). The line
//  breaking still comes from `ZhLineBreaker` — only the widths and the
//  vertical metrics are the real ones.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/TextMeasure.kt
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/ChapterProvider.kt
//

#if canImport(UIKit) && !os(watchOS)

import UIKit
import Foundation

/// The measurer of the reader that measures with the real font.
public final class CoreTextMeasurer: TextMeasuring {

    /// The provider of the font of a style.
    ///
    /// The provider is called for every style, so a font the user changes at
    /// runtime is picked up by the next measurement.
    public typealias FontProvider = (ReaderTextStyle) -> UIFont

    private let fontProvider: FontProvider

    /// The fonts of the styles that were already asked for.
    private var fonts: [ReaderTextStyle: UIFont] = [:]

    /// The measured widths of the single characters.
    private var widths: [String: Double] = [:]

    /// The lock that guards the caches.
    private let lock = NSLock()

    public init(fontProvider: @escaping FontProvider) {
        self.fontProvider = fontProvider
    }

    /// The font of a style.
    public func font(for style: ReaderTextStyle) -> UIFont {
        lock.lock()
        defer { lock.unlock() }
        if let cached = fonts[style] { return cached }
        let font = fontProvider(style)
        fonts[style] = font
        return font
    }

    public func metrics(for style: ReaderTextStyle) -> ReaderFontMetrics {
        let font = self.font(for: style)
        return ReaderFontMetrics(
            ascent: Double(font.ascender),
            descent: Double(font.descender),
            lineHeight: Double(font.lineHeight)
        )
    }

    public func width(of text: String, style: ReaderTextStyle) -> Double {
        guard !text.isEmpty else { return 0 }
        if text.count == 1, let cached = cachedWidth(text) { return cached }
        return measure(text, style: style)
    }

    public func clusterWidths(of text: String, style: ReaderTextStyle) -> [TextCluster] {
        let characters = Array(text)
        var measured: [Double] = []
        measured.reserveCapacity(characters.count)
        for character in characters {
            measured.append(width(of: String(character), style: style))
        }
        return ZhLineBreaker.clusters(text: text) { index in
            index < measured.count ? measured[index] : 0
        }
    }

    /// The width of a string in the given style.
    private func measure(_ text: String, style: ReaderTextStyle) -> Double {
        let attributed = NSAttributedString(string: text, attributes: attributes(for: style))
        let width = Double(attributed.size().width)
        if text.count == 1 { storeWidth(text, width) }
        return width
    }

    private func attributes(for style: ReaderTextStyle) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(for: style)
        ]
        // The upstream letter spacing is in ems — `paint.letterSpacing *
        // paint.textSize` — while the kern attribute of CoreText is in points.
        let spacing = style.letterSpacing * style.fontSize
        if spacing != 0 {
            // `NSAttributedString.Key.kern` exists on Apple platforms only —
            // the raw value is the same, so the key is spelled out here.
            attributes[NSAttributedString.Key("kern")] = spacing
        }
        return attributes
    }

    private func cachedWidth(_ text: String) -> Double? {
        lock.lock()
        defer { lock.unlock() }
        return widths[text]
    }

    private func storeWidth(_ text: String, _ width: Double) {
        lock.lock()
        defer { lock.unlock() }
        widths[text] = width
    }
}

#endif
