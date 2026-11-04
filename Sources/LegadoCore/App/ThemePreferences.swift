//
//  ThemePreferences.swift
//  LegadoCore
//
//  The colour and the background image preferences of the theme — upstream
//  `res/xml/pref_config_theme.xml` and `help/config/ThemeConfig.kt`.
//
//  Upstream the ACTIVE colours of the shell live in eight preferences:
//
//    * `colorPrimary` / `colorAccent` / `colorBackground` /
//      `colorBottomBackground` — the day theme;
//    * `colorPrimaryNight` / `colorAccentNight` / `colorBackgroundNight` /
//      `colorBottomBackgroundNight` — the night theme.
//
//  The list of the saved themes (`themeConfig.json`) holds the same four
//  colours; `ThemeConfig.applyConfig` copies the colours of the selected
//  theme into the preferences and `ThemeConfig.saveDayTheme` /
//  `saveNightTheme` copy the current preferences into a new entry of the list.
//
//  The background image of the shell lives in `backgroundImage` (day) and
//  `backgroundImageNight` (night) — the path of a file — and the blur radius
//  in `backgroundImageBlurring` / `backgroundImageNightBlurring`.
//
//

import Foundation

// MARK: - The colours

/// The four colours of a theme — upstream `ThemeConfig.Config`.
public struct ThemeColors: Equatable, Sendable {

    /// The primary colour (`#RRGGBB`).
    public var primary: String
    /// The accent colour (`#RRGGBB`).
    public var accent: String
    /// The background colour (`#RRGGBB`).
    public var background: String
    /// The colour of the bottom bar (`#RRGGBB`).
    public var bottomBackground: String

    public init(
        primary: String,
        accent: String,
        background: String,
        bottomBackground: String
    ) {
        self.primary = primary
        self.accent = accent
        self.background = background
        self.bottomBackground = bottomBackground
    }

    /// The colours of a theme.
    public init(theme: AppTheme) {
        self.init(
            primary: theme.primaryColor,
            accent: theme.accentColor,
            background: theme.backgroundColor,
            bottomBackground: theme.bottomBackground
        )
    }

    /// The theme of the colours.
    public var theme: AppTheme {
        AppTheme(
            themeName: "",
            isNightTheme: false,
            primaryColor: primary,
            accentColor: accent,
            backgroundColor: background,
            bottomBackground: bottomBackground
        )
    }

    /// The day defaults — upstream `R.color.md_brown_500` / `md_red_600` /
    /// `md_grey_100` / `md_grey_200`.
    public static let dayDefault = ThemeColors(
        primary: "#795548",
        accent: "#E53935",
        background: "#F5F5F5",
        bottomBackground: "#EEEEEE"
    )

    /// The night defaults — upstream `R.color.md_blue_grey_600` /
    /// `md_deep_orange_800` / `md_grey_900` / `md_grey_850`.
    public static let nightDefault = ThemeColors(
        primary: "#455A64",
        accent: "#D84315",
        background: "#212121",
        bottomBackground: "#263238"
    )

    /// The colour as an integer — upstream `Color.parseColor` /
    /// `putPrefInt` store the colours as integers.
    public static func intValue(_ hex: String) -> Int? {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 8 {
            // `#AARRGGBB` — the alpha is dropped.
            value = String(value.dropFirst(2))
        }
        guard value.count == 6, value.allSatisfy({ $0.isHexDigit }) else { return nil }
        return Int(value, radix: 16)
    }

    /// The colour as a `#RRGGBB` string — upstream `Int.hexString`.
    public static func hexValue(_ value: Int) -> String {
        String(format: "#%06X", value & 0xFFFFFF)
    }
}

// MARK: - The preferences

public extension AppSettings {

    /// The colours of the day theme — upstream `PreferKey.cPrimary` /
    /// `cAccent` / `cBackground` / `cBBackground`.
    var dayThemeColors: ThemeColors {
        ThemeColors(
            primary: ThemeColors.hexValue(int(.colorPrimary, default: ThemeColors.intValue(ThemeColors.dayDefault.primary) ?? 0)),
            accent: ThemeColors.hexValue(int(.colorAccent, default: ThemeColors.intValue(ThemeColors.dayDefault.accent) ?? 0)),
            background: ThemeColors.hexValue(int(.colorBackground, default: ThemeColors.intValue(ThemeColors.dayDefault.background) ?? 0)),
            bottomBackground: ThemeColors.hexValue(int(.colorBottomBackground, default: ThemeColors.intValue(ThemeColors.dayDefault.bottomBackground) ?? 0))
        )
    }

    /// The colours of the night theme — upstream `PreferKey.cNPrimary` /
    /// `cNAccent` / `cNBackground` / `cNBBackground`.
    var nightThemeColors: ThemeColors {
        ThemeColors(
            primary: ThemeColors.hexValue(int(.colorPrimaryNight, default: ThemeColors.intValue(ThemeColors.nightDefault.primary) ?? 0)),
            accent: ThemeColors.hexValue(int(.colorAccentNight, default: ThemeColors.intValue(ThemeColors.nightDefault.accent) ?? 0)),
            background: ThemeColors.hexValue(int(.colorBackgroundNight, default: ThemeColors.intValue(ThemeColors.nightDefault.background) ?? 0)),
            bottomBackground: ThemeColors.hexValue(int(.colorBottomBackgroundNight, default: ThemeColors.intValue(ThemeColors.nightDefault.bottomBackground) ?? 0))
        )
    }

    /// Writes the colours of the day theme.
    func setDayThemeColors(_ colors: ThemeColors) {
        set(ThemeColors.intValue(colors.primary) ?? 0, for: .colorPrimary)
        set(ThemeColors.intValue(colors.accent) ?? 0, for: .colorAccent)
        set(ThemeColors.intValue(colors.background) ?? 0, for: .colorBackground)
        set(ThemeColors.intValue(colors.bottomBackground) ?? 0, for: .colorBottomBackground)
    }

    /// Writes the colours of the night theme.
    func setNightThemeColors(_ colors: ThemeColors) {
        set(ThemeColors.intValue(colors.primary) ?? 0, for: .colorPrimaryNight)
        set(ThemeColors.intValue(colors.accent) ?? 0, for: .colorAccentNight)
        set(ThemeColors.intValue(colors.background) ?? 0, for: .colorBackgroundNight)
        set(ThemeColors.intValue(colors.bottomBackground) ?? 0, for: .colorBottomBackgroundNight)
    }

    /// The colours of the current mode.
    func themeColors(isNight: Bool) -> ThemeColors {
        isNight ? nightThemeColors : dayThemeColors
    }

    /// Writes the colours of a theme — upstream `ThemeConfig.applyConfig`
    /// (the colours go into the day or the night preferences).
    func applyThemeColors(_ colors: ThemeColors, isNight: Bool) {
        if isNight {
            setNightThemeColors(colors)
        } else {
            setDayThemeColors(colors)
        }
    }

    /// The path of the background image of the day theme — upstream
    /// `PreferKey.bgImage`.
    var dayBackgroundImagePath: String? {
        get { string(.backgroundImage) }
        set { set(newValue, for: .backgroundImage) }
    }

    /// The path of the background image of the night theme — upstream
    /// `PreferKey.bgImageN`.
    var nightBackgroundImagePath: String? {
        get { string(.backgroundImageNight) }
        set { set(newValue, for: .backgroundImageNight) }
    }

    /// The blur radius of the day background image — upstream
    /// `PreferKey.bgImageBlurring`.
    var dayBackgroundImageBlurring: Int {
        get { int(.backgroundImageBlurring, default: 0) }
        set { set(newValue, for: .backgroundImageBlurring) }
    }

    /// The blur radius of the night background image — upstream
    /// `PreferKey.bgImageNBlurring`.
    var nightBackgroundImageBlurring: Int {
        get { int(.backgroundImageNightBlurring, default: 0) }
        set { set(newValue, for: .backgroundImageNightBlurring) }
    }

    /// The background image of the current mode — upstream
    /// `ThemeConfig.getBgImage` (the path and the blur radius).
    func backgroundImage(isNight: Bool) -> (path: String, blurring: Int)? {
        let path = (isNight ? nightBackgroundImagePath : dayBackgroundImagePath) ?? ""
        guard !path.isEmpty else { return nil }
        let blurring = isNight ? nightBackgroundImageBlurring : dayBackgroundImageBlurring
        return (path, blurring)
    }
}
