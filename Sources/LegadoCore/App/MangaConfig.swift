//
//  MangaConfig.swift
//  LegadoCore
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/manga/config/MangaFooterConfig.kt
//  app/src/main/java/io/legado/app/ui/book/manga/config/MangaFooterSettingDialog.kt
//
//  The footer configuration of the manga reader — it is stored as JSON in
//  the `mangaFooterConfig` preference (the colour filter lives in
//  `Reader/Manga.swift` next to its matrix).
//

import Foundation

/// The footer configuration of the manga reader — upstream
/// `MangaFooterConfig`.
///
/// The values are stored as JSON in the `mangaFooterConfig` preference.
public struct MangaFooterConfig: Codable, Equatable, Sendable {

    /// Whether the "chapter" label is hidden.
    public var hideChapterLabel: Bool
    /// Whether the chapter is hidden.
    public var hideChapter: Bool
    /// Whether the "page number" label is hidden.
    public var hidePageNumberLabel: Bool
    /// Whether the page number is hidden.
    public var hidePageNumber: Bool
    /// Whether the "progress" label is hidden.
    public var hideProgressRatioLabel: Bool
    /// Whether the progress is hidden.
    public var hideProgressRatio: Bool
    /// The alignment of the footer — 0 = left, 1 = centre, 2 = right.
    public var footerOrientation: Int
    /// Whether the whole footer is hidden.
    public var hideFooter: Bool
    /// Whether the chapter name is hidden.
    public var hideChapterName: Bool

    public init(
        hideChapterLabel: Bool = false,
        hideChapter: Bool = false,
        hidePageNumberLabel: Bool = false,
        hidePageNumber: Bool = false,
        hideProgressRatioLabel: Bool = false,
        hideProgressRatio: Bool = false,
        footerOrientation: Int = 0,
        hideFooter: Bool = false,
        hideChapterName: Bool = false
    ) {
        self.hideChapterLabel = hideChapterLabel
        self.hideChapter = hideChapter
        self.hidePageNumberLabel = hidePageNumberLabel
        self.hidePageNumber = hidePageNumber
        self.hideProgressRatioLabel = hideProgressRatioLabel
        self.hideProgressRatio = hideProgressRatio
        self.footerOrientation = footerOrientation
        self.hideFooter = hideFooter
        self.hideChapterName = hideChapterName
    }

    /// The JSON of the configuration.
    public func jsonString() -> String {
        let object: [String: JSONValue] = [
            "hideChapterLabel": .bool(hideChapterLabel),
            "hideChapter": .bool(hideChapter),
            "hidePageNumberLabel": .bool(hidePageNumberLabel),
            "hidePageNumber": .bool(hidePageNumber),
            "hideProgressRatioLabel": .bool(hideProgressRatioLabel),
            "hideProgressRatio": .bool(hideProgressRatio),
            "footerOrientation": .number(Double(footerOrientation)),
            "hideFooter": .bool(hideFooter),
            "hideChapterName": .bool(hideChapterName)
        ]
        return JSONValue.object(object).jsonString
    }

    /// Reads the configuration.
    public static func parse(_ text: String?) -> MangaFooterConfig {
        guard let text, !text.isEmpty else { return MangaFooterConfig() }
        guard let value = try? JSONValue.parse(text), let object = value.objectValue else {
            return MangaFooterConfig()
        }
        func flag(_ key: String) -> Bool {
            guard let raw = object[key] else { return false }
            switch raw {
            case let .bool(value): return value
            case let .number(value): return value != 0
            case let .string(value): return value == "true" || value == "1"
            default: return false
            }
        }
        func number(_ key: String) -> Int {
            guard let raw = object[key] else { return 0 }
            switch raw {
            case let .number(value): return Int(value)
            case let .string(value): return Int(value) ?? 0
            default: return 0
            }
        }
        return MangaFooterConfig(
            hideChapterLabel: flag("hideChapterLabel"),
            hideChapter: flag("hideChapter"),
            hidePageNumberLabel: flag("hidePageNumberLabel"),
            hidePageNumber: flag("hidePageNumber"),
            hideProgressRatioLabel: flag("hideProgressRatioLabel"),
            hideProgressRatio: flag("hideProgressRatio"),
            footerOrientation: number("footerOrientation"),
            hideFooter: flag("hideFooter"),
            hideChapterName: flag("hideChapterName")
        )
    }
}

/// The manga settings that the menu toggles — upstream `AppConfig`.
public enum MangaSettings {

    /// The colour filter — upstream `AppConfig.mangaColorFilter`.
    public static func colorFilter(_ settings: AppSettings) -> MangaColorFilter {
        MangaColorFilter.parse(settings.string(.mangaColorFilter))
    }

    /// The footer configuration — upstream `AppConfig.mangaFooterConfig`.
    public static func footerConfig(_ settings: AppSettings) -> MangaFooterConfig {
        MangaFooterConfig.parse(settings.string(.mangaFooterConfig))
    }

    /// Stores the colour filter.
    public static func setColorFilter(_ config: MangaColorFilter, settings: AppSettings) {
        settings.set(config.jsonString(), for: .mangaColorFilter)
    }

    /// Stores the footer configuration.
    public static func setFooterConfig(_ config: MangaFooterConfig, settings: AppSettings) {
        settings.set(config.jsonString(), for: .mangaFooterConfig)
    }
}
