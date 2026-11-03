import XCTest
@testable import LegadoCore

/// The continuous-scroll reading mode — the port of the upstream
/// `ui/book/read/page/delegate/ScrollPageDelegate.kt` and the
/// `ContentTextView.scroll(mOffset)` of
/// `ui/book/read/page/ContentTextView.kt`.
final class ScrollModeTests: XCTestCase {

    // MARK: - The scroll itself

    /// The offset accumulates while the content stays inside the page.
    func testTheOffsetAccumulates() {
        let result = ScrollPageMode.scroll(
            offset: 0,
            delta: -10,
            pageHeight: 100,
            visibleHeight: 100,
            hasPrevious: true,
            hasNext: true
        )
        XCTAssertEqual(result.offset, -10)
        XCTAssertEqual(result.pageDelta, 0)
    }

    /// The content cannot be dragged above the top of the first page.
    func testTheTopOfTheFirstPageIsClamped() {
        let result = ScrollPageMode.scroll(
            offset: 0,
            delta: 30,
            pageHeight: 100,
            visibleHeight: 100,
            hasPrevious: false,
            hasNext: true
        )
        XCTAssertEqual(result.offset, 0)
        XCTAssertEqual(result.pageDelta, 0)
    }

    /// The content cannot be dragged below the bottom of the last page.
    func testTheBottomOfTheLastPageIsClamped() {
        // The page is taller than the visible area — the content stops at
        // `visibleHeight - pageHeight`.
        let result = ScrollPageMode.scroll(
            offset: 0,
            delta: -300,
            pageHeight: 200,
            visibleHeight: 100,
            hasPrevious: true,
            hasNext: false
        )
        XCTAssertEqual(result.offset, -100)
        XCTAssertEqual(result.pageDelta, 0)
    }

    /// Dragging past the top of the page shows the previous page — upstream
    /// `pageFactory.moveToPrev(true)`.
    func testDraggingUpShowsThePreviousPage() {
        let result = ScrollPageMode.scroll(
            offset: 0,
            delta: 30,
            pageHeight: 100,
            visibleHeight: 100,
            hasPrevious: true,
            hasNext: true
        )
        XCTAssertEqual(result.offset, -70)
        XCTAssertEqual(result.pageDelta, -1)
    }

    /// Dragging past the bottom of the page shows the next page — upstream
    /// `pageFactory.moveToNext(upContent = true)`.
    func testDraggingDownShowsTheNextPage() {
        let result = ScrollPageMode.scroll(
            offset: 0,
            delta: -150,
            pageHeight: 100,
            visibleHeight: 100,
            hasPrevious: true,
            hasNext: true
        )
        XCTAssertEqual(result.offset, -50)
        XCTAssertEqual(result.pageDelta, 1)
    }

    /// The offset is corrected by the page height, so the content does not
    /// jump when the page changes.
    func testTheOffsetIsCorrectedByThePageHeight() {
        let result = ScrollPageMode.scroll(
            offset: -20,
            delta: -120,
            pageHeight: 100,
            visibleHeight: 100,
            hasPrevious: true,
            hasNext: true
        )
        XCTAssertEqual(result.offset, -40)
        XCTAssertEqual(result.pageDelta, 1)
    }

    // MARK: - The tap that turns the page

    /// The tap scrolls so that the last line of the page stays visible —
    /// upstream `ScrollPageDelegate.calcNextPageOffset`.
    func testTheNextOffsetKeepsTheLastLineVisible() {
        let offset = ScrollPageMode.nextOffset(
            lastLineTop: 500,
            paddingTop: 20,
            visibleHeight: 800,
            isImage: false,
            hasImageOrEmpty: false,
            isTextStyle: false
        )
        XCTAssertEqual(offset, -480)
    }

    /// A book of images scrolls by the whole visible height.
    func testTheNextOffsetUsesTheVisibleHeightForAnImageBook() {
        let offset = ScrollPageMode.nextOffset(
            lastLineTop: 500,
            paddingTop: 20,
            visibleHeight: 800,
            isImage: true,
            hasImageOrEmpty: false,
            isTextStyle: false
        )
        XCTAssertEqual(offset, -800)
    }

    /// A page with an image scrolls by the whole visible height — unless the
    /// image style is the text-only one.
    func testTheNextOffsetUsesTheVisibleHeightWhenThePageHasAnImage() {
        let offset = ScrollPageMode.nextOffset(
            lastLineTop: 500,
            paddingTop: 20,
            visibleHeight: 800,
            isImage: false,
            hasImageOrEmpty: true,
            isTextStyle: false
        )
        XCTAssertEqual(offset, -800)
    }

    /// The text-only image style keeps the line-based distance.
    func testTheTextStyleKeepsTheLineDistance() {
        let offset = ScrollPageMode.nextOffset(
            lastLineTop: 500,
            paddingTop: 20,
            visibleHeight: 800,
            isImage: false,
            hasImageOrEmpty: true,
            isTextStyle: true
        )
        XCTAssertEqual(offset, -480)
    }

    /// The tap that turns the page back — upstream
    /// `ScrollPageDelegate.calcPrevPageOffset`.
    func testThePreviousOffsetKeepsTheFirstLineVisible() {
        let offset = ScrollPageMode.previousOffset(
            firstLineBottom: 40,
            paddingTop: 20,
            visibleHeight: 800,
            isImage: false,
            hasImageOrEmpty: false,
            isTextStyle: false
        )
        XCTAssertEqual(offset, 780)
    }

    /// A book of images scrolls back by the whole visible height.
    func testThePreviousOffsetUsesTheVisibleHeightForAnImageBook() {
        let offset = ScrollPageMode.previousOffset(
            firstLineBottom: 40,
            paddingTop: 20,
            visibleHeight: 800,
            isImage: true,
            hasImageOrEmpty: false,
            isTextStyle: false
        )
        XCTAssertEqual(offset, 800)
    }

    // MARK: - The stacked pages

    /// The current page, the next page and the page after that are drawn —
    /// upstream `ContentTextView.drawPage`.
    func testThePagesAreStacked() {
        let pages = ScrollPageMode.stackedPages(
            offset: 0,
            currentHeight: 100,
            nextHeight: 100,
            hasNext: true,
            hasNextPlus: true,
            nextPlusHeight: 100,
            visibleHeight: 250
        )
        XCTAssertEqual(pages.count, 3)
        XCTAssertEqual(pages.map(\.index), [0, 1, 2])
        XCTAssertEqual(pages.map(\.offset), [0, 100, 200])
    }

    /// The third page is only drawn when it is (partly) visible.
    func testTheThirdPageIsOnlyDrawnWhenItIsVisible() {
        let pages = ScrollPageMode.stackedPages(
            offset: 0,
            currentHeight: 100,
            nextHeight: 100,
            hasNext: true,
            hasNextPlus: true,
            nextPlusHeight: 100,
            visibleHeight: 150
        )
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(pages.map(\.index), [0, 1])
    }

    /// Without a next page only the current page is drawn.
    func testOnlyTheCurrentPageIsDrawnWithoutANextPage() {
        let pages = ScrollPageMode.stackedPages(
            offset: 0,
            currentHeight: 100,
            nextHeight: 0,
            hasNext: false,
            hasNextPlus: false,
            nextPlusHeight: 0,
            visibleHeight: 800
        )
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.first?.index, 0)
        XCTAssertEqual(pages.first?.offset, 0)
    }

    /// The offset moves the whole flow.
    func testTheOffsetMovesTheStack() {
        let pages = ScrollPageMode.stackedPages(
            offset: -30,
            currentHeight: 100,
            nextHeight: 100,
            hasNext: true,
            hasNextPlus: false,
            nextPlusHeight: 0,
            visibleHeight: 800
        )
        XCTAssertEqual(pages.map(\.offset), [-30, 70])
    }
}
