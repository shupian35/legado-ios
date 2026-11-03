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

    public init(
        lines: [TextLine],
        titleFont: Font,
        bodyFont: Font,
        textAlignment: TextAlignment = .leading
    ) {
        self.lines = lines
        self.titleFont = titleFont
        self.bodyFont = bodyFont
        self.textAlignment = textAlignment
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text)
                    .font(line.isTitle ? titleFont : bodyFont)
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
public struct ReaderTapArea: View {

    let configuration: ReaderClickConfiguration
    let onAction: (ClickAction) -> Void

    public init(configuration: ReaderClickConfiguration, onAction: @escaping (ClickAction) -> Void) {
        self.configuration = configuration
        self.onAction = onAction
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
        }
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
