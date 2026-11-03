//
//  LauncherIconTests.swift
//  LegadoCoreTests
//
//  The launcher icon preference — upstream `help/LauncherIconHelp.kt`.
//

import XCTest
@testable import LegadoCore

final class LauncherIconTests: XCTestCase {

    func testTheNamesAreTheUpstreamActivityNames() {
        XCTAssertEqual(LauncherIcon.allCases.map { $0.rawValue },
                       ["Launcher1", "Launcher2", "Launcher3",
                        "Launcher4", "Launcher5", "Launcher6"])
    }

    func testTheAlternateNamesAreTheBundleIcons() {
        XCTAssertEqual(LauncherIcon.allCases.map { $0.alternateName },
                       ["Icon1", "Icon2", "Icon3", "Icon4", "Icon5", "Icon6"])
    }

    func testTheIndicesFollowTheUpstreamOrder() {
        XCTAssertEqual(LauncherIcon.allCases.map { $0.index }, [1, 2, 3, 4, 5, 6])
    }

    func testAnEmptyValueMeansThePrimaryIcon() {
        XCTAssertNil(LauncherIcon.from(nil))
        XCTAssertNil(LauncherIcon.from(""))
        XCTAssertNil(LauncherIcon.from("Launcher9"))
    }

    func testAValueIsReadBack() {
        XCTAssertEqual(LauncherIcon.from("Launcher3"), .launcher3)
    }

    func testThePreferenceKeepsTheValue() {
        let settings = AppSettings(store: InMemorySettingsStore())
        XCTAssertNil(settings.launcherIcon)
        settings.launcherIcon = .launcher4
        XCTAssertEqual(settings.launcherIcon, .launcher4)
        XCTAssertEqual(settings.settingsStore.string(forKey: "launcherIcon"), "Launcher4")
        settings.launcherIcon = nil
        XCTAssertNil(settings.launcherIcon)
    }
}
