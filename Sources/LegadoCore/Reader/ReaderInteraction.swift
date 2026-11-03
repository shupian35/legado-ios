//
//  ReaderInteraction.swift
//  LegadoCore
//
//  Port of the reading gestures of
//  `app/src/main/java/io/legado/app/ui/book/read/page/ReadView.kt`
//  (the nine tap zones and the click actions) and of the gesture constants
//  of `app/src/main/java/io/legado/app/ui/book/read/page/delegate/PageDelegate.kt`.
//
//  The Android canvas animations (cover / slide / simulation / scroll) are not
//  reproduced — the SwiftUI layer uses the system page transition — but the
//  *semantics* of the zones, the actions and their defaults are identical, so
//  a user who configured the tap zones on Android keeps the same behaviour.
//

import Foundation

// MARK: - Tap zones

/// The nine tap zones of the reader page.
///
/// Upstream keeps them as nine `RectF` fields (`tlRect`, `tcRect`, …) that are
/// recomputed in `setRect9x()` on every size change.
public enum TapZone: Int, CaseIterable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case middleLeft
    case middleCenter
    case middleRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    /// The upstream default action of the zone —
    /// `AppConfig.clickActionTL` … `AppConfig.clickActionBR`.
    public var defaultAction: ClickAction {
        switch self {
        case .topLeft: return .prevPage
        case .topCenter: return .prevPage
        case .topRight: return .nextPage
        case .middleLeft: return .prevPage
        case .middleCenter: return .menu
        case .middleRight: return .nextPage
        case .bottomLeft: return .prevPage
        case .bottomCenter: return .nextPage
        case .bottomRight: return .nextPage
        }
    }

    /// The matching preference region — the zones and the
    /// `clickActionTopLeft` … `clickActionBottomRight` preferences use the
    /// same nine positions.
    public var clickRegion: ClickRegion {
        switch self {
        case .topLeft: return .topLeft
        case .topCenter: return .topCenter
        case .topRight: return .topRight
        case .middleLeft: return .middleLeft
        case .middleCenter: return .middleCenter
        case .middleRight: return .middleRight
        case .bottomLeft: return .bottomLeft
        case .bottomCenter: return .bottomCenter
        case .bottomRight: return .bottomRight
        }
    }
}

// MARK: - Click actions

/// The action a tap performs.
///
/// The raw values are the upstream ones (`ReadView.click(action)`), the labels
/// are the Chinese labels of `ClickActionConfigDialog`.
public enum ClickAction: Int, CaseIterable, Sendable {
    /// 不动作 — selectable upstream but there is no branch for it, so it is a
    /// no-op.
    case noAction = -1
    /// 菜单
    case menu = 0
    /// 下一页
    case nextPage = 1
    /// 上一页
    case prevPage = 2
    /// 下一章
    case nextChapter = 3
    /// 上一章
    case prevChapter = 4
    /// 朗读上一段
    case prevParagraph = 5
    /// 朗读下一段
    case nextParagraph = 6
    /// 添加书签
    case addBookmark = 7
    /// 编辑内容
    case editContent = 8
    /// 替换状态切换
    case toggleReplaceRule = 9
    /// 目录
    case chapterList = 10
    /// 搜索内容
    case searchContent = 11
    /// 同步进度
    case syncProgress = 12
    /// 朗读暂停/继续
    case pauseResumeReadAloud = 13

    /// The Chinese label of the action — upstream `ClickActionConfigDialog`.
    public var name: String {
        switch self {
        case .noAction: return "不动作"
        case .menu: return "菜单"
        case .nextPage: return "下一页"
        case .prevPage: return "上一页"
        case .nextChapter: return "下一章"
        case .prevChapter: return "上一章"
        case .prevParagraph: return "朗读上一段"
        case .nextParagraph: return "朗读下一段"
        case .addBookmark: return "添加书签"
        case .editContent: return "编辑内容"
        case .toggleReplaceRule: return "替换状态切换"
        case .chapterList: return "目录"
        case .searchContent: return "搜索内容"
        case .syncProgress: return "同步进度"
        case .pauseResumeReadAloud: return "朗读暂停/继续"
        }
    }
}

// MARK: - Rects

/// A rectangle in the reader page coordinate space.
public struct ReaderRect: Equatable, Sendable {
    public var left: Double
    public var top: Double
    public var right: Double
    public var bottom: Double

    public init(left: Double, top: Double, right: Double, bottom: Double) {
        self.left = left
        self.top = top
        self.right = right
        self.bottom = bottom
    }

    /// Upstream `RectF.contains` — the edges are **exclusive**
    /// (`left < x && x < right && top < y && y < bottom`).
    public func contains(x: Double, y: Double) -> Bool {
        left < x && x < right && top < y && y < bottom
    }
}

// MARK: - The zone mapper

/// Maps a tap position onto one of the nine zones.
///
/// The geometry is upstream's `setRect9x()`:
///
/// ```kotlin
/// tlRect.set(0f, 0f, width * 0.33f, height * 0.33f)
/// tcRect.set(width * 0.33f, 0f, width * 0.66f, height * 0.33f)
/// trRect.set(width * 0.36f, 0f, width.toFloat(), height * 0.33f)
/// …
/// ```
///
/// Note the `0.36` of the top-right rect: upstream overlaps the top-center
/// rect between 0.36 and 0.66 and tests the center first, so a tap in that
/// strip is a *top-center* tap. The quirk is reproduced on purpose.
public enum TapZoneMapper {

    /// The rect of every zone for a page of `width` × `height`.
    public static func rects(width: Double, height: Double) -> [TapZone: ReaderRect] {
        [
            .topLeft: ReaderRect(left: 0, top: 0, right: width * 0.33, bottom: height * 0.33),
            .topCenter: ReaderRect(left: width * 0.33, top: 0, right: width * 0.66, bottom: height * 0.33),
            .topRight: ReaderRect(left: width * 0.36, top: 0, right: width, bottom: height * 0.33),
            .middleLeft: ReaderRect(left: 0, top: height * 0.33, right: width * 0.33, bottom: height * 0.66),
            .middleCenter: ReaderRect(left: width * 0.33, top: height * 0.33, right: width * 0.66, bottom: height * 0.66),
            .middleRight: ReaderRect(left: width * 0.66, top: height * 0.33, right: width, bottom: height * 0.66),
            .bottomLeft: ReaderRect(left: 0, top: height * 0.66, right: width * 0.33, bottom: height),
            .bottomCenter: ReaderRect(left: width * 0.33, top: height * 0.66, right: width * 0.66, bottom: height),
            .bottomRight: ReaderRect(left: width * 0.66, top: height * 0.66, right: width, bottom: height)
        ]
    }

    /// The dispatch order of upstream `onSingleTapUp()`:
    /// `mc → bc → bl → br → ml → mr → tl → tc → tr`.
    ///
    /// The order matters because the rects overlap (the top-right rect starts
    /// at 0.36) and because the rect edges are inclusive.
    public static let dispatchOrder: [TapZone] = [
        .middleCenter, .bottomCenter, .bottomLeft, .bottomRight,
        .middleLeft, .middleRight, .topLeft, .topCenter, .topRight
    ]

    /// The zone a tap at (`x`, `y`) hits, or `nil` when it hits none.
    public static func zone(atX x: Double, y: Double, width: Double, height: Double) -> TapZone? {
        let rects = rects(width: width, height: height)
        for zone in dispatchOrder {
            guard let rect = rects[zone] else { continue }
            if rect.contains(x: x, y: y) { return zone }
        }
        return nil
    }
}

// MARK: - The configuration

/// The tap-zone configuration of the reader.
public struct ReaderClickConfiguration: Equatable, Sendable {
    /// The action of every zone.
    public var actions: [TapZone: ClickAction]

    public init(actions: [TapZone: ClickAction] = [:]) {
        var merged: [TapZone: ClickAction] = [:]
        for zone in TapZone.allCases {
            merged[zone] = actions[zone] ?? zone.defaultAction
        }
        self.actions = merged
    }

    /// The action of a zone.
    public func action(for zone: TapZone) -> ClickAction {
        actions[zone] ?? zone.defaultAction
    }

    /// The action a tap at (`x`, `y`) performs.
    public func action(atX x: Double, y: Double, width: Double, height: Double) -> ClickAction? {
        guard let zone = TapZoneMapper.zone(atX: x, y: y, width: width, height: height) else { return nil }
        return action(for: zone)
    }

    /// Upstream `AppConfig.detectClickArea()` — when no zone is mapped to the
    /// menu the middle-center is reset to the menu, otherwise the reader would
    /// have no way to open the menu at all.
    public func repaired() -> ReaderClickConfiguration {
        let hasMenu = TapZone.allCases.contains { action(for: $0) == .menu }
        guard !hasMenu else { return self }
        var copy = self
        copy.actions[.middleCenter] = .menu
        return copy
    }

    /// Builds the configuration from the reader preferences — the upstream
    /// `clickActionTopLeft` … `clickActionBottomRight`.
    public static func from(settings: AppSettings) -> ReaderClickConfiguration {
        var actions: [TapZone: ClickAction] = [:]
        for zone in TapZone.allCases {
            let value = settings.clickAction(zone.clickRegion)
            actions[zone] = ClickAction(rawValue: value) ?? .noAction
        }
        return ReaderClickConfiguration(actions: actions).repaired()
    }
}

// MARK: - Gesture constants

/// The gesture constants of the upstream reader.
public enum ReaderGesture {
    /// Upstream `longPressTimeout` — 600 ms.
    public static let longPressTimeout: Double = 0.6

    /// Upstream `ReadView.defaultAnimationSpeed` — 300 ms for a full page drag.
    public static let defaultAnimationSpeed: Int = 300

    /// Upstream `PageDelegate.keyTurnPage` — 100 ms for a keyboard page turn.
    public static let keyAnimationSpeed: Int = 100

    /// The platform `scaledTouchSlop` used when `AppConfig.pageTouchSlop` is 0.
    public static let defaultTouchSlop: Double = 8

    /// The squared movement threshold of the page delegates —
    /// upstream `pageSlopSquare2`.
    public static func squaredSlop(_ slop: Double = defaultTouchSlop) -> Double {
        slop * slop
    }

    /// The animation duration of a page turn — upstream `startScroll`:
    /// `(animationSpeed * |dx|) / viewWidth`.
    public static func animationDuration(distance: Double, viewWidth: Double, speed: Int = defaultAnimationSpeed) -> Int {
        guard viewWidth > 0 else { return 0 }
        return Int(Double(speed) * abs(distance) / viewWidth)
    }
}
