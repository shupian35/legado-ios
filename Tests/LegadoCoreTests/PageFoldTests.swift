import XCTest
@testable import LegadoCore

/// The page-fold geometry — the port of the upstream
/// `SimulationPageDelegate` (`calcCornerXY`, `calcPoints`, `getCross`).
final class PageFoldTests: XCTestCase {

    private func accuracy(_ value: Double, _ expected: Double, _ tolerance: Double = 0.001) {
        XCTAssertEqual(value, expected, accuracy: tolerance)
    }

    // MARK: - The corner

    func testCornerIsTheNearestOne() {
        // The left half and the top half → the top-left corner.
        let topLeft = PageFoldGeometry.corner(
            for: CGPointLike(x: 100, y: 100),
            viewWidth: 400,
            viewHeight: 600
        )
        XCTAssertEqual(topLeft.x, 0)
        XCTAssertEqual(topLeft.y, 0)

        // The right half and the bottom half → the bottom-right corner.
        let bottomRight = PageFoldGeometry.corner(
            for: CGPointLike(x: 300, y: 400),
            viewWidth: 400,
            viewHeight: 600
        )
        XCTAssertEqual(bottomRight.x, 400)
        XCTAssertEqual(bottomRight.y, 600)

        // The right half and the top half → the top-right corner.
        let topRight = PageFoldGeometry.corner(
            for: CGPointLike(x: 390, y: 10),
            viewWidth: 400,
            viewHeight: 600
        )
        XCTAssertEqual(topRight.x, 400)
        XCTAssertEqual(topRight.y, 0)
    }

    func testRightTopOrLeftBottom() {
        // The bottom-right corner is neither.
        XCTAssertFalse(
            PageFoldGeometry.isRightTopOrLeftBottom(
                corner: CGPointLike(x: 400, y: 600),
                viewWidth: 400,
                viewHeight: 600
            )
        )
        // The bottom-left corner is.
        XCTAssertTrue(
            PageFoldGeometry.isRightTopOrLeftBottom(
                corner: CGPointLike(x: 0, y: 600),
                viewWidth: 400,
                viewHeight: 600
            )
        )
        // The top-right corner is.
        XCTAssertTrue(
            PageFoldGeometry.isRightTopOrLeftBottom(
                corner: CGPointLike(x: 400, y: 0),
                viewWidth: 400,
                viewHeight: 600
            )
        )
    }

    // MARK: - The fold

    func testFoldOfTheBottomRightCorner() {
        let fold = PageFoldGeometry.fold(
            touch: CGPointLike(x: 300, y: 400),
            corner: CGPointLike(x: 400, y: 600),
            viewWidth: 400,
            viewHeight: 600
        )
        // The middle point is (350, 500); the control points follow the
        // upstream's formula.
        accuracy(fold.control1.x, 150)
        accuracy(fold.control1.y, 600)
        accuracy(fold.control2.x, 400)
        accuracy(fold.control2.y, 475)
        // The start points are half way between the control point and the edge.
        accuracy(fold.start1.x, 25)
        accuracy(fold.start1.y, 600)
        accuracy(fold.start2.x, 400)
        accuracy(fold.start2.y, 412.5)
        // The end points are the intersections of the two lines.
        accuracy(fold.end1.x, 225)
        accuracy(fold.end1.y, 500)
        accuracy(fold.end2.x, 350)
        accuracy(fold.end2.y, 437.5)
        // The vertices use the quadratic Bézier vertex formula.
        accuracy(fold.vertex1.x, 137.5)
        accuracy(fold.vertex1.y, 575)
        accuracy(fold.vertex2.x, 387.5)
        accuracy(fold.vertex2.y, 450)
        accuracy(fold.touchToCornerDistance, 223.6067977499789, 0.0001)
        accuracy(fold.degrees, -116.565051177078, 0.0001)
        XCTAssertFalse(fold.isRightTopOrLeftBottom)
    }

    func testFoldOfTheTopLeftCorner() {
        let fold = PageFoldGeometry.fold(
            touch: CGPointLike(x: 100, y: 100),
            corner: CGPointLike(x: 0, y: 0),
            viewWidth: 400,
            viewHeight: 600
        )
        // The middle point is (50, 50).
        // control1.x = 50 - (0-50)²/(0-50) = 50 + 50 = 100; control1.y = 0.
        accuracy(fold.control1.x, 100)
        accuracy(fold.control1.y, 0)
        // f4 = 0 - 50 = -50 → control2.y = 50 - (0-50)²/(-50) = 50 + 50 = 100.
        accuracy(fold.control2.x, 0)
        accuracy(fold.control2.y, 100)
        // start1.x = 100 - (0-100)/2 = 150.
        accuracy(fold.start1.x, 150)
        accuracy(fold.start1.y, 0)
        // start2.y = 100 - (0-100)/2 = 150.
        accuracy(fold.start2.x, 0)
        accuracy(fold.start2.y, 150)
    }

    func testCrossOfTwoLines() {
        // The diagonal y = x and the anti-diagonal y = 100 - x meet at (50, 50).
        let point = PageFoldGeometry.cross(
            CGPointLike(x: 0, y: 0),
            CGPointLike(x: 100, y: 100),
            CGPointLike(x: 0, y: 100),
            CGPointLike(x: 100, y: 0)
        )
        accuracy(point.x, 50)
        accuracy(point.y, 50)
    }

    func testAnimationOffset() {
        // The page is folded into the bottom-right corner.
        let offset = PageFoldGeometry.animationOffset(
            touch: CGPointLike(x: 300, y: 400),
            corner: CGPointLike(x: 400, y: 600),
            direction: .next,
            cancelled: false,
            viewWidth: 400,
            viewHeight: 600
        )
        // dx = -(viewWidth + touchX), dy = viewHeight - touchY.
        accuracy(offset.x, -700)
        accuracy(offset.y, 200)

        // The cancelled animation returns to the touch point.
        let cancelled = PageFoldGeometry.animationOffset(
            touch: CGPointLike(x: 300, y: 400),
            corner: CGPointLike(x: 400, y: 600),
            direction: .next,
            cancelled: true,
            viewWidth: 400,
            viewHeight: 600
        )
        accuracy(cancelled.x, 100)
        accuracy(cancelled.y, 200)
    }

    // MARK: - The layout of the three horizontal styles

    func testSlideMovesBothPages() {
        let layout = PageTurnLayout(style: .slide, direction: .next, progress: 0.5, viewWidth: 400)
        accuracy(layout.currentOffsetX, -200)
        accuracy(layout.revealedOffsetX, 200)
        accuracy(layout.rotationDegrees, 0)
        XCTAssertTrue(layout.drawsRevealedPage)
    }

    func testCoverKeepsTheRevealedPageInPlace() {
        let layout = PageTurnLayout(style: .cover, direction: .next, progress: 0.5, viewWidth: 400)
        accuracy(layout.currentOffsetX, -200)
        accuracy(layout.revealedOffsetX, 0)
        accuracy(layout.rotationDegrees, 0)
    }

    func testSimulationFoldsThePage() {
        let layout = PageTurnLayout(style: .simulation, direction: .next, progress: 0.5, viewWidth: 400)
        accuracy(layout.rotationDegrees, 45)
        XCTAssertEqual(layout.hinge, .leading)
        let previous = PageTurnLayout(style: .simulation, direction: .previous, progress: 0.5, viewWidth: 400)
        accuracy(previous.rotationDegrees, -45)
        XCTAssertEqual(previous.hinge, .trailing)
    }

    func testProgressIsClamped() {
        let layout = PageTurnLayout(style: .slide, direction: .next, progress: 3, viewWidth: 400)
        accuracy(layout.progress, 1)
        accuracy(layout.currentOffsetX, -400)
    }
}
