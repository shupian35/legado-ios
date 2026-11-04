//
//  ThemePreferencesTests.swift
//  LegadoCoreTests
//
//  The colour and the background image preferences of the theme — upstream
//  `res/xml/pref_config_theme.xml` and `help/config/ThemeConfig.kt`.
//

import XCTest
@testable import LegadoCore

final class ThemePreferencesTests: XCTestCase {

    // MARK: - The colours

    func testTheColourIsConvertedToAnInteger() {
        XCTAssertEqual(ThemeColors.intValue("#795548"), 0x795548)
        XCTAssertEqual(ThemeColors.intValue("795548"), 0x795548)
        XCTAssertEqual(ThemeColors.intValue("#FF795548"), 0x795548)
        XCTAssertNil(ThemeColors.intValue("nonsense"))
        XCTAssertNil(ThemeColors.intValue("#12345"))
    }

    func testTheColourIsConvertedToAHexString() {
        XCTAssertEqual(ThemeColors.hexValue(0x795548), "#795548")
        XCTAssertEqual(ThemeColors.hexValue(0x00795548), "#795548")
    }

    func testTheDefaultsAreTheUpstreamColours() {
        XCTAssertEqual(ThemeColors.dayDefault.primary, "#795548")
        XCTAssertEqual(ThemeColors.dayDefault.accent, "#E53935")
        XCTAssertEqual(ThemeColors.dayDefault.background, "#F5F5F5")
        XCTAssertEqual(ThemeColors.dayDefault.bottomBackground, "#EEEEEE")
        XCTAssertEqual(ThemeColors.nightDefault.primary, "#455A64")
        XCTAssertEqual(ThemeColors.nightDefault.accent, "#D84315")
        XCTAssertEqual(ThemeColors.nightDefault.background, "#212121")
        XCTAssertEqual(ThemeColors.nightDefault.bottomBackground, "#263238")
    }

    func testTheColoursOfAThemeAreRead() {
        let theme = AppTheme(
            themeName: "测试",
            isNightTheme: false,
            primaryColor: "#123456",
            accentColor: "#654321",
            backgroundColor: "#ABCDEF",
            bottomBackground: "#FEDCBA"
        )
        let colors = ThemeColors(theme: theme)
        XCTAssertEqual(colors.primary, "#123456")
        XCTAssertEqual(colors.accent, "#654321")
        XCTAssertEqual(colors.background, "#ABCDEF")
        XCTAssertEqual(colors.bottomBackground, "#FEDCBA")
    }

    // MARK: - The preferences

    func testTheDayColoursAreStoredInThePreferences() {
        let settings = AppSettings(store: InMemorySettingsStore())
        let colors = ThemeColors(
            primary: "#111111",
            accent: "#222222",
            background: "#333333",
            bottomBackground: "#444444"
        )
        settings.setDayThemeColors(colors)
        XCTAssertEqual(settings.dayThemeColors, colors)
        // The night colours are untouched.
        XCTAssertEqual(settings.nightThemeColors, ThemeColors.nightDefault)
    }

    func testTheNightColoursAreStoredInThePreferences() {
        let settings = AppSettings(store: InMemorySettingsStore())
        let colors = ThemeColors(
            primary: "#111111",
            accent: "#222222",
            background: "#333333",
            bottomBackground: "#444444"
        )
        settings.setNightThemeColors(colors)
        XCTAssertEqual(settings.nightThemeColors, colors)
        XCTAssertEqual(settings.dayThemeColors, ThemeColors.dayDefault)
    }

    func testTheColoursOfTheCurrentModeAreRead() {
        let settings = AppSettings(store: InMemorySettingsStore())
        let day = ThemeColors(
            primary: "#111111",
            accent: "#222222",
            background: "#333333",
            bottomBackground: "#444444"
        )
        let night = ThemeColors(
            primary: "#555555",
            accent: "#666666",
            background: "#777777",
            bottomBackground: "#888888"
        )
        settings.setDayThemeColors(day)
        settings.setNightThemeColors(night)
        XCTAssertEqual(settings.themeColors(isNight: false), day)
        XCTAssertEqual(settings.themeColors(isNight: true), night)
    }

    func testApplyingAThemeWritesItsColours() {
        let settings = AppSettings(store: InMemorySettingsStore())
        let theme = AppTheme(
            themeName: "夜色",
            isNightTheme: true,
            primaryColor: "#123456",
            accentColor: "#654321",
            backgroundColor: "#ABCDEF",
            bottomBackground: "#FEDCBA"
        )
        ThemeManager(themes: [theme], selectedIndex: 0).applyConfig(theme, to: settings)
        XCTAssertEqual(settings.nightThemeColors, ThemeColors(theme: theme))
        XCTAssertEqual(settings.dayThemeColors, ThemeColors.dayDefault)
    }

    // MARK: - The background image

    func testTheBackgroundImageIsStoredInThePreferences() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.dayBackgroundImagePath = "/tmp/bg.png"
        settings.dayBackgroundImageBlurring = 12
        XCTAssertEqual(settings.dayBackgroundImagePath, "/tmp/bg.png")
        XCTAssertEqual(settings.dayBackgroundImageBlurring, 12)
        let background = settings.backgroundImage(isNight: false)
        XCTAssertEqual(background?.path, "/tmp/bg.png")
        XCTAssertEqual(background?.blurring, 12)
    }

    func testThereIsNoBackgroundImageByDefault() {
        let settings = AppSettings(store: InMemorySettingsStore())
        XCTAssertNil(settings.backgroundImage(isNight: false))
        XCTAssertNil(settings.backgroundImage(isNight: true))
    }

    func testTheNightBackgroundImageIsSeparate() {
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.dayBackgroundImagePath = "/tmp/day.png"
        settings.nightBackgroundImagePath = "/tmp/night.png"
        XCTAssertEqual(settings.backgroundImage(isNight: false)?.path, "/tmp/day.png")
        XCTAssertEqual(settings.backgroundImage(isNight: true)?.path, "/tmp/night.png")
    }
}
