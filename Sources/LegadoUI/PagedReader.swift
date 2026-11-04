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

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
                if line.isImage {
                    // An inline image — upstream `ImageColumn.draw`.
                    ReaderInlineImageView(line: line)
                } else {
                    Text(line.text)
                        .font(line.isTitle ? titleFont : bodyFont)
                        // The paragraph that is being read is drawn with the
                        // accent colour — upstream `TextColumn.draw`.
                        .foregroundColor(line.isReadAloud ? accentColor : textColor)
                        .multilineTextAlignment(textAlignment)
                        // The line is never wrapped again — the layout engine
                        // has already broken it.
                        .fixedSize(horizontal: true, vertical: false)
                        .offset(x: line.startX, y: line.lineTop)
                }
            }
        }
    }
}

/// One inline image of a page — upstream `ImageColumn.draw`.
///
/// The upstream draws the bitmap of the image at the position of its column
/// (`TextPage.drawPage` → `line.draw(view, this)`); the port draws the bytes
/// that the content provider resolved before the layout.
public struct ReaderInlineImageView: View {

    /// The image column of the line — `nil` when the line carries no image.
    let column: ImageColumn?
    /// The width of the image in points.
    let width: Double
    /// The height of the image in points.
    let height: Double

    public init(line: TextLine) {
        let imageColumn = line.columns.first { $0 is ImageColumn } as? ImageColumn
        self.column = imageColumn
        self.width = imageColumn.map { $0.end - $0.start } ?? 0
        self.height = line.height
    }

    public var body: some View {
        #if canImport(UIKit)
        if let column, let data = column.imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .frame(width: width, height: height)
                .offset(x: column.start, y: column.textLine?.lineTop ?? 0)
        } else if let column, let url = URL(string: column.src), url.scheme != nil {
            // The bytes were not resolved (the image was not cached) — the
            // remote image is loaded on demand.
            AsyncImage(url: url) { phase in
                if case let .success(image) = phase {
                    return AnyView(
                        image.resizable()
                            .frame(width: width, height: height)
                    )
                }
                return AnyView(EmptyView())
            }
            .frame(width: width, height: height)
            .offset(x: column.start, y: column.textLine?.lineTop ?? 0)
        }
        #elseif canImport(AppKit)
        if let column, let data = column.imageData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .frame(width: width, height: height)
                .offset(x: column.start, y: column.textLine?.lineTop ?? 0)
        } else if let column, let url = URL(string: column.src), url.scheme != nil {
            AsyncImage(url: url) { phase in
                if case let .success(image) = phase {
                    return AnyView(
                        image.resizable()
                            .frame(width: width, height: height)
                    )
                }
                return AnyView(EmptyView())
            }
            .frame(width: width, height: height)
            .offset(x: column.start, y: column.textLine?.lineTop ?? 0)
        }
        #else
        EmptyView()
        #endif
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
    /// Whether a tap on an image opens the preview — upstream
    /// `AppConfig.previewImageByClick`.
    var previewImageByClick: Bool = false
    /// Called with the source of the image that was tapped — upstream
    /// `ContentTextView.click` → `PhotoDialog`.
    var onTapImage: (String) -> Void = { _ in }
    /// Called with the source of the image that was long pressed — upstream
    /// `ContentTextView.longPress` → `ReadBookActivity.onImageLongPress`.
    var onLongPressImage: (String) -> Void = { _ in }

    public init(
        configuration: ReaderClickConfiguration,
        lines: [TextLine] = [],
        lineOffsets: [Int] = [],
        previewImageByClick: Bool = false,
        onAction: @escaping (ClickAction) -> Void,
        onLongPress: @escaping (Int) -> Void = { _ in },
        onTapImage: @escaping (String) -> Void = { _ in },
        onLongPressImage: @escaping (String) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.lines = lines
        self.lineOffsets = lineOffsets
        self.previewImageByClick = previewImageByClick
        self.onAction = onAction
        self.onLongPress = onLongPress
        self.onTapImage = onTapImage
        self.onLongPressImage = onLongPressImage
    }

    public var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 1, coordinateSpace: .local) { point in
                    // Upstream `ContentTextView.click` — a tap on an image
                    // opens the preview and is NOT handled by the click
                    // zones.
                    if previewImageByClick, let src = imageSrc(atY: Double(point.y)) {
                        onTapImage(src)
                        return
                    }
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
                    // Upstream `ContentTextView.longPress` — a long press on
                    // an image opens the image menu.
                    if let src = imageSrc(atY: y) {
                        onLongPressImage(src)
                        return
                    }
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

    /// The source of the image at the given vertical position — upstream
    /// `ContentTextView.touch` (the `ImageColumn`).
    private func imageSrc(atY y: Double) -> String? {
        guard let index = lineIndex(atY: y) else { return nil }
        let line = lines[index]
        guard line.isImage else { return nil }
        guard let column = line.columns.first(where: { $0 is ImageColumn }) as? ImageColumn else {
            return nil
        }
        return column.src
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
