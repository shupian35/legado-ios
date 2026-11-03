//
//  ReaderConfigStore.swift
//  LegadoCore
//
//  Loads and saves the reader configuration — upstream `ReadBookConfig`.
//
//  The upstream keeps the reader preferences in two places:
//
//  * the *read* preferences of `app/src/main/res/xml/pref_config_read.xml`
//    live in the `SharedPreferences` and use the names of `PreferKey`
//    (`textFullJustify`, `textBottomJustify`, `useZhLayout`,
//    `doubleHorizontalPage`, …);
//  * the *style* of `ReadBookConfig.Config` is written into the JSON file
//    `readConfig.json` (the upstream `ReadBookConfig.save()`), which the port
//    persists through the same settings store — the names of the properties
//    of that data class are used as the key names, so that both spellings
//    stay recognisable.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/help/config/ReadBookConfig.kt
//  app/src/main/java/io/legado/app/constant/PreferKey.kt
//  app/src/main/res/xml/pref_config_read.xml
//

import Foundation

/// The preference keys of the reader configuration.
///
/// The keys are the upstream ones: the `PreferKey` names of the read
/// preferences and the property names of `ReadBookConfig.Config`.
public enum ReaderPreferenceKey: String, CaseIterable, Sendable {

    // MARK: - The upstream `PreferKey` names (the `SharedPreferences`).

    /// `PreferKey.textFullJustify` — the text is justified.
    case textFullJustify = "textFullJustify"
    /// `PreferKey.textBottomJustify` — the last line is justified too.
    case textBottomJustify = "textBottomJustify"
    /// `PreferKey.useZhLayout` — the Chinese layout rules are used.
    case useZhLayout = "useZhLayout"
    /// `PreferKey.doubleHorizontalPage` — the page shows two columns.
    case doubleHorizontalPage = "doubleHorizontalPage"
    /// `PreferKey.chineseConverterType` — the Chinese converter.
    case chineseConverterType = "chineseConverterType"
    /// `PreferKey.readStyleSelect` — the index of the selected read style.
    case readStyleSelect = "readStyleSelect"

    // MARK: - The property names of `ReadBookConfig.Config`.

    /// `Config.textSize` — the size of the body text.
    case textSize = "textSize"
    /// `Config.titleSize` — the size of the title.
    case titleSize = "titleSize"
    /// `Config.letterSpacing` — the extra letter spacing.
    case letterSpacing = "letterSpacing"
    /// `Config.lineSpacingExtra` — the extra line spacing.
    case lineSpacingExtra = "lineSpacingExtra"
    /// `Config.paragraphSpacing` — the space between two paragraphs.
    case paragraphSpacing = "paragraphSpacing"
    /// `Config.paragraphIndent` — the indent of the first line.
    case paragraphIndent = "paragraphIndent"
    /// `Config.textBold` — 0 normal, 1 bold, 2 light.
    case textBold = "textBold"
    /// `Config.underline` — the text is underlined.
    case underline = "underline"
    /// `Config.pageAnim` — the page turn animation.
    case pageAnim = "pageAnim"
    /// `Config.titleMode` — 0 left, 1 centre, 2 hidden.
    case titleMode = "titleMode"
    /// `Config.titleTopSpacing` — the space above the title.
    case titleTopSpacing = "titleTopSpacing"
    /// `Config.titleBottomSpacing` — the space below the title.
    case titleBottomSpacing = "titleBottomSpacing"
    /// `Config.paddingTop` — the top padding of the page.
    case paddingTop = "paddingTop"
    /// `Config.paddingBottom` — the bottom padding of the page.
    case paddingBottom = "paddingBottom"
    /// `Config.paddingLeft` — the left padding of the page.
    case paddingLeft = "paddingLeft"
    /// `Config.paddingRight` — the right padding of the page.
    case paddingRight = "paddingRight"
    /// `Config.headerMode` — the mode of the header (0 hidden, 1 shown).
    case headerMode = "headerMode"
    /// `Config.footerMode` — the mode of the footer (0 shown, 1 hidden).
    case footerMode = "footerMode"
    /// `Config.bgStr` — the background of the day.
    case bgStr = "bgStr"
    /// `Config.bgStrNight` — the background of the night.
    case bgStrNight = "bgStrNight"
    /// `Config.bgStrEInk` — the background of the e-ink mode.
    case bgStrEInk = "bgStrEInk"
    /// `Config.bgAlpha` — the opacity of the background, in percent.
    case bgAlpha = "bgAlpha"
    /// `Config.textColor` — the colour of the text of the day.
    case textColor = "textColor"
    /// `Config.textColorNight` — the colour of the text of the night.
    case textColorNight = "textColorNight"
    /// `Config.textColorEInk` — the colour of the text of the e-ink mode.
    case textColorEInk = "textColorEInk"
}

/// Loads and saves the reader configuration — upstream `ReadBookConfig`.
///
/// The upstream writes its style into the JSON file `readConfig.json`; the
/// port writes the same values through the settings store, so that the
/// preferences of the reader survive a restart of the app.
public final class ReaderConfigStore {

    private let store: SettingsStore

    /// Creates a store.
    ///
    /// - Parameter store: the settings store (upstream `SharedPreferences`).
    public init(store: SettingsStore) {
        self.store = store
    }

    /// Creates a store for the settings of the app.
    public convenience init(settings: AppSettings) {
        self.init(store: settings.settingsStore)
    }

    // MARK: - Loading

    /// Loads the reader configuration.
    ///
    /// The values that were never stored keep their default. Two of them
    /// differ from the defaults of the port: the upstream justifies the text
    /// (`ReadBookConfig.kt:233` and `:238` read the two preferences with the
    /// default `true`, and `pref_config_read.xml` declares the same), so the
    /// store does the same.
    public func load() -> ReaderConfig {
        var config = ReaderConfig()
        config.textFullJustify = boolean(.textFullJustify, default: true)
        config.textBottomJustify = boolean(.textBottomJustify, default: true)
        config.useZhLayout = boolean(.useZhLayout, default: config.useZhLayout)
        config.doublePage = boolean(.doubleHorizontalPage, default: config.doublePage)
        config.underline = boolean(.underline, default: config.underline)
        config.textBold = integer(.textBold, default: config.textBold)
        config.pageAnim = integer(.pageAnim, default: config.pageAnim)
        config.titleMode = integer(.titleMode, default: config.titleMode)
        config.styleIndex = integer(.readStyleSelect, default: config.styleIndex)
        config.textSize = number(.textSize, default: config.textSize)
        config.titleSize = number(.titleSize, default: config.titleSize)
        config.letterSpacing = number(.letterSpacing, default: config.letterSpacing)
        config.lineSpacingExtra = number(.lineSpacingExtra, default: config.lineSpacingExtra)
        config.paragraphSpacing = number(.paragraphSpacing, default: config.paragraphSpacing)
        config.titleTopSpacing = number(.titleTopSpacing, default: config.titleTopSpacing)
        config.titleBottomSpacing = number(.titleBottomSpacing, default: config.titleBottomSpacing)
        config.paddingTop = number(.paddingTop, default: config.paddingTop)
        config.paddingBottom = number(.paddingBottom, default: config.paddingBottom)
        config.paddingLeft = number(.paddingLeft, default: config.paddingLeft)
        config.paddingRight = number(.paddingRight, default: config.paddingRight)
        config.backgroundAlpha = integer(.bgAlpha, default: config.backgroundAlpha)
        config.backgroundColor = text(.bgStr, default: config.backgroundColor)
        config.backgroundColorNight = text(.bgStrNight, default: config.backgroundColorNight)
        config.backgroundColorEInk = text(.bgStrEInk, default: config.backgroundColorEInk)
        config.textColor = text(.textColor, default: config.textColor)
        config.textColorNight = text(.textColorNight, default: config.textColorNight)
        config.textColorEInk = text(.textColorEInk, default: config.textColorEInk)
        config.paragraphIndent = text(.paragraphIndent, default: config.paragraphIndent)
        config.showHeader = headerShown(.headerMode, default: config.showHeader)
        config.showFooter = footerShown(.footerMode, default: config.showFooter)
        // The upstream derives the centred title from the title mode
        // (`ReadBookConfig.kt:310`: `val isMiddleTitle get() = titleMode == 1`).
        config.isMiddleTitle = config.titleMode == 1
        return config
    }

    // MARK: - Saving

    /// Saves the reader configuration.
    public func save(_ config: ReaderConfig) {
        store.set(config.textFullJustify, forKey: ReaderPreferenceKey.textFullJustify.rawValue)
        store.set(config.textBottomJustify, forKey: ReaderPreferenceKey.textBottomJustify.rawValue)
        store.set(config.useZhLayout, forKey: ReaderPreferenceKey.useZhLayout.rawValue)
        store.set(config.doublePage, forKey: ReaderPreferenceKey.doubleHorizontalPage.rawValue)
        store.set(config.underline, forKey: ReaderPreferenceKey.underline.rawValue)
        store.set(config.textBold, forKey: ReaderPreferenceKey.textBold.rawValue)
        store.set(config.pageAnim, forKey: ReaderPreferenceKey.pageAnim.rawValue)
        store.set(config.titleMode, forKey: ReaderPreferenceKey.titleMode.rawValue)
        store.set(config.styleIndex, forKey: ReaderPreferenceKey.readStyleSelect.rawValue)
        store.set(config.backgroundAlpha, forKey: ReaderPreferenceKey.bgAlpha.rawValue)
        store.set(text(config.textSize), forKey: ReaderPreferenceKey.textSize.rawValue)
        store.set(text(config.titleSize), forKey: ReaderPreferenceKey.titleSize.rawValue)
        store.set(text(config.letterSpacing), forKey: ReaderPreferenceKey.letterSpacing.rawValue)
        store.set(text(config.lineSpacingExtra), forKey: ReaderPreferenceKey.lineSpacingExtra.rawValue)
        store.set(text(config.paragraphSpacing), forKey: ReaderPreferenceKey.paragraphSpacing.rawValue)
        store.set(text(config.titleTopSpacing), forKey: ReaderPreferenceKey.titleTopSpacing.rawValue)
        store.set(text(config.titleBottomSpacing), forKey: ReaderPreferenceKey.titleBottomSpacing.rawValue)
        store.set(text(config.paddingTop), forKey: ReaderPreferenceKey.paddingTop.rawValue)
        store.set(text(config.paddingBottom), forKey: ReaderPreferenceKey.paddingBottom.rawValue)
        store.set(text(config.paddingLeft), forKey: ReaderPreferenceKey.paddingLeft.rawValue)
        store.set(text(config.paddingRight), forKey: ReaderPreferenceKey.paddingRight.rawValue)
        store.set(config.backgroundColor, forKey: ReaderPreferenceKey.bgStr.rawValue)
        store.set(config.backgroundColorNight, forKey: ReaderPreferenceKey.bgStrNight.rawValue)
        store.set(config.backgroundColorEInk, forKey: ReaderPreferenceKey.bgStrEInk.rawValue)
        store.set(config.textColor, forKey: ReaderPreferenceKey.textColor.rawValue)
        store.set(config.textColorNight, forKey: ReaderPreferenceKey.textColorNight.rawValue)
        store.set(config.textColorEInk, forKey: ReaderPreferenceKey.textColorEInk.rawValue)
        store.set(config.paragraphIndent, forKey: ReaderPreferenceKey.paragraphIndent.rawValue)
        store.set(config.showHeader ? 1 : 2, forKey: ReaderPreferenceKey.headerMode.rawValue)
        store.set(config.showFooter ? 0 : 1, forKey: ReaderPreferenceKey.footerMode.rawValue)
    }

    /// Removes every reader preference — the reader falls back to the
    /// defaults of the upstream.
    public func reset() {
        for key in ReaderPreferenceKey.allCases {
            store.removeValue(forKey: key.rawValue)
        }
    }

    // MARK: - The helpers

    /// Whether a preference was ever stored.
    ///
    /// The reader uses it to know whether a value is the one of the user or
    /// the default of the background preset.
    public func hasValue(for key: ReaderPreferenceKey) -> Bool {
        store.string(forKey: key.rawValue) != nil
            || store.bool(forKey: key.rawValue) != nil
            || store.int(forKey: key.rawValue) != nil
    }

    /// The Chinese converter of the reader — upstream
    /// `PreferKey.chineseConverterType`.
    public var chineseConverterType: Int {
        get { store.int(forKey: ReaderPreferenceKey.chineseConverterType.rawValue) ?? 0 }
        set { store.set(newValue, forKey: ReaderPreferenceKey.chineseConverterType.rawValue) }
    }

    private func boolean(_ key: ReaderPreferenceKey, default fallback: Bool) -> Bool {
        store.bool(forKey: key.rawValue) ?? fallback
    }

    private func integer(_ key: ReaderPreferenceKey, default fallback: Int) -> Int {
        store.int(forKey: key.rawValue) ?? fallback
    }

    private func text(_ key: ReaderPreferenceKey, default fallback: String) -> String {
        store.string(forKey: key.rawValue) ?? fallback
    }

    /// The textual form of a floating point preference.
    ///
    /// The settings store has no floating point accessor, so the value is
    /// stored as its textual form — the way the advanced settings screen
    /// writes a preference.
    private func text(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(value)
    }

    /// A floating point preference.
    ///
    /// The settings store has no floating point accessor, so the value is
    /// stored as its textual form — the way the advanced settings screen
    /// writes a preference.
    private func number(_ key: ReaderPreferenceKey, default fallback: Double) -> Double {
        if let raw = store.string(forKey: key.rawValue) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Double(trimmed) { return value }
        }
        if let value = store.int(forKey: key.rawValue) { return Double(value) }
        return fallback
    }

    /// The header of the reader — upstream `Config.headerMode`.
    ///
    /// The upstream shows the header with the mode 1 and hides it with the
    /// mode 2 (`PageView.kt:164`).
    private func headerShown(_ key: ReaderPreferenceKey, default fallback: Bool) -> Bool {
        guard let mode = store.int(forKey: key.rawValue) else { return fallback }
        return mode != 2
    }

    /// The footer of the reader — upstream `Config.footerMode`.
    ///
    /// The upstream hides the footer with the mode 1 (`PageView.kt:169`).
    private func footerShown(_ key: ReaderPreferenceKey, default fallback: Bool) -> Bool {
        guard let mode = store.int(forKey: key.rawValue) else { return fallback }
        return mode != 1
    }
}
