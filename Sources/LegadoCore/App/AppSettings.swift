//
//  AppSettings.swift
//  LegadoCore
//
//  Port of the upstream preference layer:
//
//  · `constant/PreferKey.kt`     — the preference keys.
//  · `help/config/AppConfig.kt`  — the typed accessors and their defaults.
//  · `help/SharedPreferences.kt` — the storage.
//
//  The settings live in `LegadoCore` so that they can be unit tested on
//  Linux; the SwiftUI shell only binds them to `UserDefaults`.
//
//

import Foundation

/// The upstream preference keys — `constant/PreferKey.kt`.
///
/// Only the keys the port actually implements are listed; upstream has ~200
/// more. The string values are the upstream ones, which are **not** always
/// the same as the Kotlin property name (`backupPath` is stored as
/// `"backupUri"`, `ttsEngine` as `"appTtsEngine"`, …) so that a preference
/// file written by the Android app can be read by the port.
public enum SettingsKey: String, CaseIterable, Sendable {
    // Appearance
    case language = "language"
    case fontScale = "fontScale"
    case themeMode = "themeMode"
    case keepLight = "keep_light"
    case transparentStatusBar = "transparentStatusBar"
    case screenOrientation = "screenOrientation"
    case defaultCover = "defaultCover"
    case defaultCoverDark = "defaultCoverDark"
    case launcherIcon = "launcherIcon"

    // Network
    case userAgent = "userAgent"
    case cronet = "Cronet"
    case threadCount = "threadCount"
    case preDownloadNum = "preDownloadNum"
    case bitmapCacheSize = "bitmapCacheSize"
    case imageRetainNum = "imageRetainNum"
    case antiAlias = "antiAlias"

    // Bookshelf
    case showUnread = "showUnread"
    case bookGroupStyle = "bookGroupStyle"
    case useDefaultCover = "useDefaultCover"
    case loadCoverOnlyWifi = "loadCoverOnlyWifi"
    case coverShowName = "coverShowName"
    case coverShowAuthor = "coverShowAuthor"
    case bookshelfLayout = "bookshelfLayout"
    case bookshelfSort = "bookshelfSort"
    case showDiscovery = "showDiscovery"
    case showRss = "showRss"
    case enableReview = "enableReview"
    case autoRefresh = "auto_refresh"
    case showLastUpdateTime = "showLastUpdateTime"
    case showWaitUpCount = "showWaitUpCount"
    case showBookshelfFastScroller = "showBookshelfFastScroller"
    case defaultHomePage = "defaultHomePage"
    case defaultToRead = "defaultToRead"

    // Click actions — the region of the screen the reader reacts to.
    case clickActionTL = "clickActionTopLeft"
    case clickActionTC = "clickActionTopCenter"
    case clickActionTR = "clickActionTopRight"
    case clickActionML = "clickActionMiddleLeft"
    case clickActionMC = "clickActionMiddleCenter"
    case clickActionMR = "clickActionMiddleRight"
    case clickActionBL = "clickActionBottomLeft"
    case clickActionBC = "clickActionBottomCenter"
    case clickActionBR = "clickActionBottomRight"

    // Reading
    case hideStatusBar = "hideStatusBar"
    case hideNavigationBar = "hideNavigationBar"
    case systemTypefaces = "system_typefaces"
    case textSelectAble = "selectText"
    case textFullJustify = "textFullJustify"
    case readBodyToLh = "readBodyToLh"
    case readStyleSelect = "readStyleSelect"
    case shareLayout = "shareLayout"
    case autoReadSpeed = "autoReadSpeed"
    case brightness = "brightness"
    case nightBrightness = "nightBrightness"
    case showBrightnessView = "showBrightnessView"
    case useZhLayout = "useZhLayout"
    case doublePageHorizontal = "doubleHorizontalPage"
    case optimizeRender = "optimizeRender"
    case fontFolder = "fontFolder"
    case keyPageOnLongPress = "keyPageOnLongPress"
    case volumeKeyPage = "volumeKeyPage"
    case volumeKeyPageOnPlay = "volumeKeyPageOnPlay"
    case mouseWheelPage = "mouseWheelPage"
    case previewImageByClick = "previewImageByClick"
    case paddingDisplayCutouts = "paddingDisplayCutouts"
    case expandTextMenu = "expandTextMenu"
    case readUrlOpenInBrowser = "readUrlInBrowser"

    // Search / sources
    case precisionSearch = "precisionSearch"
    case checkSource = "checkSource"
    case uploadRule = "uploadRule"
    case sourceEditMaxLine = "sourceEditMaxLine"

    // Replace rules and Chinese conversion
    case replaceEnableDefault = "replaceEnableDefault"
    case chineseConverterType = "chineseConverterType"

    // Import / export
    case bookExportFileName = "bookExportFileName"
    case bookImportFileName = "bookImportFileName"
    case exportCharset = "exportCharset"
    case exportType = "exportType"
    case exportUseReplace = "exportUseReplace"
    case exportNoChapterName = "exportNoChapterName"
    case exportPictureFile = "exportPictureFile"
    case enableCustomExport = "enableCustomExport"
    case exportToWebDav = "webDavCacheBackup"
    case parallelExportBook = "parallelExportBook"
    case importKeepName = "importKeepName"
    case importKeepGroup = "importKeepGroup"
    case importKeepEnable = "importKeepEnable"
    case localBookImportSort = "localBookImportSort"

    // Backup / sync
    case backupPath = "backupUri"
    case restoreIgnore = "restoreIgnore"
    case onlyLatestBackup = "onlyLatestBackup"
    case autoCheckNewBackup = "autoCheckNewBackup"
    case shrinkDatabase = "shrinkDatabase"
    case webDavUrl = "web_dav_url"
    case webDavAccount = "web_dav_account"
    case webDavPassword = "web_dav_password"
    case webDavDir = "webDavDir"
    case webDavDeviceName = "webDavDeviceName"
    case syncBookProgress = "syncBookProgress"
    case syncBookProgressPlus = "syncBookProgressPlus"
    case batchChangeSourceDelay = "batchChangeSourceDelay"
    case autoChangeSource = "autoChangeSource"

    // Web service (the local HTTP API)
    case webService = "webService"
    case webPort = "webPort"
    case remoteServerId = "remoteServerId"
    case webServiceWakeLock = "webServiceWakeLock"

    // Read aloud
    case ttsEngine = "appTtsEngine"
    case ttsFollowSys = "ttsFollowSys"
    case ttsSpeechRate = "ttsSpeechRate"
    case readAloudByPage = "readAloudByPage"
    case streamReadAloudAudio = "streamReadAloudAudio"
    case pauseReadAloudWhilePhoneCalls = "pauseReadAloudWhilePhoneCalls"
    case readAloudByMediaButton = "readAloudByMediaButton"

    // Manga (the image reader)
    case showMangaUi = "showMangaUi"
    case hideMangaTitle = "hideMangaTitle"
    case mangaColorFilter = "mangaColorFilter"
    case enableMangaEInk = "enableMangaEInk"
    case mangaEInkThreshold = "mangaEInkThreshold"
    case enableMangaGray = "enableMangaGray"
    case disableMangaScale = "disableMangaScale"
    case disableMangaPageAnim = "disableMangaPageAnim"
    case enableMangaHorizontalScroll = "enableMangaHorizontalScroll"
    case mangaPreDownloadNum = "mangaPreDownloadNum"
    case mangaAutoPageSpeed = "mangaAutoPageSpeed"
    case mangaFooterConfig = "mangaFooterConfig"

    // Miscellaneous
    case recordLog = "recordLog"
    case cleanCache = "cleanCache"
    case saveTabPosition = "saveTabPosition"
    case enableReadRecord = "enableReadRecord"
    case autoClearExpired = "autoClearExpired"
    case tocUiUseReplace = "tocUiUseReplace"
    case tocCountWords = "tocCountWords"
    case clearWebViewData = "clearWebViewData"
    case pageTouchSlop = "pageTouchSlop"
    case showAddToShelfAlert = "showAddToShelfAlert"
    case prevKeys = "prevKeyCodes"
    case nextKeys = "nextKeyCodes"

    // The upstream preferences that the port reads from the advanced settings
    // screen (they have no dedicated switch on the curated screen yet).
    case audioPlayWakeLock = "audioPlayWakeLock"
    case readAloudWakeLock = "readAloudWakeLock"
    case ignoreAudioFocus = "ignoreAudioFocus"
    case ttsTimer = "ttsTimer"
    case contentReadAloudMod = "contentReadAloudMod"
    case backgroundImage = "backgroundImage"
    case backgroundImageNight = "backgroundImageNight"
    case backgroundImageBlurring = "backgroundImageBlurring"
    case backgroundImageNightBlurring = "backgroundImageNightBlurring"
    case barElevation = "barElevation"
    case brightnessVwPos = "brightnessVwPos"
    case changeSourceCheckAuthor = "changeSourceCheckAuthor"
    case changeSourceLoadInfo = "changeSourceLoadInfo"
    case changeSourceLoadToc = "changeSourceLoadToc"
    case changeSourceLoadWordCount = "changeSourceLoadWordCount"
    case colorAccent = "colorAccent"
    case colorAccentNight = "colorAccentNight"
    case colorBackground = "colorBackground"
    case colorBackgroundNight = "colorBackgroundNight"
    case colorBottomBackground = "colorBottomBackground"
    case colorBottomBackgroundNight = "colorBottomBackgroundNight"
    case colorPrimary = "colorPrimary"
    case colorPrimaryNight = "colorPrimaryNight"
    case comicStyleSelect = "comicStyleSelect"
    case coverShowAuthorN = "coverShowAuthorN"
    case coverShowNameN = "coverShowNameN"
    case customWelcome = "customWelcome"
    case defaultBookTreeUri = "defaultBookTreeUri"
    case disableClickScroll = "disableClickScroll"
    case disableHorizontalPageSnap = "disableHorizontalPageSnap"
    case episodeExportFileName = "episodeExportFileName"
    case immNavigationBar = "immNavigationBar"
    case noAnimScrollPage = "noAnimScrollPage"
    case openBookInfoByClickTitle = "openBookInfoByClickTitle"
    case processText = "process_text"
    case progressBarBehavior = "progressBarBehavior"
    case readBarStyleFollowPage = "readBarStyleFollowPage"
    case recordHeapDump = "recordHeapDump"
    case showReadTitleAddition = "showReadTitleAddition"
    case textBottomJustify = "textBottomJustify"
    case updateToVariant = "updateToVariant"
    case welcomeImagePath = "welcomeImagePath"
    case welcomeImagePathDark = "welcomeImagePathDark"
    case welcomeShowIcon = "welcomeShowIcon"
    case welcomeShowIconDark = "welcomeShowIconDark"
    case welcomeShowText = "welcomeShowText"
    case welcomeShowTextDark = "welcomeShowTextDark"

    // The upstream preferences that are read with their raw key instead of a
    // `PreferKey` constant — the screens that use them are
    // `ui/book/read/config/MoreConfigDialog.kt`,
    // `ui/book/read/config/ReadAloudConfigDialog.kt`,
    // `ui/config/ThemeConfigFragment.kt`, `ui/config/CoverConfigFragment.kt`,
    // `ui/config/BackupConfigFragment.kt`, `help/config/AppConfig.kt` and
    // `service/BaseReadAloudService.kt`.
    /// The click-region configuration — upstream `MoreConfigDialog.kt:182`.
    case clickRegionalConfig = "clickRegionalConfig"
    /// Whether the back key is disabled in the reader — upstream
    /// `ReadBookActivity.kt:288`.
    case disableReturnKey = "disableReturnKey"
    /// The custom page-turn key — upstream `MoreConfigDialog.kt:181`.
    case customPageKey = "customPageKey"
    /// Whether the media button stops the read aloud when the app exits —
    /// upstream `AppConfig.mediaButtonOnExit`.
    case mediaButtonOnExit = "mediaButtonOnExit"
    /// The compatibility switch of the system media control — upstream
    /// `BaseReadAloudService.kt:482`.
    case systemMediaControlCompatibilityChange = "systemMediaControlCompatibilityChange"
    /// Whether the media button skips to the next paragraph — upstream
    /// `MediaButtonReceiver.kt:51`.
    case mediaButtonPerNext = "mediaButtonPerNext"
    /// The system TTS settings — upstream `ReadAloudConfigDialog.kt:107`.
    case sysTtsConfig = "sysTtsConfig"
    /// The style of the welcome screen — upstream
    /// `ThemeConfigFragment.kt:207`.
    case welcomeStyle = "welcomeStyle"
    /// The cover configuration — upstream `ThemeConfigFragment.kt:203`.
    case coverConfig = "coverConfig"
    /// The list of the themes — upstream `ThemeConfigFragment.kt:199`.
    case themeList = "themeList"
    /// The name of the saved day theme — upstream `ThemeConfig.kt:193`.
    case saveDayTheme = "saveDayTheme"
    /// The name of the saved night theme — upstream `ThemeConfig.kt:213`.
    case saveNightTheme = "saveNightTheme"
    /// The cover rule — upstream `CoverConfigFragment.kt:102`.
    case coverRule = "coverRule"
    /// The restore of the old backups — upstream
    /// `BackupConfigFragment.kt:238`.
    case importOld = "import_old"
}

/// A minimal key/value store — upstream `SharedPreferences`.
public protocol SettingsStore: AnyObject {
    func string(forKey key: String) -> String?
    func bool(forKey key: String) -> Bool?
    func int(forKey key: String) -> Int?
    func set(_ value: String?, forKey key: String)
    func set(_ value: Bool, forKey key: String)
    func set(_ value: Int, forKey key: String)
    func removeValue(forKey key: String)
}

public extension SettingsStore {
    /// Stores a floating point preference.
    ///
    /// The upstream's `SharedPreferences` has no floating point type — the
    /// reader stores its sizes and spacings as their textual form
    /// (`ReadBookConfig.kt`), so the port does the same.
    func set(_ value: Double, forKey key: String) {
        set(String(value), forKey: key)
    }
}

/// Reads a boolean the way the upstream's `SharedPreferences` does.
///
/// The upstream stores a boolean preference as a boolean; the port's advanced
/// settings screen writes the raw text of a preference, so a boolean can also
/// be stored as "true" / "false" / "1" / "0" / "yes" / "no". Both forms have
/// to read back the same way — otherwise a switch that was turned on would
/// read back as off.
func settingsBool(from object: Any?) -> Bool? {
    guard let object else { return nil }
    if let flag = object as? Bool { return flag }
    if let text = object as? String {
        switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "1", "yes", "y", "on": return true
        case "false", "0", "no", "n", "off", "": return false
        default: return nil
        }
    }
    if let number = object as? NSNumber { return number.boolValue }
    return nil
}

/// Reads an integer, also from its textual form.
func settingsInt(from object: Any?) -> Int? {
    guard let object else { return nil }
    if let number = object as? Int { return number }
    if let flag = object as? Bool { return flag ? 1 : 0 }
    if let text = object as? String {
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if let number = object as? NSNumber { return number.intValue }
    return nil
}

/// An in-memory settings store.
///
/// Used by the tests and as the cache of the `UserDefaults` store.
public final class InMemorySettingsStore: SettingsStore {
    private var values: [String: Any] = [:]
    private let lock = NSLock()

    public init(values: [String: Any] = [:]) {
        self.values = values
    }

    public func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key] as? String
    }

    public func bool(forKey key: String) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        return settingsBool(from: values[key])
    }

    public func int(forKey key: String) -> Int? {
        lock.lock()
        defer { lock.unlock() }
        return settingsInt(from: values[key])
    }

    public func set(_ value: String?, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        if let value {
            values[key] = value
        } else {
            values.removeValue(forKey: key)
        }
    }

    public func set(_ value: Bool, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    public func set(_ value: Int, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    public func removeValue(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        values.removeValue(forKey: key)
    }

    /// Every stored value — handy for tests and for the backup.
    public var allValues: [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

/// A `UserDefaults` backed settings store.
///
/// `UserDefaults` is the iOS/macOS equivalent of the upstream
/// `SharedPreferences`; the same file is written by the Android app, so the
/// keys must stay identical.
public final class UserDefaultsSettingsStore: SettingsStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// A store in its own suite — the upstream keeps the device-local
    /// preferences (`LocalConfig`) in a separate file, so that they are not
    /// written into a backup.
    public static func localSuite(named name: String = "local") -> UserDefaultsSettingsStore {
        UserDefaultsSettingsStore(defaults: UserDefaults(suiteName: name) ?? .standard)
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func bool(forKey key: String) -> Bool? {
        guard let object = defaults.object(forKey: key) else { return nil }
        return settingsBool(from: object)
    }

    public func int(forKey key: String) -> Int? {
        guard let object = defaults.object(forKey: key) else { return nil }
        return settingsInt(from: object)
    }

    public func set(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    public func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func set(_ value: Int, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

/// The typed settings of the app — upstream `AppConfig`.
///
/// Every accessor keeps the upstream default so that a fresh installation
/// behaves like the Android app.
public final class AppSettings {
    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    /// The underlying store.
    public var settingsStore: SettingsStore { store }

    // MARK: - Reading the raw values

    public func string(_ key: SettingsKey) -> String? {
        store.string(forKey: key.rawValue)
    }

    public func set(_ value: String?, for key: SettingsKey) {
        store.set(value, forKey: key.rawValue)
    }

    public func bool(_ key: SettingsKey, default fallback: Bool) -> Bool {
        store.bool(forKey: key.rawValue) ?? fallback
    }

    public func set(_ value: Bool, for key: SettingsKey) {
        store.set(value, forKey: key.rawValue)
    }

    public func int(_ key: SettingsKey, default fallback: Int) -> Int {
        store.int(forKey: key.rawValue) ?? fallback
    }

    public func set(_ value: Int, for key: SettingsKey) {
        store.set(value, forKey: key.rawValue)
    }

    // MARK: - Appearance

    /// The theme mode — upstream `AppConfig.themeMode` ("0" system, "1" light,
    /// "2" dark, "3" e-ink).
    public var themeMode: String {
        get { string(.themeMode) ?? "0" }
        set { set(newValue, for: .themeMode) }
    }

    /// `true` in e-ink mode — upstream `AppConfig.isEInkMode`.
    public var isEInkMode: Bool {
        themeMode == "3"
    }

    /// `true` when the dark theme is used — upstream `AppConfig.isDarkTheme`.
    public var isDarkTheme: Bool {
        themeMode == "2"
    }

    /// The font scale preference — upstream `PreferKey.fontScale`.
    ///
    /// Upstream stores the scale multiplied by ten (`10` = 1.0) and falls back
    /// to the system scale when the value is outside 0.8…1.6.
    public var fontScalePreference: Int {
        get { int(.fontScale, default: 0) }
        set { set(newValue, for: .fontScale) }
    }

    /// The effective font scale — upstream `AppContextWrapper.getFontScale`.
    public func fontScale(systemScale: Double) -> Double {
        let scale = Double(fontScalePreference) / 10.0
        guard scale >= 0.8, scale <= 1.6 else { return systemScale }
        return scale
    }

    /// The screen orientation — upstream `PreferKey.screenOrientation`.
    public var screenOrientation: Int {
        get { int(.screenOrientation, default: 0) }
        set { set(newValue, for: .screenOrientation) }
    }

    /// The alternate launcher icon — upstream `PreferKey.launcherIcon`.
    ///
    /// The value is the name of the upstream launcher activity (`Launcher1` …
    /// `Launcher6`); an empty value means the primary icon.
    public var launcherIcon: LauncherIcon? {
        get { LauncherIcon.from(string(.launcherIcon)) }
        set { set(newValue?.rawValue, for: .launcherIcon) }
    }

    // MARK: - Network

    /// The user agent — upstream `AppConfig.userAgent`.
    ///
    /// Upstream falls back to a Chrome user agent that carries the Cronet
    /// version; the port keeps the same shape with a fixed Chrome version.
    public static let defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    public var userAgent: String {
        get {
            let value = string(.userAgent) ?? ""
            return value.isEmpty ? AppSettings.defaultUserAgent : value
        }
        set { set(newValue, for: .userAgent) }
    }

    /// The number of parallel downloads — upstream `AppConfig.threadCount`.
    public var threadCount: Int {
        get { int(.threadCount, default: 16) }
        set { set(newValue, for: .threadCount) }
    }

    /// The number of chapters prefetched — upstream `PreferKey.preDownloadNum`.
    public var preDownloadNumber: Int {
        get { int(.preDownloadNum, default: 10) }
        set { set(newValue, for: .preDownloadNum) }
    }

    // MARK: - Bookshelf

    /// The global bookshelf sort — upstream `AppConfig.bookshelfSort`.
    public var bookshelfSort: Int {
        get { int(.bookshelfSort, default: 0) }
        set { set(newValue, for: .bookshelfSort) }
    }

    /// The bookshelf layout (0 = list, 1 = grid) — upstream
    /// `PreferKey.bookshelfLayout`.
    public var bookshelfLayout: Int {
        get { int(.bookshelfLayout, default: 0) }
        set { set(newValue, for: .bookshelfLayout) }
    }

    /// Whether the discovery tab is shown — upstream `AppConfig.showDiscovery`.
    public var showDiscovery: Bool {
        get { bool(.showDiscovery, default: true) }
        set { set(newValue, for: .showDiscovery) }
    }

    /// Whether the RSS tab is shown — upstream `AppConfig.showRSS`.
    public var showRSS: Bool {
        get { bool(.showRss, default: true) }
        set { set(newValue, for: .showRss) }
    }

    /// Whether the review button is shown — upstream `AppConfig.enableReview`.
    ///
    /// Upstream only enables it in debug builds; the port has no debug flag
    /// and keeps the preference only.
    public var enableReview: Bool {
        get { bool(.enableReview, default: false) }
        set { set(newValue, for: .enableReview) }
    }

    /// Whether the cover is the built-in one — upstream
    /// `AppConfig.useDefaultCover`.
    public var useDefaultCover: Bool {
        get { bool(.useDefaultCover, default: false) }
        set { set(newValue, for: .useDefaultCover) }
    }

    /// Whether the covers are only loaded over Wi-Fi — upstream
    /// `PreferKey.loadCoverOnlyWifi`.
    public var loadCoverOnlyWifi: Bool {
        get { bool(.loadCoverOnlyWifi, default: false) }
        set { set(newValue, for: .loadCoverOnlyWifi) }
    }

    /// Whether the unread chapters are marked — upstream `PreferKey.showUnread`.
    public var showUnread: Bool {
        get { bool(.showUnread, default: true) }
        set { set(newValue, for: .showUnread) }
    }

    /// Whether the books are refreshed automatically — upstream
    /// `AppConfig.autoRefreshBook`.
    public var autoRefreshBook: Bool {
        get { bool(.autoRefresh, default: false) }
        set { set(newValue, for: .autoRefresh) }
    }

    /// The sort of a group — upstream `AppConfig.getBookSortByGroupId`.
    public func bookSort(forGroup group: BookGroup) -> Int {
        Int(group.realBookSort(fallback: Int64(bookshelfSort)))
    }

    // MARK: - Reading

    /// The click action of a screen region — upstream `AppConfig.clickAction*`.
    ///
    /// 0 = nothing, 1 = page turn, 2 = menu.
    public func clickAction(_ region: ClickRegion) -> Int {
        int(region.key, default: region.defaultValue)
    }

    public func setClickAction(_ value: Int, for region: ClickRegion) {
        set(value, for: region.key)
    }

    /// The system typeface — upstream `AppConfig.systemTypefaces`.
    public var systemTypefaces: Int {
        get { int(.systemTypefaces, default: 0) }
        set { set(newValue, for: .systemTypefaces) }
    }

    /// Whether the text is justified — upstream `PreferKey.textFullJustify`.
    public var textFullJustify: Bool {
        get { bool(.textFullJustify, default: false) }
        set { set(newValue, for: .textFullJustify) }
    }

    /// The screen brightness in percent — upstream `AppConfig.brightness`.
    public var brightness: Int {
        get { int(.brightness, default: 100) }
        set { set(newValue, for: .brightness) }
    }

    /// The screen brightness in percent while reading at night — upstream
    /// `AppConfig.nightBrightness`.
    public var nightBrightness: Int {
        get { int(.nightBrightness, default: 100) }
        set { set(newValue, for: .nightBrightness) }
    }

    /// The automatic read-aloud speed — upstream `PreferKey.autoReadSpeed`.
    ///
    /// The upstream default is 10 seconds per page
    /// (`ReadBookConfig.kt:194`); a value below 1 is clamped to 1 by the
    /// pager (`AutoReadDialog.kt:78`).
    public var autoReadSpeed: Int {
        get { int(.autoReadSpeed, default: 10) }
        set { set(newValue, for: .autoReadSpeed) }
    }

    // MARK: - Read aloud

    /// The TTS engine — upstream `AppConfig.ttsEngine`.
    public var ttsEngine: String? {
        get { string(.ttsEngine) }
        set { set(newValue, for: .ttsEngine) }
    }

    /// Whether the system TTS voice is used — upstream `PreferKey.ttsFollowSys`.
    public var ttsFollowSys: Bool {
        get { bool(.ttsFollowSys, default: true) }
        set { set(newValue, for: .ttsFollowSys) }
    }

    /// The speech rate — upstream `PreferKey.ttsSpeechRate`.
    public var ttsSpeechRate: Int {
        get { int(.ttsSpeechRate, default: 5) }
        set { set(newValue, for: .ttsSpeechRate) }
    }

    /// Whether the read-aloud reads a whole page at once — upstream
    /// `PreferKey.readAloudByPage`.
    public var readAloudByPage: Bool {
        get { bool(.readAloudByPage, default: false) }
        set { set(newValue, for: .readAloudByPage) }
    }

    /// The auto-stop timer of the read aloud in minutes — upstream
    /// `PreferKey.ttsTimer` (0 = no timer).
    public var ttsTimer: Int {
        get { int(.ttsTimer, default: 0) }
        set { set(newValue, for: .ttsTimer) }
    }

    /// The id of the HTTP TTS engine — upstream `PreferKey.ttsEngine`
    /// (`appTtsEngine`).
    public var ttsEngineId: Int64 {
        get { Int64(int(.ttsEngine, default: 0)) }
        set { set(Int(newValue), for: .ttsEngine) }
    }

    /// Whether the media buttons skip a paragraph instead of a chapter —
    /// upstream `mediaButtonPerNext` (`MediaButtonReceiver.kt:51`).
    public var mediaButtonPerNext: Bool {
        get { bool(.mediaButtonPerNext, default: false) }
        set { set(newValue, for: .mediaButtonPerNext) }
    }

    /// Whether the media button stops the read aloud when the app exits —
    /// upstream `AppConfig.mediaButtonOnExit`.
    public var mediaButtonOnExit: Bool {
        get { bool(.mediaButtonOnExit, default: true) }
        set { set(newValue, for: .mediaButtonOnExit) }
    }

    /// The compatibility switch of the system media control — upstream
    /// `systemMediaControlCompatibilityChange` (`BaseReadAloudService.kt:482`).
    public var systemMediaControlCompatibilityChange: Bool {
        get { bool(.systemMediaControlCompatibilityChange, default: false) }
        set { set(newValue, for: .systemMediaControlCompatibilityChange) }
    }

    // MARK: - Import / export

    /// The charset of the exported text — upstream `AppConfig.exportCharset`.
    public var exportCharset: String {
        get {
            let value = string(.exportCharset) ?? ""
            return value.isEmpty ? "UTF-8" : value
        }
        set { set(newValue, for: .exportCharset) }
    }

    /// The export format (0 = txt, 1 = epub) — upstream `AppConfig.exportType`.
    public var exportType: Int {
        get { int(.exportType, default: 0) }
        set { set(newValue, for: .exportType) }
    }

    /// Whether the replace rules are applied while exporting — upstream
    /// `AppConfig.exportUseReplace`.
    public var exportUseReplace: Bool {
        get { bool(.exportUseReplace, default: true) }
        set { set(newValue, for: .exportUseReplace) }
    }

    /// Whether the chapter titles are omitted while exporting — upstream
    /// `AppConfig.exportNoChapterName`.
    public var exportNoChapterName: Bool {
        get { bool(.exportNoChapterName, default: false) }
        set { set(newValue, for: .exportNoChapterName) }
    }

    /// Whether the images are exported — upstream
    /// `AppConfig.exportPictureFile`.
    public var exportPictureFile: Bool {
        get { bool(.exportPictureFile, default: false) }
        set { set(newValue, for: .exportPictureFile) }
    }

    /// The export file name rule — upstream `PreferKey.bookExportFileName`.
    public var bookExportFileName: String? {
        get { string(.bookExportFileName) }
        set { set(newValue, for: .bookExportFileName) }
    }

    // MARK: - Backup / sync

    /// The backup folder — upstream `PreferKey.backupPath`.
    public var backupPath: String? {
        get { string(.backupPath) }
        set { set(newValue, for: .backupPath) }
    }

    /// Whether only the newest backup is kept — upstream
    /// `AppConfig.onlyLatestBackup`.
    public var onlyLatestBackup: Bool {
        get { bool(.onlyLatestBackup, default: true) }
        set { set(newValue, for: .onlyLatestBackup) }
    }

    /// Whether the reading progress is synchronised — upstream
    /// `AppConfig.syncBookProgress`.
    public var syncBookProgress: Bool {
        get { bool(.syncBookProgress, default: true) }
        set { set(newValue, for: .syncBookProgress) }
    }

    /// Whether the reading progress of the "plus" format is synchronised —
    /// upstream `AppConfig.syncBookProgressPlus`.
    public var syncBookProgressPlus: Bool {
        get { bool(.syncBookProgressPlus, default: false) }
        set { set(newValue, for: .syncBookProgressPlus) }
    }

    /// The WebDAV server — upstream `PreferKey.webDavUrl`.
    public var webDavUrl: String? {
        get { string(.webDavUrl) }
        set { set(newValue, for: .webDavUrl) }
    }

    /// The WebDAV account — upstream `PreferKey.webDavAccount`.
    public var webDavAccount: String? {
        get { string(.webDavAccount) }
        set { set(newValue, for: .webDavAccount) }
    }

    /// The WebDAV password — upstream `PreferKey.webDavPassword`.
    public var webDavPassword: String? {
        get { string(.webDavPassword) }
        set { set(newValue, for: .webDavPassword) }
    }

    /// The WebDAV root folder — upstream `PreferKey.webDavDir`.
    public var webDavDir: String? {
        get { string(.webDavDir) }
        set { set(newValue, for: .webDavDir) }
    }

    /// The device name used in the backup file name — upstream
    /// `PreferKey.webDavDeviceName`.
    public var webDavDeviceName: String? {
        get { string(.webDavDeviceName) }
        set { set(newValue, for: .webDavDeviceName) }
    }

    // MARK: - Web service

    /// Whether the local HTTP API is enabled — upstream `PreferKey.webService`.
    public var webServiceEnabled: Bool {
        get { bool(.webService, default: false) }
        set { set(newValue, for: .webService) }
    }

    /// The port of the local HTTP API — upstream `PreferKey.webPort`.
    public var webPort: Int {
        get { int(.webPort, default: 1122) }
        set { set(newValue, for: .webPort) }
    }

    // MARK: - Miscellaneous

    /// Whether the log is written — upstream `AppConfig.recordLog`.
    public var recordLog: Bool {
        get { bool(.recordLog, default: false) }
        set { set(newValue, for: .recordLog) }
    }

    /// Whether the reading records are kept — upstream
    /// `PreferKey.enableReadRecord`.
    public var enableReadRecord: Bool {
        get { bool(.enableReadRecord, default: true) }
        set { set(newValue, for: .enableReadRecord) }
    }

    /// The Chinese converter — upstream `AppConfig.chineseConverterType`.
    ///
    /// 0 = none, 1 = simplified, 2 = traditional.
    public var chineseConverterType: Int {
        get { int(.chineseConverterType, default: 0) }
        set { set(newValue, for: .chineseConverterType) }
    }
}

/// The nine click regions of the reader — upstream `AppConfig.clickAction*`.
public enum ClickRegion: String, CaseIterable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case middleCenter
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    public var key: SettingsKey {
        switch self {
        case .topLeft: return .clickActionTL
        case .topCenter: return .clickActionTC
        case .topRight: return .clickActionTR
        case .middleLeft: return .clickActionML
        case .middleCenter: return .clickActionMC
        case .middleRight: return .clickActionMR
        case .bottomLeft: return .clickActionBL
        case .bottomCenter: return .clickActionBC
        case .bottomRight: return .clickActionBR
        }
    }

    /// The upstream default — `AppConfig`: the top and bottom edges open the
    /// menu (2), the right and left edges turn the page (1) and the middle
    /// does nothing (0).
    public var defaultValue: Int {
        switch self {
        case .topLeft, .topCenter, .middleLeft, .bottomLeft: return 2
        case .topRight, .middleRight, .bottomCenter, .bottomRight: return 1
        case .middleCenter: return 0
        }
    }
}
