import Foundation

//
//  BackupIgnoreConfig.swift
//  LegadoCore
//
//  The port of app/src/main/java/io/legado/app/help/storage/BackupConfig.kt.
//
//  The upstream keeps a map of the configuration groups that a restore must
//  skip. It is stored in the file `restoreIgnore.json`; the port keeps it in
//  the settings store under the same name.
//

/// The configuration groups that a restore can skip — upstream
/// `BackupConfig.ignoreKeys`.
public enum BackupIgnoreKey: String, CaseIterable, Identifiable, Sendable {
    /// The reading preferences.
    case readConfig = "readConfig"
    /// The theme mode (the light / dark switch).
    case themeMode = "themeMode"
    /// The theme colours and the background.
    case themeConfig = "themeConfig"
    /// The cover configuration.
    case coverConfig = "coverConfig"
    /// The layout of the bookshelf.
    case bookshelfLayout = "bookshelfLayout"
    /// The visibility of the RSS tab.
    case showRss = "showRss"
    /// The number of the search threads.
    case threadCount = "threadCount"
    /// The local books.
    case localBook = "localBook"

    public var id: String { rawValue }

    /// The title of the entry — upstream `BackupConfig.ignoreTitle`.
    public var title: String {
        switch self {
        case .readConfig: return "阅读设置"
        case .themeMode: return "主题模式"
        case .themeConfig: return "主题配置"
        case .coverConfig: return "封面配置"
        case .bookshelfLayout: return "书架布局"
        case .showRss: return "显示订阅"
        case .threadCount: return "线程数"
        case .localBook: return "本地书籍"
        }
    }
}

/// The groups that a restore skips — the port of the upstream `BackupConfig`.
public struct BackupIgnoreConfig: Equatable, Sendable {

    /// The key the configuration is stored under.
    public static let storageKey = "restoreIgnore"

    /// The flags of the groups.
    public private(set) var flags: [String: Bool]

    public init(flags: [String: Bool] = [:]) {
        self.flags = flags
    }

    // MARK: - The automatically ignored preferences

    /// The preferences that are never restored — upstream
    /// `BackupConfig.ignorePrefKeys`.
    public static let alwaysIgnoredKeys: [String] = [
        SettingsKey.defaultCover.rawValue,
        SettingsKey.defaultCoverDark.rawValue,
        SettingsKey.backupPath.rawValue,
        SettingsKey.defaultBookTreeUri.rawValue,
        SettingsKey.webDavDeviceName.rawValue,
        SettingsKey.launcherIcon.rawValue,
        SettingsKey.bitmapCacheSize.rawValue,
        SettingsKey.webServiceWakeLock.rawValue,
        SettingsKey.readAloudWakeLock.rawValue,
        SettingsKey.audioPlayWakeLock.rawValue
    ]

    /// The reading preferences — upstream `BackupConfig.readPrefKeys`.
    public static let readPrefKeys: [String] = [
        SettingsKey.readStyleSelect.rawValue,
        SettingsKey.comicStyleSelect.rawValue,
        SettingsKey.shareLayout.rawValue,
        SettingsKey.hideStatusBar.rawValue,
        SettingsKey.hideNavigationBar.rawValue,
        SettingsKey.autoReadSpeed.rawValue,
        SettingsKey.clickActionTL.rawValue,
        SettingsKey.clickActionTC.rawValue,
        SettingsKey.clickActionTR.rawValue,
        SettingsKey.clickActionML.rawValue,
        SettingsKey.clickActionMC.rawValue,
        SettingsKey.clickActionMR.rawValue,
        SettingsKey.clickActionBL.rawValue,
        SettingsKey.clickActionBC.rawValue,
        SettingsKey.clickActionBR.rawValue
    ]

    /// The theme preferences — upstream `BackupConfig.themePrefKeys`.
    public static let themePrefKeys: [String] = [
        SettingsKey.colorPrimary.rawValue,
        SettingsKey.colorAccent.rawValue,
        SettingsKey.colorBackground.rawValue,
        SettingsKey.colorBottomBackground.rawValue,
        SettingsKey.backgroundImage.rawValue,
        SettingsKey.backgroundImageBlurring.rawValue,
        SettingsKey.colorPrimaryNight.rawValue,
        SettingsKey.colorAccentNight.rawValue,
        SettingsKey.colorBackgroundNight.rawValue,
        SettingsKey.colorBottomBackgroundNight.rawValue,
        SettingsKey.backgroundImageNight.rawValue,
        SettingsKey.backgroundImageNightBlurring.rawValue
    ]

    /// The cover preferences — upstream `BackupConfig.coverPrefKeys`.
    public static let coverPrefKeys: [String] = [
        SettingsKey.useDefaultCover.rawValue,
        SettingsKey.loadCoverOnlyWifi.rawValue,
        SettingsKey.coverShowName.rawValue,
        SettingsKey.coverShowAuthor.rawValue,
        SettingsKey.coverShowNameN.rawValue,
        SettingsKey.coverShowAuthorN.rawValue
    ]

    // MARK: - The flags

    /// Whether the group is skipped — upstream `BackupConfig.ignoreReadConfig`
    /// and its siblings.
    public func isIgnored(_ key: BackupIgnoreKey) -> Bool {
        flags[key.rawValue] == true
    }

    /// Sets the flag of a group.
    public mutating func set(_ value: Bool, for key: BackupIgnoreKey) {
        flags[key.rawValue] = value
    }

    /// Whether the preference must be restored — upstream
    /// `BackupConfig.keyIsNotIgnore`.
    public func shouldRestore(_ key: String) -> Bool {
        if Self.alwaysIgnoredKeys.contains(key) { return false }
        if isIgnored(.readConfig), Self.readPrefKeys.contains(key) { return false }
        if isIgnored(.themeConfig), Self.themePrefKeys.contains(key) { return false }
        if isIgnored(.coverConfig), Self.coverPrefKeys.contains(key) { return false }
        if key == SettingsKey.themeMode.rawValue, isIgnored(.themeMode) { return false }
        if key == SettingsKey.bookshelfLayout.rawValue, isIgnored(.bookshelfLayout) { return false }
        if key == SettingsKey.showRss.rawValue, isIgnored(.showRss) { return false }
        if key == SettingsKey.threadCount.rawValue, isIgnored(.threadCount) { return false }
        return true
    }

    // MARK: - The persistence

    /// Reads the configuration — upstream `BackupConfig.ignoreConfig`.
    public static func load(from store: SettingsStore) -> BackupIgnoreConfig {
        guard let json = store.string(forKey: storageKey), !json.isEmpty else {
            return BackupIgnoreConfig()
        }
        guard let parsed = try? JSONValue.parse(json), let object = parsed.objectValue else {
            return BackupIgnoreConfig()
        }
        var flags: [String: Bool] = [:]
        for (key, value) in object {
            if let flag = value.boolValue {
                flags[key] = flag
            }
        }
        return BackupIgnoreConfig(flags: flags)
    }

    /// Writes the configuration — upstream `BackupConfig.saveIgnoreConfig`.
    public func save(to store: SettingsStore) {
        var object: [String: JSONValue] = [:]
        for (key, value) in flags {
            object[key] = .bool(value)
        }
        store.set(JSONValue.object(object).jsonString, forKey: Self.storageKey)
    }
}
