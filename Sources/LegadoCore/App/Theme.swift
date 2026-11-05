//
//  Theme.swift
//  LegadoCore
//
//  The port of app/src/main/java/io/legado/app/help/config/ThemeConfig.kt.
//
//  Upstream the app theme is a list of `Config` records (the colours of the
//  shell) that is stored in `themeConfig.json`; the day/night mode comes from
//  the `themeMode` preference ("0" follow the system, "1" light, "2" dark,
//  "3" E-Ink).
//
//  The port keeps the same model: the themes are `AppTheme` values, the list
//  is persisted as JSON and the effective theme is derived from the mode and
//  the system appearance.
//

import Foundation

// MARK: - The theme

/// The colours of the application shell — upstream `ThemeConfig.Config`.
public struct AppTheme: Equatable, Codable, Sendable {

    /// The name of the theme.
    public var themeName: String
    /// Whether the theme is a night theme.
    public var isNightTheme: Bool
    /// The primary colour (`#RRGGBB`).
    public var primaryColor: String
    /// The accent colour (`#RRGGBB`).
    public var accentColor: String
    /// The background colour (`#RRGGBB`).
    public var backgroundColor: String
    /// The colour of the bottom bar (`#RRGGBB`).
    public var bottomBackground: String

    public init(
        themeName: String,
        isNightTheme: Bool,
        primaryColor: String,
        accentColor: String,
        backgroundColor: String,
        bottomBackground: String
    ) {
        self.themeName = themeName
        self.isNightTheme = isNightTheme
        self.primaryColor = primaryColor
        self.accentColor = accentColor
        self.backgroundColor = backgroundColor
        self.bottomBackground = bottomBackground
    }

    /// The themes upstream ships in `assets/defaultData/themeConfig.json`.
    public static let defaults: [AppTheme] = [
        AppTheme(
            themeName: "默认",
            isNightTheme: false,
            primaryColor: "#795548",
            accentColor: "#E53935",
            backgroundColor: "#F5F5F5",
            bottomBackground: "#EEEEEE"
        ),
        AppTheme(
            themeName: "典雅蓝",
            isNightTheme: false,
            primaryColor: "#03A9F4",
            accentColor: "#AD1457",
            backgroundColor: "#F5F5F5",
            bottomBackground: "#EEEEEE"
        ),
        AppTheme(
            themeName: "黑白",
            isNightTheme: true,
            primaryColor: "#303030",
            accentColor: "#E0E0E0",
            backgroundColor: "#424242",
            bottomBackground: "#424242"
        ),
        AppTheme(
            themeName: "A屏黑",
            isNightTheme: true,
            primaryColor: "#000000",
            accentColor: "#FFFFFF",
            backgroundColor: "#000000",
            bottomBackground: "#000000"
        )
    ]
}

// MARK: - The theme mode

/// The theme mode — upstream `PreferKey.themeMode`.
public enum ThemeMode: Int, CaseIterable, Sendable {
    /// Follow the system appearance.
    case followSystem = 0
    /// Always light.
    case light = 1
    /// Always dark.
    case dark = 2
    /// E-Ink (a black and white theme).
    case eInk = 3

    /// The name shown in the settings.
    public var name: String {
        switch self {
        case .followSystem: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        case .eInk: return "墨水屏"
        }
    }
}

/// The effective theme — upstream `ThemeConfig.getTheme()`.
public enum EffectiveTheme: String, Sendable {
    case light
    case dark
    case eInk
}

// MARK: - The manager

/// The theme manager — upstream `ThemeConfig`.
public final class ThemeManager {

    /// The name of the file the themes are stored in.
    public static let configFileName = "themeConfig.json"

    /// The themes.
    public private(set) var themes: [AppTheme]
    /// The index of the selected theme.
    public private(set) var selectedIndex: Int
    /// The theme mode.
    public var mode: ThemeMode {
        didSet { onModeChanged?(mode) }
    }
    /// Called when the mode changes (the shell re-renders).
    public var onModeChanged: ((ThemeMode) -> Void)?

    private let fileURL: URL?

    /// Creates a manager.
    ///
    /// - Parameters:
    ///   - themes: the themes; the upstream defaults are used when `nil`.
    ///   - selectedIndex: the index of the selected theme.
    ///   - mode: the theme mode.
    ///   - fileURL: the file the themes are persisted in; without it the
    ///     themes are not persisted (the tests use that).
    public init(
        themes: [AppTheme]? = nil,
        selectedIndex: Int = 0,
        mode: ThemeMode = .followSystem,
        fileURL: URL? = nil
    ) {
        self.themes = themes ?? AppTheme.defaults
        self.selectedIndex = min(max(0, selectedIndex), max(0, self.themes.count - 1))
        self.mode = mode
        self.fileURL = fileURL
        if let fileURL, let loaded = ThemeManager.loadThemes(from: fileURL), !loaded.isEmpty {
            self.themes = loaded
        }
    }

    /// The file the themes are persisted in — upstream
    /// `ThemeConfig.configFilePath`. It is `nil` when the themes are not
    /// persisted at all (the tests use that).
    public var configFileURL: URL? { fileURL }

    /// The effective theme — upstream `getTheme()`.
    ///
    /// - Parameter isSystemDark: whether the system is in dark mode.
    public func effectiveTheme(isSystemDark: Bool) -> EffectiveTheme {        switch mode {
        case .eInk: return .eInk
        case .dark: return .dark
        case .light: return .light
        case .followSystem: return isSystemDark ? .dark : .light
        }
    }

    /// The theme of the current mode — upstream `applyTheme()`.
    ///
    /// The night themes win over the day ones when the system is dark; the
    /// selected theme is used when the list has more than one entry.
    public func currentTheme(isSystemDark: Bool) -> AppTheme {
        let dark = effectiveTheme(isSystemDark: isSystemDark) != .light
        if themes.count > 1 {
            return themes[selectedIndex]
        }
        let night = themes.first { $0.isNightTheme }
        let day = themes.first { !$0.isNightTheme }
        if dark {
            return night ?? themes[0]
        }
        return day ?? themes[0]
    }

    /// Selects another theme.
    public func select(index: Int) {
        guard themes.indices.contains(index) else { return }
        selectedIndex = index
        save()
    }

    /// Adds a theme (upstream `addConfig`).
    @discardableResult
    public func add(_ theme: AppTheme) -> Bool {
        guard !theme.themeName.isEmpty else { return false }
        themes.append(theme)
        save()
        return true
    }

    /// Saves the current colours under a new name — upstream
    /// `ThemeConfig.saveDayTheme` / `saveNightTheme`.
    ///
    /// The upstream reads the colours out of the preferences; the port keeps
    /// them in the theme list, so the current theme of the requested mode is
    /// copied into a new entry. When the caller passes the colours of the
    /// preferences (the active theme), they win.
    ///
    /// - Parameters:
    ///   - name: the name of the new theme.
    ///   - isNightTheme: whether the night colours are saved.
    ///   - colors: the colours of the active theme.
    @discardableResult
    public func saveCurrentTheme(
        name: String,
        isNightTheme: Bool,
        colors: ThemeColors? = nil
    ) -> Bool {
        // The upstream keeps the day colours and the night colours in two
        // separate sets of preferences; the port keeps them in the two
        // entries of the theme list.
        let current = colors.map { ThemeColors(theme: $0.theme) }
            ?? themes.first { $0.isNightTheme == isNightTheme }.map { ThemeColors(theme: $0) }
            ?? ThemeColors(theme: currentTheme(isSystemDark: isNightTheme))
        let theme = AppTheme(
            themeName: name,
            isNightTheme: isNightTheme,
            primaryColor: current.primary,
            accentColor: current.accent,
            backgroundColor: current.background,
            bottomBackground: current.bottomBackground
        )
        return add(theme)
    }

    /// Copies the colours of a theme into the preferences — upstream
    /// `ThemeConfig.applyConfig` (L169-191).
    ///
    /// The colours go into the day or the night preferences, depending on
    /// `theme.isNightTheme`.
    public func applyConfig(_ theme: AppTheme, to settings: AppSettings) {
        settings.applyThemeColors(ThemeColors(theme: theme), isNight: theme.isNightTheme)
    }

    /// Deletes a theme (upstream `delConfig`).
    public func delete(index: Int) {
        guard themes.indices.contains(index) else { return }
        themes.remove(at: index)
        selectedIndex = min(selectedIndex, max(0, themes.count - 1))
        save()
    }

    /// Updates a theme (upstream `upConfig`).
    public func update(index: Int, theme: AppTheme) {
        guard themes.indices.contains(index) else { return }
        themes[index] = theme
        save()
    }

    /// The theme as the upstream JSON document (upstream
    /// `ThemeConfig.toJson`).
    public static func exportJSON(_ theme: AppTheme) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(theme) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Reads a theme from the upstream JSON document.
    public static func importJSON(_ json: String) -> AppTheme? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(AppTheme.self, from: data)
    }

    /// Saves the themes.
    public func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(themes) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: fileURL)
    }

    /// Loads the themes from a file.
    public static func loadThemes(from fileURL: URL) -> [AppTheme]? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode([AppTheme].self, from: data)
    }

    /// Reloads the themes from the file — upstream `ThemeConfig.upConfig()`.
    ///
    /// A restore writes the theme file and then asks the manager to pick the
    /// themes up again.
    @discardableResult
    public func reload() -> Bool {
        guard let fileURL, let loaded = ThemeManager.loadThemes(from: fileURL), !loaded.isEmpty else {
            return false
        }
        themes = loaded
        selectedIndex = min(max(0, selectedIndex), max(0, themes.count - 1))
        return true
    }
}
