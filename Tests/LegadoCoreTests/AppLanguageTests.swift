//
//  AppLanguageTests.swift
//  LegadoCoreTests
//
//  The tests of the language of the interface and of the E-Ink palette.
//
//  Upstream:
//  - `base/AppContextWrapper.kt:77-84` — `getSetLocale`,
//  - `help/config/ThemeConfig.kt:244-251` — the E-Ink colours.
//

import XCTest
@testable import LegadoCore

final class AppLanguageTests: XCTestCase {

    // MARK: - The language

    /// The four values of the upstream preference.
    func testTheLanguages() {
        XCTAssertEqual(
            AppLanguage.allCases.map(\.rawValue),
            ["", "zh", "tw", "en"]
        )
    }

    /// The names of the picker.
    func testTheDisplayNames() {
        XCTAssertEqual(AppLanguage.system.displayName, "跟随系统")
        XCTAssertEqual(AppLanguage.simplified.displayName, "简体中文")
        XCTAssertEqual(AppLanguage.traditional.displayName, "繁體中文")
        XCTAssertEqual(AppLanguage.english.displayName, "English")
    }

    /// The locales of the upstream `getSetLocale` mapping.
    func testTheLocaleIdentifiers() {
        XCTAssertNil(AppLanguage.system.localeIdentifier)
        XCTAssertEqual(AppLanguage.simplified.localeIdentifier, "zh-Hans")
        XCTAssertEqual(AppLanguage.traditional.localeIdentifier, "zh-Hant")
        XCTAssertEqual(AppLanguage.english.localeIdentifier, "en")
    }

    /// An unknown value falls back to the system language — upstream
    /// `else -> getSystemLocale()`.
    func testAnUnknownValueFollowsTheSystem() {
        XCTAssertEqual(AppLanguage.from("fr"), .system)
        XCTAssertEqual(AppLanguage.from(""), .system)
    }

    /// The accessor of the settings stores the raw value.
    func testTheSettingsStoreTheRawValue() throws {
        let settings = AppSettings(store: InMemorySettingsStore())
        XCTAssertEqual(settings.appLanguage, .system)
        settings.appLanguage = .traditional
        XCTAssertEqual(settings.language, "tw")
        XCTAssertEqual(settings.appLanguage, .traditional)
        settings.appLanguage = .system
        XCTAssertEqual(settings.language, "")
    }

    // MARK: - The E-Ink palette

    /// The E-Ink palette is white with a black accent — upstream
    /// `ThemeConfig.applyTheme` (`ThemeConfig.kt:244-251`).
    func testTheEInkPalette() {
        XCTAssertEqual(AppTheme.eInk.primaryColor, "#FFFFFF")
        XCTAssertEqual(AppTheme.eInk.accentColor, "#000000")
        XCTAssertEqual(AppTheme.eInk.backgroundColor, "#FFFFFF")
        XCTAssertEqual(AppTheme.eInk.bottomBackground, "#FFFFFF")
        XCTAssertFalse(AppTheme.eInk.isNightTheme)
    }

    /// The E-Ink mode overrides the selected theme — upstream checks
    /// `AppConfig.isEInkMode` first.
    func testTheEInkModeOverridesTheSelectedTheme() {
        let manager = ThemeManager(mode: .eInk)
        let theme = manager.currentTheme(isSystemDark: false)
        XCTAssertEqual(theme.backgroundColor, "#FFFFFF")
        XCTAssertEqual(theme.accentColor, "#000000")
        // Even with the system in dark mode the E-Ink palette wins.
        XCTAssertEqual(manager.currentTheme(isSystemDark: true).accentColor, "#000000")
    }

    /// The other modes keep the selected theme.
    func testTheLightModeKeepsTheSelectedTheme() {
        let manager = ThemeManager(mode: .light)
        manager.select(index: 1)
        XCTAssertEqual(manager.currentTheme(isSystemDark: false).themeName, "典雅蓝")
    }
}
