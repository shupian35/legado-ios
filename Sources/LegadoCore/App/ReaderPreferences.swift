//
//  ReaderPreferences.swift
//  LegadoCore
//
//  The reading preferences of the app — upstream
//  `app/src/main/res/xml/pref_config_read.xml` (202 lines) and the
//  enumerations of `app/src/main/res/values/arrays.xml` +
//  `array_values.xml`.
//
//  The upstream builds the screen with `MoreConfigDialog`
//  (`ui/book/read/config/MoreConfigDialog.kt:86`) and writes every change
//  into the preferences (`MoreConfigDialog.kt:113`).
//

import Foundation

// MARK: - The enumerations of the preferences

/// The orientation of the screen — upstream `R.array.screen_direction_title`
/// / `R.array.screen_direction_value` (0 unspecified, 1 portrait,
/// 2 landscape, 3 sensor, 4 reversed portrait).
public enum ReaderScreenDirection: Int, CaseIterable, Sendable, Identifiable {
    case unspecified = 0
    case portrait = 1
    case landscape = 2
    case sensor = 3
    case portraitReversed = 4

    public var id: Int { rawValue }

    /// The Chinese name of the orientation.
    public var displayName: String {
        switch self {
        case .unspecified: return "未指定"
        case .portrait: return "竖屏"
        case .landscape: return "横屏"
        case .sensor: return "跟随传感器"
        case .portraitReversed: return "反向竖屏"
        }
    }
}

/// How long the screen stays awake — upstream `R.array.screen_time_out` /
/// `R.array.screen_time_out_value` (0 default, 60, 300, 600, -1 always).
public enum ReaderScreenTimeout: Int, CaseIterable, Sendable, Identifiable {
    case systemDefault = 0
    case oneMinute = 60
    case fiveMinutes = 300
    case tenMinutes = 600
    case always = -1

    public var id: Int { rawValue }

    /// The Chinese name of the timeout.
    public var displayName: String {
        switch self {
        case .systemDefault: return "跟随系统"
        case .oneMinute: return "1 分钟"
        case .fiveMinutes: return "5 分钟"
        case .tenMinutes: return "10 分钟"
        case .always: return "常亮"
        }
    }
}

/// The double-page mode — upstream `R.array.double_page_title` /
/// `R.array.double_page_value` (0 single, 1 double, 2 double in the
/// landscape, 3 double on a tablet or in the landscape).
public enum ReaderDoublePageMode: Int, CaseIterable, Sendable, Identifiable {
    case single = 0
    case double = 1
    case doubleInLandscape = 2
    case doubleInTabletOrLandscape = 3

    public var id: Int { rawValue }

    /// The Chinese name of the mode.
    public var displayName: String {
        switch self {
        case .single: return "单页"
        case .double: return "双页"
        case .doubleInLandscape: return "横屏双页"
        case .doubleInTabletOrLandscape: return "平板或横屏双页"
        }
    }
}

/// What the progress bar moves — upstream
/// `R.array.progress_bar_behavior_title` / `progress_bar_behavior_value`
/// ("page" or "chapter").
public enum ReaderProgressBarBehavior: String, CaseIterable, Sendable, Identifiable {
    case page = "page"
    case chapter = "chapter"

    public var id: String { rawValue }

    /// The Chinese name of the behaviour.
    public var displayName: String {
        switch self {
        case .page: return "调整页码"
        case .chapter: return "调整章节"
        }
    }
}

// MARK: - The accessors

extension AppSettings {

    // MARK: The screen

    /// The orientation — upstream `PreferKey.screenOrientation` (0).
    public var readerScreenDirection: Int {
        get { int(.screenOrientation, default: 0) }
        set { set(newValue, for: .screenOrientation) }
    }

    /// The screen timeout in seconds — upstream `PreferKey.keep_light`
    /// (0 = the system default, -1 = always).
    public var keepLight: Int {
        get { int(.keepLight, default: 0) }
        set { set(newValue, for: .keepLight) }
    }

    /// Whether the status bar is hidden — upstream `PreferKey.hideStatusBar`.
    public var hideStatusBar: Bool {
        get { bool(.hideStatusBar, default: false) }
        set { set(newValue, for: .hideStatusBar) }
    }

    /// Whether the navigation bar is hidden — upstream
    /// `PreferKey.hideNavigationBar`.
    public var hideNavigationBar: Bool {
        get { bool(.hideNavigationBar, default: false) }
        set { set(newValue, for: .hideNavigationBar) }
    }

    /// Whether the reader avoids the display cutouts — upstream
    /// `PreferKey.paddingDisplayCutouts`.
    public var paddingDisplayCutouts: Bool {
        get { bool(.paddingDisplayCutouts, default: false) }
        set { set(newValue, for: .paddingDisplayCutouts) }
    }

    // MARK: The layout

    /// Whether the body text is aligned to the left — upstream
    /// `PreferKey.readBodyToLh` (true).
    public var readBodyToLh: Bool {
        get { bool(.readBodyToLh, default: true) }
        set { set(newValue, for: .readBodyToLh) }
    }

    /// The double-page mode — upstream `PreferKey.doubleHorizontalPage` (0).
    public var doublePageHorizontal: Int {
        get { int(.doublePageHorizontal, default: 0) }
        set { set(newValue, for: .doublePageHorizontal) }
    }

    /// Whether the Chinese layout is used — upstream `PreferKey.useZhLayout`
    /// (false).
    public var useZhLayout: Bool {
        get { bool(.useZhLayout, default: false) }
        set { set(newValue, for: .useZhLayout) }
    }

    /// Whether the text is justified at the bottom — upstream
    /// `PreferKey.textBottomJustify` (true).
    public var textBottomJustify: Bool {
        get { bool(.textBottomJustify, default: true) }
        set { set(newValue, for: .textBottomJustify) }
    }

    // MARK: The paging

    /// What the progress bar moves — upstream `PreferKey.progressBarBehavior`
    /// ("page").
    public var progressBarBehavior: String {
        get { string(.progressBarBehavior) ?? ReaderProgressBarBehavior.page.rawValue }
        set { set(newValue, for: .progressBarBehavior) }
    }

    /// Whether the mouse wheel turns the pages — upstream
    /// `PreferKey.mouseWheelPage` (true).
    public var mouseWheelPage: Bool {
        get { bool(.mouseWheelPage, default: true) }
        set { set(newValue, for: .mouseWheelPage) }
    }

    /// Whether the volume keys turn the pages — upstream
    /// `PreferKey.volumeKeyPage` (true).
    public var volumeKeyPage: Bool {
        get { bool(.volumeKeyPage, default: true) }
        set { set(newValue, for: .volumeKeyPage) }
    }

    /// Whether the volume keys turn the pages while the reader speaks —
    /// upstream `PreferKey.volumeKeyPageOnPlay` (false).
    public var volumeKeyPageOnPlay: Bool {
        get { bool(.volumeKeyPageOnPlay, default: false) }
        set { set(newValue, for: .volumeKeyPageOnPlay) }
    }

    /// Whether a long press of a key turns the page — upstream
    /// `PreferKey.keyPageOnLongPress` (false).
    public var keyPageOnLongPress: Bool {
        get { bool(.keyPageOnLongPress, default: false) }
        set { set(newValue, for: .keyPageOnLongPress) }
    }

    /// The touch slop of the page turn in pixels — upstream
    /// `PreferKey.pageTouchSlop` (0 = the platform slop).
    public var pageTouchSlop: Int {
        get { int(.pageTouchSlop, default: 0) }
        set { set(newValue, for: .pageTouchSlop) }
    }

    /// Whether the scrolling mode turns the pages without an animation —
    /// upstream `PreferKey.noAnimScrollPage` (false).
    public var noAnimScrollPage: Bool {
        get { bool(.noAnimScrollPage, default: false) }
        set { set(newValue, for: .noAnimScrollPage) }
    }

    /// Whether a tap on an image opens the preview — upstream
    /// `PreferKey.previewImageByClick` (false).
    public var previewImageByClick: Bool {
        get { bool(.previewImageByClick, default: false) }
        set { set(newValue, for: .previewImageByClick) }
    }

    /// Whether the rendering is optimised — upstream
    /// `PreferKey.optimizeRender` (false).
    public var optimizeRender: Bool {
        get { bool(.optimizeRender, default: false) }
        set { set(newValue, for: .optimizeRender) }
    }

    // MARK: The behaviour

    /// Whether the source is changed automatically when the book has no
    /// chapters — upstream `PreferKey.autoChangeSource` (true).
    public var autoChangeSource: Bool {
        get { bool(.autoChangeSource, default: true) }
        set { set(newValue, for: .autoChangeSource) }
    }

    /// Whether the text can be selected — upstream `PreferKey.selectText`
    /// (true).
    public var textSelectAble: Bool {
        get { bool(.textSelectAble, default: true) }
        set { set(newValue, for: .textSelectAble) }
    }

    /// Whether the brightness slider is shown — upstream
    /// `PreferKey.showBrightnessView` (true).
    public var showBrightnessView: Bool {
        get { bool(.showBrightnessView, default: true) }
        set { set(newValue, for: .showBrightnessView) }
    }

    /// Whether the text menu is expanded — upstream
    /// `PreferKey.expandTextMenu` (false).
    public var expandTextMenu: Bool {
        get { bool(.expandTextMenu, default: false) }
        set { set(newValue, for: .expandTextMenu) }
    }

    /// Whether the extra title of the reading is shown — upstream
    /// `PreferKey.showReadTitleAddition` (true).
    public var showReadTitleAddition: Bool {
        get { bool(.showReadTitleAddition, default: true) }
        set { set(newValue, for: .showReadTitleAddition) }
    }

    /// Whether the bottom bar follows the style of the page — upstream
    /// `PreferKey.readBarStyleFollowPage` (false).
    public var readBarStyleFollowPage: Bool {
        get { bool(.readBarStyleFollowPage, default: false) }
        set { set(newValue, for: .readBarStyleFollowPage) }
    }
}
