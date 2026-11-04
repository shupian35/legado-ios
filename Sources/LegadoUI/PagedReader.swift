//
//  PagedReader.swift
//  LegadoUI
//
//  The paged reader — the port of the upstream drawing model.
//
//  Upstream `ui/book/read/page/ReadView.kt` draws the laid-out lines of the
//  current page on a canvas and dispatches a tap to one of the nine zones
//  (`ReadView.onSingleTapUp` → `click(action)`). The port renders the same
//  laid-out lines with SwiftUI and reuses the ported
//  `TapZoneMapper` / `ReaderClickConfiguration`.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The content of one page — the laid-out lines of the current page.
///
/// The upstream draws the lines on a canvas, every line at its own `lineTop`
/// and starting at its own `startX` (`TextPage.drawPage` →
/// `canvas.withTranslation(0f, line.lineTop) { line.draw(view, this) }`).
/// The port does the same with SwiftUI: every line is placed at the position
/// the layout engine computed, so SwiftUI never re-wraps the text.
public struct PagedContentView: View {

    let lines: [TextLine]
    let titleFont: Font
    let bodyFont: Font
    let textAlignment: TextAlignment
    /// The colour of the text — upstream `ReadBookConfig.curTextColor`.
    let textColor: Color
    /// The colour of the paragraph that is being read — upstream
    /// `TextColumn.draw` uses the accent colour for `isReadAloud`.
    let accentColor: Color

    public init(
        lines: [TextLine],
        titleFont: Font,
        bodyFont: Font,
        textAlignment: TextAlignment = .leading,
        textColor: Color = .primary,
        accentColor: Color = .accentColor
    ) {
        self.lines = lines
        self.titleFont = titleFont
        self.bodyFont = bodyFont
        self.textAlignment = textAlignment
        self.textColor = textColor
        self.accentColor = accentColor
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(line.isTitle ? titleFont : bodyFont)
                    // The paragraph that is being read is drawn with the
                    // accent colour — upstream `TextColumn.draw`.
                    .foregroundColor(line.isReadAloud ? accentColor : textColor)
                    .multilineTextAlignment(textAlignment)
                    // The line is never wrapped again — the layout engine has
                    // already broken it.
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(x: line.startX, y: line.lineTop)
            }
        }
    }
}

/// The nine-zone tap area — upstream `ReadView.setRect9x` +
/// `onSingleTapUp`.
///
/// The area also catches the long press that starts the text selection
/// (upstream `ReadView.onLongPress` → `ContentTextView.selectText`).
public struct ReaderTapArea: View {

    let configuration: ReaderClickConfiguration
    let onAction: (ClickAction) -> Void
    /// The laid-out lines of the page — the long press finds the line that
    /// was touched.
    var lines: [TextLine] = []
    /// The offset of the first character of every line inside the page text.
    var lineOffsets: [Int] = []
    /// Called with the character offset of the long press.
    var onLongPress: (Int) -> Void = { _ in }

    public init(
        configuration: ReaderClickConfiguration,
        lines: [TextLine] = [],
        lineOffsets: [Int] = [],
        onAction: @escaping (ClickAction) -> Void,
        onLongPress: @escaping (Int) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.lines = lines
        self.lineOffsets = lineOffsets
        self.onAction = onAction
        self.onLongPress = onLongPress
    }

    public var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 1, coordinateSpace: .global) { point in
                    let zone = TapZoneMapper.zone(
                        atX: point.x,
                        y: point.y,
                        width: proxy.size.width,
                        height: proxy.size.height
                    )
                    guard let zone else { return }
                    let action = configuration.action(for: zone)
                    guard action != .noAction else { return }
                    onAction(action)
                }
                .onLongPressGesture(minimumDuration: 0.35) {
                    // The upstream selects the paragraph that was touched.
                    guard !lines.isEmpty else { return }
                    let y = touchY
                    guard let index = lineIndex(atY: y) else { return }
                    let offset = index < lineOffsets.count ? lineOffsets[index] : 0
                    onLongPress(offset)
                }
                // The long press does not report the position, so the finger
                // position is tracked with a drag gesture.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            touchY = Double(value.location.y)
                        }
                )
        }
    }

    /// The vertical position of the last long press — the shim does not
    /// report the position of the long press, so the port uses the last
    /// known touch point.
    @State private var touchY: Double = 0

    /// The index of the line at the given vertical position.
    private func lineIndex(atY y: Double) -> Int? {
        var best: Int?
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, line) in lines.enumerated() {
            if y >= line.lineTop && y <= line.lineBottom { return index }
            let distance = abs(line.lineTop - y)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }
}

/// The reader interaction configuration — the upstream preferences
/// (`clickActionTopLeft` … `clickActionBottomRight`) with the upstream
/// self-healing rule (`AppConfig.detectClickArea`).
public enum ReaderInteractionConfiguration {

    /// Builds the configuration from the settings.
    public static func configuration(from settings: AppSettings) -> ReaderClickConfiguration {
        ReaderClickConfiguration.from(settings: settings)
    }
}
