//
//  HomePageTests.swift
//  LegadoCoreTests
//
//  The tests of the start page — the port of upstream
//  `MainActivity.upHomePage()` (MainActivity.kt:385-398).
//

import XCTest
@testable import LegadoCore

final class HomePageTests: XCTestCase {

    func testTheRawValuesAreTheUpstreamOnes() {
        // Upstream knows "bookshelf", "explore", "rss" and "my".
        XCTAssertEqual(HomePage.allCases.map(\.rawValue), ["bookshelf", "explore", "rss", "my"])
    }

    func testTheExploreTabNeedsThePreference() {
        XCTAssertFalse(HomePage.explore.isVisible(showDiscovery: false, showRSS: true))
        XCTAssertTrue(HomePage.explore.isVisible(showDiscovery: true, showRSS: true))
    }

    func testTheRssTabNeedsThePreference() {
        XCTAssertFalse(HomePage.rss.isVisible(showDiscovery: true, showRSS: false))
        XCTAssertTrue(HomePage.rss.isVisible(showDiscovery: true, showRSS: true))
    }

    func testTheOtherTabsAreAlwaysVisible() {
        XCTAssertTrue(HomePage.bookshelf.isVisible(showDiscovery: false, showRSS: false))
        XCTAssertTrue(HomePage.my.isVisible(showDiscovery: false, showRSS: false))
    }

    func testThePreferenceIsStoredAsTheRawValue() {
        let settings = AppSettings(store: InMemorySettingsStore())
        XCTAssertEqual(settings.homePage, .bookshelf)
        settings.homePage = .explore
        XCTAssertEqual(settings.defaultHomePage, "explore")
        XCTAssertEqual(settings.homePage, .explore)
    }

    func testAnUnknownValueFallsBackToTheBookshelf() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.defaultHomePage = "something"
        XCTAssertEqual(settings.homePage, .bookshelf)
    }

    func testEveryTabHasATitle() {
        for page in HomePage.allCases {
            XCTAssertFalse(page.displayName.isEmpty)
            XCTAssertFalse(page.systemImage.isEmpty)
        }
    }
}
