//
//  FontResolver.swift
//  LegadoCore
//
//  The port of the upstream font selection.
//
//  Upstream `ui/book/read/page/provider/ChapterProvider.kt:884-933`:
//  * `getTypeface(fontPath)` loads the font file the user picked; when no
//    file is configured it falls back to `AppConfig.systemTypefaces`:
//    1 = `Typeface.SERIF`, 2 = `Typeface.MONOSPACE`, otherwise
//    `Typeface.SANS_SERIF`. A broken font file resets the preference and
//    falls back to the sans-serif face.
//  * `getPaints(typeface)` derives the title and the body faces from
//    `ReadBookConfig.textBold`:
//    0 = (title bold, body normal), 1 = (title black/900, body bold),
//    2 = (title normal, body light/300).
//
//  The port keeps the decision logic platform independent and only the
//  concrete font objects are resolved by the platform layer.
//

import Foundation

/// The upstream `AppConfig.systemTypefaces` values.
public enum SystemTypeface: Int, CaseIterable, Sendable {
    /// `Typeface.SANS_SERIF` — the default.
    case sansSerif = 0
    /// `Typeface.SERIF`.
    case serif = 1
    /// `Typeface.MONOSPACE`.
    case monospace = 2

    /// The upstream name of the face.
    public var name: String {
        switch self {
        case .sansSerif: return "sans-serif"
        case .serif: return "serif"
        case .monospace: return "monospace"
        }
    }

    /// The iOS family that corresponds to the upstream face.
    public var family: ReaderFontFamily {
        switch self {
        case .sansSerif: return .system
        case .serif: return .serif
        case .monospace: return .monospace
        }
    }
}

/// The font families the port can ask the platform for.
public enum ReaderFontFamily: String, CaseIterable, Sendable {
    /// The system font (San Francisco with the PingFang fallback for CJK).
    case system
    /// The Chinese serif face (Songti SC).
    case serif
    /// The monospaced face (Menlo).
    case monospace
    /// A font file that the user installed — resolved by the platform layer.
    case file

    /// The name of the face as the platform knows it.
    public var platformName: String {
        switch self {
        case .system: return ""
        case .serif: return "Songti SC"
        case .monospace: return "Menlo"
        case .file: return ""
        }
    }
}

/// The weight variants the upstream uses.
public enum ReaderFontWeight: Int, CaseIterable, Sendable {
    case light = 300
    case regular = 400
    case bold = 700
    case black = 900

    /// The upstream weight value.
    public var value: Int { rawValue }
}

/// A platform independent description of a reader font.
public struct ReaderFontDescriptor: Equatable, Sendable {
    /// The family.
    public var family: ReaderFontFamily
    /// The weight.
    public var weight: ReaderFontWeight
    /// The size in points.
    public var size: Double
    /// The path of the user font file, when `family == .file`.
    public var filePath: String?

    public init(
        family: ReaderFontFamily,
        weight: ReaderFontWeight,
        size: Double,
        filePath: String? = nil
    ) {
        self.family = family
        self.weight = weight
        self.size = size
        self.filePath = filePath
    }
}

/// The upstream `ReadBookConfig.textBold` values.
public enum ReaderTextBold: Int, CaseIterable, Sendable {
    /// The title is bold, the body is regular.
    case titleBold = 0
    /// The title is black (900), the body is bold.
    case bodyBold = 1
    /// The title is regular, the body is light (300).
    case lightBody = 2

    /// The weight of the title face.
    public var titleWeight: ReaderFontWeight {
        switch self {
        case .titleBold: return .bold
        case .bodyBold: return .black
        case .lightBody: return .regular
        }
    }

    /// The weight of the body face.
    public var bodyWeight: ReaderFontWeight {
        switch self {
        case .titleBold: return .regular
        case .bodyBold: return .bold
        case .lightBody: return .light
        }
    }
}

/// Resolves the reader fonts the way upstream does.
public enum FontResolver {

    /// The title and the body descriptors.
    public struct Resolved: Equatable, Sendable {
        public var title: ReaderFontDescriptor
        public var body: ReaderFontDescriptor
    }

    /// Resolves the faces.
    ///
    /// - Parameters:
    ///   - textBold: the upstream `ReadBookConfig.textBold` value.
    ///   - textSize: the body size in points.
    ///   - titleSize: the extra size of the title (upstream: the title size is
    ///     `textSize + titleSize`).
    ///   - systemTypeface: the upstream `AppConfig.systemTypefaces` value.
    ///   - fontPath: the font file the user picked, if any.
    public static func resolve(
        textBold: Int,
        textSize: Double,
        titleSize: Double,
        systemTypeface: Int,
        fontPath: String? = nil
    ) -> Resolved {
        let bold = ReaderTextBold(rawValue: textBold) ?? .titleBold
        let family: ReaderFontFamily
        let filePath: String?
        if let fontPath, !fontPath.isEmpty {
            family = .file
            filePath = fontPath
        } else {
            family = (SystemTypeface(rawValue: systemTypeface) ?? .sansSerif).family
            filePath = nil
        }
        let title = ReaderFontDescriptor(
            family: family,
            weight: bold.titleWeight,
            size: textSize + titleSize,
            filePath: filePath
        )
        let body = ReaderFontDescriptor(
            family: family,
            weight: bold.bodyWeight,
            size: textSize,
            filePath: filePath
        )
        return Resolved(title: title, body: body)
    }

    /// The upstream resets the font preference when the file cannot be
    /// loaded; the port reports the failure so the caller can do the same.
    public static func isUsableFontPath(_ path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}
