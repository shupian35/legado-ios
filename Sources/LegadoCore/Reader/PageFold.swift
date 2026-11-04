import Foundation

/// The geometry of the page fold — the port of the upstream
/// `ui/book/read/page/delegate/SimulationPageDelegate.kt`.
///
/// The upstream peels the page back along a quadratic Bézier that starts at
/// the touch point and ends at the page corner. The port reproduces the whole
/// geometry in the engine (it is pure arithmetic and therefore testable on its
/// own) and the view layer only turns the numbers into transforms.
///
/// The upstream's algorithm (`calcCornerXY`, `calcPoints`, `getCross`):
/// 1. the corner is the page corner nearest to the touch point,
/// 2. the middle point is the midpoint of the touch and the corner,
/// 3. the two control points are derived from the middle point and the corner,
/// 4. the two Bézier start points are half way between the control point and
///    the opposite edge,
/// 5. the two end points are the intersections of the touch→control lines
///    with the fixed edge,
/// 6. the two vertices are the quadratic Bézier vertex formula
///    `(p0 + 2·p1 + p2) / 4`.
public struct PageFold: Sendable, Equatable {

    /// The touch point of the drag.
    public var touch: CGPointLike
    /// The page corner that the page is folded towards.
    public var corner: CGPointLike
    /// The start point of the first Bézier curve — the fixed edge.
    public var start1: CGPointLike
    /// The control point of the first Bézier curve.
    public var control1: CGPointLike
    /// The end point of the first Bézier curve.
    public var end1: CGPointLike
    /// The vertex of the first Bézier curve.
    public var vertex1: CGPointLike
    /// The start point of the second Bézier curve — the fixed edge.
    public var start2: CGPointLike
    /// The control point of the second Bézier curve.
    public var control2: CGPointLike
    /// The end point of the second Bézier curve.
    public var end2: CGPointLike
    /// The vertex of the second Bézier curve.
    public var vertex2: CGPointLike
    /// Whether the corner is the right-top or the left-bottom one — upstream
    /// `mIsRtOrLb`.
    public var isRightTopOrLeftBottom: Bool
    /// The distance between the touch point and the corner — upstream
    /// `mTouchToCornerDis`.
    public var touchToCornerDistance: Double
    /// The rotation of the folded page in degrees — upstream `mDegrees`.
    public var degrees: Double
}

/// The page-fold geometry — upstream `SimulationPageDelegate`.
public enum PageFoldGeometry {

    /// The corner the page is folded towards — upstream `calcCornerXY`.
    ///
    /// The corner is the page corner nearest to the touch point: the left
    /// edge when the touch is in the left half, the bottom edge when the touch
    /// is in the bottom half.
    public static func corner(
        for touch: CGPointLike,
        viewWidth: Double,
        viewHeight: Double
    ) -> CGPointLike {
        CGPointLike(
            x: touch.x <= viewWidth / 2 ? 0 : viewWidth,
            y: touch.y <= viewHeight / 2 ? 0 : viewHeight
        )
    }

    /// Whether the corner is the right-top or the left-bottom one — upstream
    /// `mIsRtOrLb`.
    public static func isRightTopOrLeftBottom(corner: CGPointLike, viewWidth: Double, viewHeight: Double) -> Bool {
        let isLeftBottom = corner.x == 0 && corner.y == viewHeight
        let isRightTop = corner.y == 0 && corner.x == viewWidth
        return isLeftBottom || isRightTop
    }

    /// The whole fold — upstream `calcPoints` + `drawNextPageAreaAndShadow`.
    ///
    /// - Parameters:
    ///   - touch: the touch point of the drag.
    ///   - corner: the corner the page is folded towards.
    ///   - viewWidth: the width of the reader view.
    ///   - viewHeight: the height of the reader view.
    public static func fold(
        touch: CGPointLike,
        corner: CGPointLike,
        viewWidth: Double,
        viewHeight: Double
    ) -> PageFold {
        var touchX = touch.x
        var touchY = touch.y
        var middleX = (touchX + corner.x) / 2
        var middleY = (touchY + corner.y) / 2
        var control1X = middleX - (corner.y - middleY) * (corner.y - middleY) / (corner.x - middleX)
        let control1Y = corner.y
        let control2X = corner.x
        var control2Y: Double
        let f4 = corner.y - middleY
        if f4 == 0 {
            control2Y = middleY - (corner.x - middleX) * (corner.x - middleX) / 0.1
        } else {
            control2Y = middleY - (corner.x - middleX) * (corner.x - middleX) / f4
        }
        var start1X = control1X - (corner.x - control1X) / 2
        let start1Y = corner.y

        // The fixed left edge — when the start point leaves the view the touch
        // point is moved back onto the fold (upstream `calcPoints`).
        if touchX > 0 && touchX < viewWidth, start1X < 0 || start1X > viewWidth {
            if start1X < 0 {
                start1X = viewWidth - start1X
            }
            let f1 = abs(corner.x - touchX)
            let f2 = viewWidth * f1 / start1X
            touchX = abs(corner.x - f2)
            let f3 = abs(corner.x - touchX) * abs(corner.y - touchY) / f1
            touchY = abs(corner.y - f3)
            middleX = (touchX + corner.x) / 2
            middleY = (touchY + corner.y) / 2
            control1X = middleX - (corner.y - middleY) * (corner.y - middleY) / (corner.x - middleX)
            let f5 = corner.y - middleY
            if f5 == 0 {
                control2Y = middleY - (corner.x - middleX) * (corner.x - middleX) / 0.1
            } else {
                control2Y = middleY - (corner.x - middleX) * (corner.x - middleX) / f5
            }
            start1X = control1X - (corner.x - control1X) / 2
        }
        let start2X = corner.x
        let start2Y = control2Y - (corner.y - control2Y) / 2

        let touchToCornerDistance = (
            (touchX - corner.x) * (touchX - corner.x) + (touchY - corner.y) * (touchY - corner.y)
        ).squareRoot()

        let start1 = CGPointLike(x: start1X, y: start1Y)
        let start2 = CGPointLike(x: start2X, y: start2Y)
        let control1 = CGPointLike(x: control1X, y: control1Y)
        let control2 = CGPointLike(x: control2X, y: control2Y)
        let end1 = cross(CGPointLike(x: touchX, y: touchY), control1, start1, start2)
        let end2 = cross(CGPointLike(x: touchX, y: touchY), control2, start1, start2)
        let vertex1 = CGPointLike(
            x: (start1.x + 2 * control1.x + end1.x) / 4,
            y: (2 * control1.y + start1.y + end1.y) / 4
        )
        let vertex2 = CGPointLike(
            x: (start2.x + 2 * control2.x + end2.x) / 4,
            y: (2 * control2.y + start2.y + end2.y) / 4
        )
        let degrees = atan2(control1.x - corner.x, control2.y - corner.y) * 180 / Double.pi

        return PageFold(
            touch: CGPointLike(x: touchX, y: touchY),
            corner: corner,
            start1: start1,
            control1: control1,
            end1: end1,
            vertex1: vertex1,
            start2: start2,
            control2: control2,
            end2: end2,
            vertex2: vertex2,
            isRightTopOrLeftBottom: isRightTopOrLeftBottom(corner: corner, viewWidth: viewWidth, viewHeight: viewHeight),
            touchToCornerDistance: touchToCornerDistance,
            degrees: degrees
        )
    }

    /// The intersection of the line `p1→p2` and the line `p3→p4` — upstream
    /// `getCross`.
    public static func cross(
        _ p1: CGPointLike,
        _ p2: CGPointLike,
        _ p3: CGPointLike,
        _ p4: CGPointLike
    ) -> CGPointLike {
        let a1 = (p2.y - p1.y) / (p2.x - p1.x)
        let b1 = (p1.x * p2.y - p2.x * p1.y) / (p1.x - p2.x)
        let a2 = (p4.y - p3.y) / (p4.x - p3.x)
        let b2 = (p3.x * p4.y - p4.x * p3.y) / (p3.x - p4.x)
        let x = (b2 - b1) / (a1 - a2)
        return CGPointLike(x: x, y: a1 * x + b1)
    }

    /// The offset the fold animation runs to — upstream `onAnimStart`.
    ///
    /// The page is folded all the way into the corner; when the animation is
    /// cancelled the page returns to the touch point.
    public static func animationOffset(
        touch: CGPointLike,
        corner: CGPointLike,
        direction: PageTurnDirection,
        cancelled: Bool,
        viewWidth: Double,
        viewHeight: Double
    ) -> CGPointLike {
        var dx: Double
        let dy: Double
        if cancelled {
            dx = corner.x > 0 && direction == .next ? viewWidth - touch.x : -touch.x
            if direction != .next {
                dx = -(viewWidth + touch.x)
            }
            dy = corner.y > 0 ? viewHeight - touch.y : -touch.y
        } else {
            dx = corner.x > 0 && direction == .next ? -(viewWidth + touch.x) : viewWidth - touch.x
            dy = corner.y > 0 ? viewHeight - touch.y : 1 - touch.y
        }
        return CGPointLike(x: dx, y: dy)
    }
}

/// The edge the turning page is hinged on.
public enum PageTurnHinge: Sendable, Equatable {
    /// The left edge — the page turns to the left.
    case leading
    /// The right edge — the page turns to the right.
    case trailing
}

/// The transforms of a page turn — the port of the three horizontal page
/// delegates of the upstream (`CoverPageDelegate`, `SlidePageDelegate` and
/// `SimulationPageDelegate`).
///
/// The upstream draws the pages on an Android `Canvas`; the port draws them
/// with SwiftUI transforms, so the engine computes the offsets, the rotation
/// and the hinge and the view layer only applies them.
public struct PageTurnLayout: Sendable, Equatable {

    /// The style of the turn.
    public var style: PageTurnStyle
    /// The direction of the turn.
    public var direction: PageTurnDirection
    /// The fraction of the turn that has been travelled (0…1).
    public var progress: Double
    /// The horizontal offset of the page that is turned away.
    public var currentOffsetX: Double
    /// The horizontal offset of the page that is revealed.
    public var revealedOffsetX: Double
    /// The rotation of the turning page around the vertical axis — the
    /// upstream's simulation folds the page back.
    public var rotationDegrees: Double
    /// The edge the turning page is hinged on.
    public var hinge: PageTurnHinge
    /// Whether the revealed page is drawn underneath the turning one.
    public var drawsRevealedPage: Bool

    /// The layout of a turn.
    ///
    /// - The **slide** moves the revealed page in from the side — both pages
    ///   travel together (upstream `SlidePageDelegate.onDraw`).
    /// - The **cover** keeps the revealed page in place and slides the current
    ///   page over it, with a shadow along the leading edge (upstream
    ///   `CoverPageDelegate.onDraw`).
    /// - The **simulation** folds the current page back around the hinge
    ///   (upstream `SimulationPageDelegate.onDraw`).
    public init(
        style: PageTurnStyle,
        direction: PageTurnDirection,
        progress: Double,
        viewWidth: Double,
        viewHeight: Double = 0
    ) {
        self.style = style
        self.direction = direction
        let p = min(max(progress, 0), 1)
        self.progress = p
        let isNext = direction == .next
        switch style {
        case .slide:
            currentOffsetX = isNext ? -p * viewWidth : p * viewWidth
            revealedOffsetX = isNext ? viewWidth - p * viewWidth : -viewWidth + p * viewWidth
            rotationDegrees = 0
            hinge = isNext ? .leading : .trailing
            drawsRevealedPage = true
        case .cover:
            currentOffsetX = isNext ? -p * viewWidth : p * viewWidth
            revealedOffsetX = 0
            rotationDegrees = 0
            hinge = isNext ? .leading : .trailing
            drawsRevealedPage = true
        case .simulation:
            currentOffsetX = isNext ? -p * viewWidth * 0.08 : p * viewWidth * 0.08
            revealedOffsetX = 0
            rotationDegrees = isNext ? p * 90 : -p * 90
            hinge = isNext ? .leading : .trailing
            drawsRevealedPage = true
        case .scroll, .none:
            currentOffsetX = 0
            revealedOffsetX = 0
            rotationDegrees = 0
            hinge = .leading
            drawsRevealedPage = false
        }
    }

    /// The width of the shadow along the leading edge of the moving page —
    /// upstream `CoverPageDelegate.addShadow` uses 30 points.
    public static let shadowWidth: Double = 30
}
