//
//  ScrollMode.swift
//  LegadoCore
//
//  The continuous-scroll reading mode.
//
//  Upstream `ui/book/read/page/delegate/ScrollPageDelegate.kt` + the
//  `ContentTextView.scroll(mOffset)` of
//  `ui/book/read/page/ContentTextView.kt`:
//
//  * the content is drawn as a continuous flow: the current page at the page
//    offset, the next page right below it and the page after that below that
//    (`ContentTextView.drawPage`);
//  * the page offset is 0 at the top of the current page and negative while
//    the content is scrolled up;
//  * when the offset leaves the current page the reader moves to the previous
//    or the next page and the offset is corrected by the page height.
//
//  The port keeps the semantics exactly; only the drawing is done with SwiftUI
//  instead of an Android `Canvas`.
//

import Foundation

/// The continuous-scroll reading mode — upstream `ScrollPageDelegate.kt`.
public enum ScrollPageMode {

    /// The result of a scroll gesture — the new offset and the page the
    /// reader has to move to (0 = it stays on the page).
    public struct ScrollResult: Equatable, Sendable {
        /// The new page offset.
        public var offset: Double
        /// The page the reader crossed: -1 = the previous page, 1 = the next
        /// page, 0 = it stays on the current page.
        public var pageDelta: Int

        public init(offset: Double, pageDelta: Int = 0) {
            self.offset = offset
            self.pageDelta = pageDelta
        }
    }

    /// The upstream `ContentTextView.scroll(mOffset)`.
    ///
    /// - Parameters:
    ///   - offset: the current page offset (0 = the top of the current page).
    ///   - delta: the distance the finger moved (negative = up).
    ///   - pageHeight: the height of the current page.
    ///   - visibleHeight: the height of the visible area.
    ///   - hasPrevious: whether there is a page before the current one.
    ///   - hasNext: whether there is a page after the current one.
    public static func scroll(
        offset: Double,
        delta: Double,
        pageHeight: Double,
        visibleHeight: Double,
        hasPrevious: Bool,
        hasNext: Bool
    ) -> ScrollResult {
        let pageOffset = offset + delta
        // The top of the current page — the content cannot be dragged up.
        if !hasPrevious && pageOffset > 0 {
            return ScrollResult(offset: 0)
        }
        // The bottom of the last page — the content cannot be dragged down
        // past the visible area.
        if !hasNext && pageOffset < 0 && pageOffset + pageHeight < visibleHeight {
            return ScrollResult(offset: min(0, visibleHeight - pageHeight))
        }
        // The reader was dragged above the top of the current page — the
        // previous page is shown and the offset is corrected.
        if pageOffset > 0 {
            guard hasPrevious else { return ScrollResult(offset: 0) }
            return ScrollResult(offset: pageOffset - pageHeight, pageDelta: -1)
        }
        // The reader was dragged below the bottom of the current page — the
        // next page is shown and the offset is corrected.
        if pageOffset < -pageHeight {
            guard hasNext else { return ScrollResult(offset: -pageHeight) }
            return ScrollResult(offset: pageOffset + pageHeight, pageDelta: 1)
        }
        return ScrollResult(offset: pageOffset)
    }

    /// The upstream `ScrollPageDelegate.calcNextPageOffset()` — the distance
    /// a tap scrolls down: the last line of the page stays visible.
    ///
    /// The upstream scrolls by the whole visible height when the book is an
    /// image book or when the page holds an image (and the image style is not
    /// the text-only one).
    public static func nextOffset(
        lastLineTop: Double,
        paddingTop: Double,
        visibleHeight: Double,
        isImage: Bool,
        hasImageOrEmpty: Bool,
        isTextStyle: Bool
    ) -> Double {
        if isImage { return -visibleHeight }
        if !isTextStyle && hasImageOrEmpty { return -visibleHeight }
        return -(lastLineTop - paddingTop)
    }

    /// The upstream `ScrollPageDelegate.calcPrevPageOffset()` — the distance
    /// a tap scrolls up: the first line of the page stays visible.
    public static func previousOffset(
        firstLineBottom: Double,
        paddingTop: Double,
        visibleHeight: Double,
        isImage: Bool,
        hasImageOrEmpty: Bool,
        isTextStyle: Bool
    ) -> Double {
        if isImage { return visibleHeight }
        if !isTextStyle && hasImageOrEmpty { return visibleHeight }
        return visibleHeight - (firstLineBottom - paddingTop)
    }

    /// The pages that are drawn in the scroll mode — the upstream
    /// `ContentTextView.drawPage` stacks the current page, the next page and
    /// (when it is visible) the page after that.
    ///
    /// - Parameters:
    ///   - offset: the page offset.
    ///   - currentHeight: the height of the current page.
    ///   - nextHeight: the height of the next page (0 when there is none).
    ///   - hasNext: whether there is a next page.
    ///   - hasNextPlus: whether there is a page after the next one.
    ///   - nextPlusHeight: the height of the page after the next one.
    ///   - visibleHeight: the height of the visible area.
    public static func stackedPages(
        offset: Double,
        currentHeight: Double,
        nextHeight: Double,
        hasNext: Bool,
        hasNextPlus: Bool,
        nextPlusHeight: Double,
        visibleHeight: Double
    ) -> [ScrollPageOffset] {
        var pages = [ScrollPageOffset(index: 0, offset: offset)]
        guard hasNext else { return pages }
        var relative = offset + currentHeight
        pages.append(ScrollPageOffset(index: 1, offset: relative))
        guard hasNextPlus else { return pages }
        relative += nextHeight
        // The third page is only drawn when it is (partly) visible.
        guard relative < visibleHeight else { return pages }
        pages.append(ScrollPageOffset(index: 2, offset: relative))
        return pages
    }
}

/// One page of the continuous flow — the y offset of the page's top.
public struct ScrollPageOffset: Equatable, Sendable {
    /// The index of the page relative to the current one (0 = the current
    /// page, 1 = the next one, 2 = the one after that).
    public let index: Int
    /// The y offset of the page's top.
    public let offset: Double

    public init(index: Int, offset: Double) {
        self.index = index
        self.offset = offset
    }
}
