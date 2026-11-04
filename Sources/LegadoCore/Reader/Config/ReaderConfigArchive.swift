//
//  ReaderConfigArchive.swift
//  LegadoCore
//
//  The import and the export of the reader style — upstream `readConfig.zip`.
//
//  The upstream exports the style of the reader as a ZIP that holds
//  `readConfig.json` (the `ReadBookConfig.Config` of the upstream), the font
//  file of the style and the background images of the three modes
//  (`ui/book/read/config/BgTextConfigDialog.kt:266-318`). The import reads the
//  archive back, copies the font and the background images into the app and
//  rewrites the paths of the configuration
//  (`help/config/ReadBookConfig.kt:460-520`).
//
//  The port keeps the same format: the JSON uses the field names of the
//  upstream, so that an archive written by the Android app can be read by the
//  port and the other way round. The fields the upstream does not know (the
//  preferences of the reader that live in the `SharedPreferences`) are written
//  under their `PreferKey` names — the upstream's GSON ignores them.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/config/BgTextConfigDialog.kt
//  app/src/main/java/io/legado/app/help/config/ReadBookConfig.kt
//

import Foundation

/// The errors of the reader style archive.
public enum ReaderConfigArchiveError: Error, Equatable {
    /// The archive does not hold `readConfig.json`.
    case missingConfigFile
    /// The `readConfig.json` of the archive cannot be read.
    case brokenConfigFile
}

/// The reader style archive — upstream `readConfig.zip`.
public enum ReaderConfigArchive {

    /// The name of the JSON file inside the archive — upstream
    /// `ReadBookConfig.configFileName`.
    public static let configFileName = "readConfig.json"

    /// The name of the archive — upstream `BgTextConfigDialog.configFileName`.
    public static let archiveFileName = "readConfig.zip"

    // MARK: - The payload

    /// A file that travels with the configuration.
    public struct File: Equatable {
        /// The name of the file.
        public var name: String
        /// The content of the file.
        public var data: Data

        public init(name: String, data: Data) {
            self.name = name
            self.data = data
        }
    }

    /// What an archive holds.
    public struct Payload: Equatable {
        /// The configuration.
        public var config: ReaderConfig
        /// The name of the font — the file travels with the archive.
        public var fontName: String?
        /// The font file.
        public var font: File?
        /// The background images (the day, the night and the e-ink mode).
        public var backgrounds: [File]

        public init(
            config: ReaderConfig,
            fontName: String? = nil,
            font: File? = nil,
            backgrounds: [File] = []
        ) {
            self.config = config
            self.fontName = fontName
            self.font = font
            self.backgrounds = backgrounds
        }
    }

    // MARK: - The JSON

    /// The JSON of a configuration — the field names of the upstream.
    ///
    /// - Parameters:
    ///   - config: the configuration.
    ///   - fontName: the name of the font of the style (the upstream writes
    ///     the file name, not the path).
    ///   - name: the name of the style.
    ///   - backgroundType: the type of the day background (0 a colour,
    ///     1 an asset image, 2 a user image).
    public static func json(
        of config: ReaderConfig,
        fontName: String? = nil,
        name: String = "",
        backgroundType: Int = 0
    ) -> String {
        let object: [String: JSONValue] = [
            "name": .string(name),
            // The backgrounds and their colours.
            "bgStr": .string(config.backgroundColor),
            "bgStrNight": .string(config.backgroundColorNight),
            "bgStrEInk": .string(config.backgroundColorEInk),
            "bgAlpha": .number(Double(config.backgroundAlpha)),
            "bgType": .number(Double(backgroundType)),
            "bgTypeNight": .number(Double(backgroundType)),
            "bgTypeEInk": .number(Double(backgroundType)),
            "textColor": .string(config.textColor),
            "textColorNight": .string(config.textColorNight),
            "textColorEInk": .string(config.textColorEInk),
            // The typography.
            "pageAnim": .number(Double(config.pageAnim)),
            "textFont": .string(fontName ?? ""),
            "textBold": .number(Double(config.textBold)),
            "textSize": .number(config.textSize),
            "letterSpacing": .number(config.letterSpacing),
            "lineSpacingExtra": .number(config.lineSpacingExtra),
            "paragraphSpacing": .number(config.paragraphSpacing),
            "titleMode": .number(Double(config.titleMode)),
            "titleSize": .number(config.titleSize),
            "titleTopSpacing": .number(config.titleTopSpacing),
            "titleBottomSpacing": .number(config.titleBottomSpacing),
            "paragraphIndent": .string(config.paragraphIndent),
            "underline": .bool(config.underline),
            "paddingBottom": .number(config.paddingBottom),
            "paddingLeft": .number(config.paddingLeft),
            "paddingRight": .number(config.paddingRight),
            "paddingTop": .number(config.paddingTop),
            // The tips.
            "tipHeaderLeft": .number(Double(config.tipHeaderLeft)),
            "tipHeaderMiddle": .number(Double(config.tipHeaderMiddle)),
            "tipHeaderRight": .number(Double(config.tipHeaderRight)),
            "tipFooterLeft": .number(Double(config.tipFooterLeft)),
            "tipFooterMiddle": .number(Double(config.tipFooterMiddle)),
            "tipFooterRight": .number(Double(config.tipFooterRight)),
            "tipColor": .number(Double(config.tipColor)),
            "tipDividerColor": .number(Double(config.tipDividerColor)),
            "headerMode": .number(Double(config.headerMode)),
            "footerMode": .number(Double(config.footerMode)),
            // The preferences of the reader that the upstream keeps in the
            // `SharedPreferences` — the upstream ignores them, the port reads
            // them back.
            "textFullJustify": .bool(config.textFullJustify),
            "textBottomJustify": .bool(config.textBottomJustify),
            "useZhLayout": .bool(config.useZhLayout),
            "doubleHorizontalPage": .bool(config.doublePage),
            "readStyleSelect": .number(Double(config.styleIndex))
        ]
        return JSONValue.object(object).jsonString
    }

    /// Reads a configuration from the JSON of the upstream.
    ///
    /// The values that the JSON does not hold keep the default of the port.
    public static func parse(_ text: String) throws -> ReaderConfig {
        guard let value = try? JSONValue.parse(text),
              let object = value.objectValue else {
            throw ReaderConfigArchiveError.brokenConfigFile
        }
        var config = ReaderConfig()

        func stringValue(_ key: String, _ fallback: String) -> String {
            guard let raw = object[key] else { return fallback }
            if case .string(let value) = raw { return value }
            if case .number(let value) = raw { return String(value) }
            return fallback
        }
        func numberValue(_ key: String, _ fallback: Double) -> Double {
            guard let raw = object[key] else { return fallback }
            switch raw {
            case .number(let value): return value
            case .string(let value): return Double(value) ?? fallback
            case .bool(let value): return value ? 1 : 0
            default: return fallback
            }
        }
        func integerValue(_ key: String, _ fallback: Int) -> Int {
            Int(numberValue(key, Double(fallback)))
        }
        func flagValue(_ key: String, _ fallback: Bool) -> Bool {
            guard let raw = object[key] else { return fallback }
            if case .bool(let value) = raw { return value }
            if case .number(let value) = raw { return value != 0 }
            if case .string(let value) = raw { return value == "true" || value == "1" }
            return fallback
        }

        config.backgroundColor = stringValue("bgStr", config.backgroundColor)
        config.backgroundColorNight = stringValue("bgStrNight", config.backgroundColorNight)
        config.backgroundColorEInk = stringValue("bgStrEInk", config.backgroundColorEInk)
        config.backgroundAlpha = integerValue("bgAlpha", config.backgroundAlpha)
        config.textColor = stringValue("textColor", config.textColor)
        config.textColorNight = stringValue("textColorNight", config.textColorNight)
        config.textColorEInk = stringValue("textColorEInk", config.textColorEInk)
        config.pageAnim = integerValue("pageAnim", config.pageAnim)
        config.textBold = integerValue("textBold", config.textBold)
        config.textSize = numberValue("textSize", config.textSize)
        config.letterSpacing = numberValue("letterSpacing", config.letterSpacing)
        config.lineSpacingExtra = numberValue("lineSpacingExtra", config.lineSpacingExtra)
        config.paragraphSpacing = numberValue("paragraphSpacing", config.paragraphSpacing)
        config.titleMode = integerValue("titleMode", config.titleMode)
        config.titleSize = numberValue("titleSize", config.titleSize)
        config.titleTopSpacing = numberValue("titleTopSpacing", config.titleTopSpacing)
        config.titleBottomSpacing = numberValue("titleBottomSpacing", config.titleBottomSpacing)
        config.paragraphIndent = stringValue("paragraphIndent", config.paragraphIndent)
        config.underline = flagValue("underline", config.underline)
        config.paddingBottom = numberValue("paddingBottom", config.paddingBottom)
        config.paddingLeft = numberValue("paddingLeft", config.paddingLeft)
        config.paddingRight = numberValue("paddingRight", config.paddingRight)
        config.paddingTop = numberValue("paddingTop", config.paddingTop)
        config.tipHeaderLeft = integerValue("tipHeaderLeft", config.tipHeaderLeft)
        config.tipHeaderMiddle = integerValue("tipHeaderMiddle", config.tipHeaderMiddle)
        config.tipHeaderRight = integerValue("tipHeaderRight", config.tipHeaderRight)
        config.tipFooterLeft = integerValue("tipFooterLeft", config.tipFooterLeft)
        config.tipFooterMiddle = integerValue("tipFooterMiddle", config.tipFooterMiddle)
        config.tipFooterRight = integerValue("tipFooterRight", config.tipFooterRight)
        config.tipColor = integerValue("tipColor", config.tipColor)
        config.tipDividerColor = integerValue("tipDividerColor", config.tipDividerColor)
        config.headerMode = integerValue("headerMode", config.headerMode)
        config.footerMode = integerValue("footerMode", config.footerMode)
        config.textFullJustify = flagValue("textFullJustify", config.textFullJustify)
        config.textBottomJustify = flagValue("textBottomJustify", config.textBottomJustify)
        config.useZhLayout = flagValue("useZhLayout", config.useZhLayout)
        config.doublePage = flagValue("doubleHorizontalPage", config.doublePage)
        config.styleIndex = integerValue("readStyleSelect", config.styleIndex)
        // The upstream derives the centred title from the title mode
        // (`ReadBookConfig.kt:310`).
        config.isMiddleTitle = config.titleMode == 1
        config.showHeader = config.headerMode != 2
        config.showFooter = config.footerMode != 1
        return config
    }

    /// The name of the font of a JSON — upstream `Config.textFont`.
    public static func fontName(in text: String) -> String? {
        guard let value = try? JSONValue.parse(text),
              let object = value.objectValue,
              case .string(let name)? = object["textFont"],
              !name.isEmpty else {
            return nil
        }
        return name
    }

    // MARK: - The archive

    /// Builds the archive — upstream `BgTextConfigDialog.exportConfig`.
    ///
    /// - Parameters:
    ///   - config: the configuration.
    ///   - font: the font file of the style.
    ///   - backgrounds: the background images of the three modes.
    public static func archive(
        config: ReaderConfig,
        font: File? = nil,
        backgrounds: [File] = []
    ) throws -> Data {
        var entries: [ZipWriteEntry] = []
        let json = self.json(of: config, fontName: font?.name)
        entries.append(ZipWriteEntry(name: configFileName, data: Data(json.utf8)))
        if let font {
            entries.append(ZipWriteEntry(name: font.name, data: font.data))
        }
        for background in backgrounds {
            entries.append(ZipWriteEntry(name: background.name, data: background.data))
        }
        return try ZipWriter.archive(entries)
    }

    /// Reads the archive — upstream `ReadBookConfig.import(byteArray)`.
    ///
    /// The font and the background images travel with the archive; the caller
    /// copies them into the app (the upstream copies them into
    /// `<externalFiles>/font` and `<externalFiles>/bg`).
    public static func read(_ data: Data) throws -> Payload {
        let archive = try ZipArchive(data: data)
        guard let entry = archive.entry(named: configFileName),
              let jsonData = try? archive.data(for: entry) else {
            throw ReaderConfigArchiveError.missingConfigFile
        }
        guard let json = String(data: jsonData, encoding: .utf8) else {
            throw ReaderConfigArchiveError.brokenConfigFile
        }
        let config = try parse(json)
        let fontName = fontName(in: json)
        var font: File?
        if let fontName {
            if let entry = archive.entry(named: fontName),
               let data = try? archive.data(for: entry) {
                font = File(name: fontName, data: data)
            }
        }
        var backgrounds: [File] = []
        for entry in archive.entries where !entry.isDirectory && entry.name != configFileName {
            guard entry.name != fontName else { continue }
            guard let data = try? archive.data(for: entry) else { continue }
            backgrounds.append(File(name: entry.name, data: data))
        }
        return Payload(
            config: config,
            fontName: fontName,
            font: font,
            backgrounds: backgrounds
        )
    }
}
