import XCTest
@testable import LegadoCore

/// The page-turn styles and the drag detector — upstream
/// `constant/PageAnim.kt` and `ui/book/read/page/delegate/HorizontalPageDelegate.kt`.
final class PageTurnTests: XCTestCase {

    func testTheStylesMatchTheUpstreamValues() {
        XCTAssertEqual(PageTurnStyle.cover.rawValue, 0)
        XCTAssertEqual(PageTurnStyle.slide.rawValue, 1)
        XCTAssertEqual(PageTurnStyle.simulation.rawValue, 2)
        XCTAssertEqual(PageTurnStyle.scroll.rawValue, 3)
        XCTAssertEqual(PageTurnStyle.none.rawValue, 4)
        XCTAssertEqual(PageTurnStyle.allCases.count, 5)
        XCTAssertEqual(PageTurnStyle.cover.name, "覆盖")
    }

    func testTheSquaredSlop() {
        let detector = PageTurnDragDetector(touchSlop: 8)
        XCTAssertEqual(detector.squaredSlop, 64)
    }

    func testASmallDragDoesNotTurnThePage() {
        let detector = PageTurnDragDetector(touchSlop: 8)
        let decision = detector.decide(translation: CGPointLike(x: -4, y: 0), viewWidth: 400)
        XCTAssertEqual(decision, .none)
    }

    func testALeftDragGoesToTheNextPage() {
        let detector = PageTurnDragDetector(touchSlop: 8)
        XCTAssertEqual(detector.decide(translation: CGPointLike(x: -40, y: 0), viewWidth: 400), .turn(.next))
    }

    func testARightDragGoesToThePreviousPage() {
        let detector = PageTurnDragDetector(touchSlop: 8)
        XCTAssertEqual(detector.decide(translation: CGPointLike(x: 40, y: 0), viewWidth: 400), .turn(.previous))
    }

    func testTheVerticalDelegateUsesTheVerticalAxis() {
        let detector = PageTurnDragDetector(touchSlop: 8)
        XCTAssertEqual(detector.decide(translation: CGPointLike(x: 0, y: -40), viewWidth: 400, vertical: true), .turn(.next))
        XCTAssertEqual(detector.decide(translation: CGPointLike(x: 0, y: 40), viewWidth: 400, vertical: true), .turn(.previous))
    }

    func testTheAnimationDurationUsesTheUpstreamFormula() {
        let detector = PageTurnDragDetector(touchSlop: 8, animationSpeed: 300)
        // (300 * 200) / 400 = 150
        XCTAssertEqual(detector.animationDuration(distance: 200, viewWidth: 400), 150, accuracy: 0.0001)
        XCTAssertEqual(detector.keyAnimationDuration(distance: 200, viewWidth: 400), 50, accuracy: 0.0001)
    }

    func testTheFocalPointIsTheAverageOfThePointers() {
        let average = CGPointLike.average([
            CGPointLike(x: 0, y: 0),
            CGPointLike(x: 100, y: 40)
        ])
        XCTAssertEqual(average.x, 50)
        XCTAssertEqual(average.y, 20)
    }

    func testTheSessionDecidesAfterTheSlop() {
        var session = PageTurnSession(style: .slide)
        session.begin(at: CGPointLike(x: 200, y: 300))
        XCTAssertEqual(session.update(pointers: [CGPointLike(x: 200, y: 300)], viewWidth: 400), .none)
        XCTAssertEqual(session.update(pointers: [CGPointLike(x: 100, y: 300)], viewWidth: 400), .turn(.next))
        XCTAssertEqual(session.end(), .turn(.next))
        XCTAssertNil(session.startPoint)
    }

    func testTheSessionProgress() {
        var session = PageTurnSession(style: .slide)
        session.begin(at: CGPointLike(x: 200, y: 300))
        session.update(pointers: [CGPointLike(x: 100, y: 300)], viewWidth: 400)
        XCTAssertEqual(session.progress(viewWidth: 400), 0.25, accuracy: 0.0001)
        XCTAssertEqual(session.animationDuration(viewWidth: 400), 75, accuracy: 0.0001)
    }

    func testTheScrollStyleUsesTheVerticalAxis() {
        var session = PageTurnSession(style: .scroll)
        session.begin(at: CGPointLike(x: 200, y: 300))
        XCTAssertEqual(session.update(pointers: [CGPointLike(x: 200, y: 200)], viewWidth: 400), .turn(.next))
    }
}
