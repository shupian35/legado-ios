//
//  HomePage.swift
//  LegadoCore
//
//  The port of the `AppConfig.defaultHomePage` preference of upstream
//  (app/src/main/java/io/legado/app/help/config/AppConfig.kt) and of
//  `MainActivity.upHomePage()` (MainActivity.kt:385-398).
//

import Foundation

// MARK: - The tab of the start page

/// The tab the application opens on.
///
/// Upstream `MainActivity.upHomePage()` knows the four values "bookshelf",
/// "explore", "rss" and "my"; the explore and the RSS tab only exist when the
/// preference `showDiscovery` / `showRSS` is on.
public enum HomePage: String, Equatable, CaseIterable, Identifiable, Sendable {
    /// The bookshelf — upstream "bookshelf".
    case bookshelf
    /// The discovery — upstream "explore".
    case explore
    /// The RSS feed — upstream "rss".
    case rss
    /// The "我的" tab of the port (the drawer menu of upstream) — upstream "my".
    case my

    public var id: String { rawValue }

    /// The Chinese title of the tab.
    public var displayName: String {
        switch self {
        case .bookshelf: return "书架"
        case .explore: return "发现"
        case .rss: return "订阅"
        case .my: return "我的"
        }
    }

    /// The symbol of the tab.
    public var systemImage: String {
        switch self {
        case .bookshelf: return "books.vertical"
        case .explore: return "safari"
        case .rss: return "newspaper"
        case .my: return "gearshape"
        }
    }

    /// Whether the tab exists with the given visibility flags.
    ///
    /// Upstream `upHomePage()` skips the explore and the RSS tab when the
    /// preference is off.
    public func isVisible(showDiscovery: Bool, showRSS: Bool) -> Bool {
        switch self {
        case .explore: return showDiscovery
        case .rss: return showRSS
        default: return true
        }
    }
}
