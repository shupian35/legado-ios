import Foundation

/// The page-turn animation styles — upstream `constant/PageAnim.kt`.
///
/// ```kotlin
/// enum class PageAnim(val animType: Int) {
///     COVER(0), SLIDE(1), SIMULATION(2), SCROLL(3), NONE(4)
/// }
/// ```
public enum PageTurnStyle: Int, CaseIterable, Sendable {
    /// The page is peeled back (upstream `PageDelegateCover`).
    case cover = 0
    /// A plain horizontal slide (upstream `PageDelegateSlide`).
    case slide = 1
    /// A paper curl (upstream `PageDelegateSimulation`).
    case simulation = 2
    /// A continuous vertical scroll (upstream `PageDelegateScroll`).
    case scroll = 3
    /// An immediate page swap (upstream `PageDelegateNone`).
    case none = 4

    /// The Chinese name used by the upstream settings.
    public var name: String {
        switch self {
        case .cover: return "覆盖"
        case .slide: return "滑动"
        case .simulation: return "仿真"
        case .scroll: return "滚动"
        case .none: return "无"
        }
    }
}

/// The direction of a page turn.
public enum PageTurnDirection: Sendable, Equatable {
    case next
    case previous
}

/// The decision of the drag detector.
public enum PageTurnDecision: Sendable, Equatable {
    /// The drag did not pass the slop — nothing happens.
    case none
    /// The drag passed the slop — the page turns.
    case turn(PageTurnDirection)
}

/// The horizontal drag detector — upstream `ui/book/read/page/delegate/HorizontalPageDelegate.kt:62-110`.
///
/// The upstream rules are unusual and are reproduced exactly:
/// - the focal point is the **average of all the pointers**,
/// - the threshold is the **squared** distance (`pageSlopSquare2`),
/// - the direction is decided **purely by the drag direction** (right =
///   previous, left = next) — there is no fling-velocity threshold.
public struct PageTurnDragDetector: Sendable, Equatable {

    /// The touch slop — upstream `ReadView.pageTouchSlop` (0 = the platform slop).
    public var touchSlop: Double
    /// The animation speed in milliseconds per screen — upstream
    /// `ReadView.defaultAnimationSpeed` (300) and `keyAnimationSpeed` (100).
    public var animationSpeed: Int

    public init(touchSlop: Double = 8, animationSpeed: Int = 300) {
        self.touchSlop = touchSlop
        self.animationSpeed = animationSpeed
    }

    /// The squared slop — upstream `pageSlopSquare2`.
    public var squaredSlop: Double {
        touchSlop * touchSlop
    }

    /// The distance from the start of the drag.
    public static func distance(from start: CGPointLike, to current: CGPointLike) -> Double {
        let dx = current.x - start.x
        let dy = current.y - start.y
        return (dx * dx + dy * dy).squareRoot()
    }

    /// The decision for a horizontal drag of the given translation.
    ///
    /// - Parameters:
    ///   - translation: the horizontal translation of the focal point.
    ///   - viewWidth: the width of the reader view.
    ///   - vertical: `true` for the vertical (scroll) delegate, where an
    ///     upward drag goes to the next page.
    public func decide(translation: CGPointLike, viewWidth: Double, vertical: Bool = false) -> PageTurnDecision {
        guard viewWidth > 0 else { return .none }
        let dx = translation.x
        let dy = translation.y
        let distance = vertical ? abs(dy) : abs(dx)
        guard distance * distance >= squaredSlop else { return .none }
        if vertical {
            return dy < 0 ? .turn(.next) : .turn(.previous)
        }
        return dx < 0 ? .turn(.next) : .turn(.previous)
    }

    /// The animation duration — upstream `PageDelegate.startScroll`:
    /// `(animationSpeed * |dx|) / viewWidth`.
    public func animationDuration(distance: Double, viewWidth: Double) -> Double {
        guard viewWidth > 0 else { return 0 }
        return Double(animationSpeed) * abs(distance) / viewWidth
    }

    /// The animation duration of a key turn — the upstream uses the faster
    /// `keyAnimationSpeed` (100).
    public func keyAnimationDuration(distance: Double, viewWidth: Double) -> Double {
        var copy = self
        copy.animationSpeed = 100
        return copy.animationDuration(distance: distance, viewWidth: viewWidth)
    }
}

/// A minimal point — the port has no `CGPoint` on Linux.
public struct CGPointLike: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// The average of a list of points — upstream `HorizontalPageDelegate`
    /// averages all the pointers to get the focal point.
    public static func average(_ points: [CGPointLike]) -> CGPointLike {
        guard !points.isEmpty else { return CGPointLike(x: 0, y: 0) }
        let sum = points.reduce(CGPointLike(x: 0, y: 0)) { partial, point in
            CGPointLike(x: partial.x + point.x, y: partial.y + point.y)
        }
        return CGPointLike(x: sum.x / Double(points.count), y: sum.y / Double(points.count))
    }
}

/// The state of the page-turn gesture.
public struct PageTurnSession: Sendable, Equatable {

    /// The style of the turn.
    public var style: PageTurnStyle
    /// The detector.
    public var detector: PageTurnDragDetector
    /// The focal point when the drag started.
    public var startPoint: CGPointLike?
    /// The current focal point.
    public var currentPoint: CGPointLike?
    /// The decision of the last update.
    public var decision: PageTurnDecision

    public init(style: PageTurnStyle = .slide, detector: PageTurnDragDetector = PageTurnDragDetector()) {
        self.style = style
        self.detector = detector
        self.startPoint = nil
        self.currentPoint = nil
        self.decision = .none
    }

    /// Starts a drag.
    public mutating func begin(at point: CGPointLike) {
        startPoint = point
        currentPoint = point
        decision = .none
    }

    /// Updates the drag with the current pointer positions.
    public mutating func update(pointers: [CGPointLike], viewWidth: Double) -> PageTurnDecision {
        guard let start = startPoint else { return .none }
        let focal = CGPointLike.average(pointers)
        currentPoint = focal
        let translation = CGPointLike(x: focal.x - start.x, y: focal.y - start.y)
        let vertical = style == .scroll
        decision = detector.decide(translation: translation, viewWidth: viewWidth, vertical: vertical)
        return decision
    }

    /// Ends the drag and returns the final decision.
    public mutating func end() -> PageTurnDecision {
        let result = decision
        startPoint = nil
        currentPoint = nil
        decision = .none
        return result
    }

    /// The progress of the drag (0…1) — the fraction of the view width.
    public func progress(viewWidth: Double) -> Double {
        guard let start = startPoint, let current = currentPoint, viewWidth > 0 else { return 0 }
        return min(1, abs(current.x - start.x) / viewWidth)
    }

    /// The duration of the turn animation for the current drag.
    public func animationDuration(viewWidth: Double) -> Double {
        guard let start = startPoint, let current = currentPoint else { return 0 }
        return detector.animationDuration(distance: current.x - start.x, viewWidth: viewWidth)
    }
}
