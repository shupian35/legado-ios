//
//  ReaderScrollView.swift
//  LegadoUI
//
//  The continuous-scroll reading mode.
//
//  Upstream `ui/book/read/page/ContentTextView.kt` draws the current page,
//  the next page and (when it is visible) the page after that as one
//  continuous flow (`ContentTextView.drawPage`); the page offset moves the
//  flow up and down. The port draws the same stack with SwiftUI.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// One page of the continuous flow — upstream `ContentTextView.drawPage`.
public struct ReaderScrollPage: Identifiable {

    /// The index of the page relative to the current one (0 = the current
    /// page, 1 = the next one, 2 = the one after that).
    public let index: Int
    /// The laid-out lines of the page.
    public let lines: [TextLine]
    /// The y offset of the page's top.
    public let offset: Double

    public var id: Int { index }

    public init(index: Int, lines: [TextLine], offset: Double) {
        self.index = index
        self.lines = lines
        self.offset = offset
    }
}

/// The continuous-scroll content — upstream `ContentTextView.drawPage`.
///
/// The pages are drawn at their own offsets, so the text of the next page
/// follows the text of the current one without a gap.
public struct ReaderScrollContentView: View {

    /// The pages of the flow.
    public var pages: [ReaderScrollPage]
    /// The font of the title lines.
    public var titleFont: Font
    /// The font of the body lines.
    public var bodyFont: Font
    /// The alignment of the text.
    public var textAlignment: TextAlignment
    /// The colour of the text.
    public var textColor: Color

    public init(
        pages: [ReaderScrollPage],
        titleFont: Font = .system(size: 17),
        bodyFont: Font = .system(size: 17),
        textAlignment: TextAlignment = .leading,
        textColor: Color = .primary
    ) {
        self.pages = pages
        self.titleFont = titleFont
        self.bodyFont = bodyFont
        self.textAlignment = textAlignment
        self.textColor = textColor
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(pages) { page in
                PagedContentView(
                    lines: page.lines,
                    titleFont: titleFont,
                    bodyFont: bodyFont,
                    textAlignment: textAlignment,
                    textColor: textColor
                )
                .offset(y: page.offset)
            }
        }
    }
}
