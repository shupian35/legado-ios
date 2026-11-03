//
//  ReaderInteractionTests.swift
//  LegadoCoreTests
//
//  The nine tap zones and the click actions of the reader.
//

import XCTest
@testable import LegadoCore

final class TapZoneTests: XCTestCase {

    private let width: Double = 1000
    private let height: Double = 2000

    private func zone(_ x: Double, _ y: Double) -> TapZone? {
        TapZoneMapper.zone(atX: x, y: y, width: width, height: height)
    }

    func testEveryZoneIsHitAtItsCentre() {
        XCTAssertEqual(zone(100, 100), .topLeft)
        XCTAssertEqual(zone(500, 100), .topCenter)
        XCTAssertEqual(zone(900, 100), .topRight)
        XCTAssertEqual(zone(100, 1000), .middleLeft)
        XCTAssertEqual(zone(500, 1000), .middleCenter)
        XCTAssertEqual(zone(900, 1000), .middleRight)
        XCTAssertEqual(zone(100, 1900), .bottomLeft)
        XCTAssertEqual(zone(500, 1900), .bottomCenter)
        XCTAssertEqual(zone(900, 1900), .bottomRight)
    }

    /// Upstream draws the top-right rect from 0.36 of the width, so the strip
    /// between 0.36 and 0.66 belongs to the top-center zone (the dispatch
    /// tests the center first).
    func testTheTopRightRectStartsAtThirtySixPercent() {
        XCTAssertEqual(zone(380, 100), .topCenter)
        XCTAssertEqual(zone(659, 100), .topCenter)
        XCTAssertEqual(zone(700, 100), .topRight)
    }

    /// Upstream `RectF.contains` uses strict inequalities, so the borders
    /// between two zones belong to neither.
    func testTheBordersBetweenTwoZonesHitNoZone() {
        XCTAssertNil(zone(330, 100))
        XCTAssertNil(zone(500, 660))
    }

    func testTheDispatchOrderIsTheUpstreamOne() {
        XCTAssertEqual(
            TapZoneMapper.dispatchOrder,
            [.middleCenter, .bottomCenter, .bottomLeft, .bottomRight,
             .middleLeft, .middleRight, .topLeft, .topCenter, .topRight]
        )
    }

    func testATapOutsideThePageHitsNoZone() {
        XCTAssertNil(zone(-10, -10))
        XCTAssertNil(zone(2000, 100))
    }

    func testTheRectsUseThirds() {
        let rects = TapZoneMapper.rects(width: 300, height: 300)
        XCTAssertEqual(rects[.topLeft], ReaderRect(left: 0, top: 0, right: 99, bottom: 99))
        XCTAssertEqual(rects[.middleCenter], ReaderRect(left: 99, top: 99, right: 198, bottom: 198))
        XCTAssertEqual(rects[.bottomRight], ReaderRect(left: 198, top: 198, right: 300, bottom: 300))
        // The upstream quirk.
        XCTAssertEqual(rects[.topRight]?.left, 108)
    }
}

final class ClickActionTests: XCTestCase {

    func testTheDefaultActionOfEveryZone() {
        XCTAssertEqual(TapZone.topLeft.defaultAction, .prevPage)
        XCTAssertEqual(TapZone.topCenter.defaultAction, .prevPage)
        XCTAssertEqual(TapZone.topRight.defaultAction, .nextPage)
        XCTAssertEqual(TapZone.middleLeft.defaultAction, .prevPage)
        XCTAssertEqual(TapZone.middleCenter.defaultAction, .menu)
        XCTAssertEqual(TapZone.middleRight.defaultAction, .nextPage)
        XCTAssertEqual(TapZone.bottomLeft.defaultAction, .prevPage)
        XCTAssertEqual(TapZone.bottomCenter.defaultAction, .nextPage)
        XCTAssertEqual(TapZone.bottomRight.defaultAction, .nextPage)
    }

    func testTheActionValuesMatchUpstream() {
        XCTAssertEqual(ClickAction.noAction.rawValue, -1)
        XCTAssertEqual(ClickAction.menu.rawValue, 0)
        XCTAssertEqual(ClickAction.nextPage.rawValue, 1)
        XCTAssertEqual(ClickAction.prevPage.rawValue, 2)
        XCTAssertEqual(ClickAction.nextChapter.rawValue, 3)
        XCTAssertEqual(ClickAction.prevChapter.rawValue, 4)
        XCTAssertEqual(ClickAction.prevParagraph.rawValue, 5)
        XCTAssertEqual(ClickAction.nextParagraph.rawValue, 6)
        XCTAssertEqual(ClickAction.addBookmark.rawValue, 7)
        XCTAssertEqual(ClickAction.editContent.rawValue, 8)
        XCTAssertEqual(ClickAction.toggleReplaceRule.rawValue, 9)
        XCTAssertEqual(ClickAction.chapterList.rawValue, 10)
        XCTAssertEqual(ClickAction.searchContent.rawValue, 11)
        XCTAssertEqual(ClickAction.syncProgress.rawValue, 12)
        XCTAssertEqual(ClickAction.pauseResumeReadAloud.rawValue, 13)
    }

    func testTheConfigurationResolvesTheActionOfATap() {
        let configuration = ReaderClickConfiguration()
        XCTAssertEqual(configuration.action(atX: 500, y: 1000, width: 1000, height: 2000), .menu)
        XCTAssertEqual(configuration.action(atX: 100, y: 100, width: 1000, height: 2000), .prevPage)
        XCTAssertEqual(configuration.action(atX: 900, y: 100, width: 1000, height: 2000), .nextPage)
    }

    /// Upstream `AppConfig.detectClickArea()` — without a menu zone the
    /// middle-center is restored to the menu.
    func testTheConfigurationIsRepairedWhenNoZoneIsTheMenu() {
        var configuration = ReaderClickConfiguration()
        for zone in TapZone.allCases {
            configuration.actions[zone] = .nextPage
        }
        let repaired = configuration.repaired()
        XCTAssertEqual(repaired.action(for: .middleCenter), .menu)
        XCTAssertEqual(repaired.action(for: .topLeft), .nextPage)
    }

    func testTheConfigurationIsNotRepairedWhenAZoneIsTheMenu() {
        var configuration = ReaderClickConfiguration()
        configuration.actions[.topLeft] = .menu
        let repaired = configuration.repaired()
        XCTAssertEqual(repaired.action(for: .topLeft), .menu)
        XCTAssertEqual(repaired.action(for: .middleCenter), .menu)
    }

    /// The zones and the preference regions use the same nine positions.
    func testEveryZoneMapsToItsPreferenceRegion() {
        XCTAssertEqual(TapZone.topLeft.clickRegion, .topLeft)
        XCTAssertEqual(TapZone.topCenter.clickRegion, .topCenter)
        XCTAssertEqual(TapZone.topRight.clickRegion, .topRight)
        XCTAssertEqual(TapZone.middleLeft.clickRegion, .middleLeft)
        XCTAssertEqual(TapZone.middleCenter.clickRegion, .middleCenter)
        XCTAssertEqual(TapZone.middleRight.clickRegion, .middleRight)
        XCTAssertEqual(TapZone.bottomLeft.clickRegion, .bottomLeft)
        XCTAssertEqual(TapZone.bottomCenter.clickRegion, .bottomCenter)
        XCTAssertEqual(TapZone.bottomRight.clickRegion, .bottomRight)
    }

    /// The configuration is built from the `clickAction*` preferences.
    ///
    /// The upstream self-healing rule applies: when NO zone is mapped to the
    /// menu the middle-center is reset to the menu (`AppConfig.detectClickArea`).
    func testTheConfigurationIsBuiltFromThePreferences() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        settings.set(1, for: .clickActionTR)
        settings.set(10, for: .clickActionTL)
        let configuration = ReaderClickConfiguration.from(settings: settings)
        XCTAssertEqual(configuration.action(for: .topRight), .nextPage)
        XCTAssertEqual(configuration.action(for: .topLeft), .chapterList)
        // The middle-center keeps the upstream default (the menu) because no
        // zone was mapped to it.
        XCTAssertEqual(configuration.action(for: .middleCenter), .menu)
        // The untouched zones keep the upstream defaults.
        XCTAssertEqual(configuration.action(for: .middleRight), .nextPage)
        XCTAssertEqual(configuration.action(for: .bottomLeft), .prevPage)
    }
}

final class ReaderGestureTests: XCTestCase {

    func testTheGestureConstants() {
        XCTAssertEqual(ReaderGesture.longPressTimeout, 0.6)
        XCTAssertEqual(ReaderGesture.defaultAnimationSpeed, 300)
        XCTAssertEqual(ReaderGesture.keyAnimationSpeed, 100)
        XCTAssertEqual(ReaderGesture.squaredSlop(8), 64)
    }

    /// Upstream `startScroll`: `(animationSpeed * |dx|) / viewWidth`.
    func testTheAnimationDurationIsProportionalToTheDistance() {
        XCTAssertEqual(ReaderGesture.animationDuration(distance: 100, viewWidth: 1000), 30)
        XCTAssertEqual(ReaderGesture.animationDuration(distance: 1000, viewWidth: 1000), 300)
        XCTAssertEqual(ReaderGesture.animationDuration(distance: -500, viewWidth: 1000), 150)
    }
}
