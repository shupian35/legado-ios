import Foundation

/// Backup and restore — the port of
/// `app/src/main/java/io/legado/app/help/storage/Backup.kt` and `Restore.kt`.
///
/// ## What the archive contains
///
/// Upstream writes **one JSON file per table** into a ZIP, plus the
/// preference file and the reader-configuration files:
///
/// ```
/// bookshelf.json bookmark.json bookGroup.json bookSource.json rssSources.json
/// rssStar.json replaceRule.json readRecord.json searchHistory.json
/// sourceSub.json txtTocRule.json httpTTS.json keyboardAssists.json dictRule.json
/// servers.json <reader config> <theme config> <cover config> config.xml
/// ```
///
/// Chapters, cookies, caches and RSS articles are deliberately **not** backed
/// up — they are re-downloadable, and upstream skips them too.
///
/// ## Restore semantics (these are load-bearing)
///
/// * every table except `books` is restored with insert-or-replace;
/// * `books` are **merged** — a restored row never removes a local book that
///   is not in the archive, and local books can be skipped entirely with
///   `ignoreLocalBook`;
/// * `readRecord` keeps whichever row has the newer `readTime`;
/// * `servers.json` is AES-encrypted, but a plain JSON array is accepted too
///   (that is how upstream migrates a pre-encryption backup).
///
/// ## Deliberate deviation
///
/// The JSON objects are keyed by **database column name** rather than by the
/// Kotlin property name GSON would use. The two are identical for almost every
/// field; where they differ the port is internally consistent and a plain-JSON
/// conversion is enough to exchange data with an Android backup.
public enum BackupError: Error, Equatable {
    case invalidArchive(String)
    case invalidPreferences
    case missingTable(String)
}

/// One file inside a backup archive.
public struct BackupFile: Equatable {
    public let name: String
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    public init(name: String, string: String) {
        self.init(name: name, data: Data(string.utf8))
    }

    /// The file content as UTF-8 text.
    public var string: String {
        String(decoding: data, as: UTF8.self)
    }
}

/// A finished backup, before it is written to disk or pushed to WebDAV.
public struct BackupArchive: Equatable {
    public let fileName: String
    public let files: [BackupFile]

    public init(fileName: String, files: [BackupFile]) {
        self.fileName = fileName
        self.files = files
    }

    /// Zips the files — the layout upstream writes to `tmp_backup.zip`.
    public func zip() throws -> Data {
        try ZipWriter.archive(files.map { ZipWriteEntry(name: $0.name, data: $0.data) })
    }
}

/// Settings that come from application preferences.
public struct BackupSettings: Equatable {
    /// `LocalConfig.password` — derives the key used for `servers.json`.
    public var password: String?
    /// `AppConfig.webDavDeviceName` — appended to the archive name.
    public var deviceName: String?
    /// `AppConfig.onlyLatestBackup` — forces the name `backup.zip`, so each
    /// backup overwrites the previous one on the WebDAV server.
    public var onlyLatestBackup: Bool
    /// `BackupConfig.ignoreLocalBook` — do not restore local books.
    public var ignoreLocalBook: Bool

    public init(
        password: String? = nil,
        deviceName: String? = nil,
        onlyLatestBackup: Bool = false,
        ignoreLocalBook: Bool = false
    ) {
        self.password = password
        self.deviceName = deviceName
        self.onlyLatestBackup = onlyLatestBackup
        self.ignoreLocalBook = ignoreLocalBook
    }

    var cipher: BackupCipher { BackupCipher(password: password) }
}

/// What a restore did.
public struct RestoreSummary: Equatable {
    /// Table name → restored row count.
    public var tables: [String: Int]
    /// Files that were in the archive but are not handled by this port.
    public var skipped: [String]

    public init(tables: [String: Int] = [:], skipped: [String] = []) {
        self.tables = tables
        self.skipped = skipped
    }

    /// Total restored rows.
    public var restoredRows: Int {
        tables.values.reduce(0, +)
    }
}

public enum LegadoBackup {

    /// A backup file and the table it holds.
    public struct TableFile: Equatable {
        public let fileName: String
        public let table: String

        public init(fileName: String, table: String) {
            self.fileName = fileName
            self.table = table
        }
    }

    /// The 15 table dumps, in the upstream order.
    public static let tableFiles: [TableFile] = [
        TableFile(fileName: "bookshelf.json", table: "books"),
        TableFile(fileName: "bookmark.json", table: "bookmarks"),
        TableFile(fileName: "bookGroup.json", table: "book_groups"),
        TableFile(fileName: "bookSource.json", table: "book_sources"),
        TableFile(fileName: "rssSources.json", table: "rssSources"),
        TableFile(fileName: "rssStar.json", table: "rssStars"),
        TableFile(fileName: "replaceRule.json", table: "replace_rules"),
        TableFile(fileName: "readRecord.json", table: "readRecord"),
        TableFile(fileName: "searchHistory.json", table: "search_keywords"),
        TableFile(fileName: "sourceSub.json", table: "ruleSubs"),
        TableFile(fileName: "txtTocRule.json", table: "txtTocRules"),
        TableFile(fileName: "httpTTS.json", table: "httpTTS"),
        TableFile(fileName: "keyboardAssists.json", table: "keyboardAssists"),
        TableFile(fileName: "dictRule.json", table: "dictRules"),
        TableFile(fileName: "servers.json", table: "servers")
    ]

    public static let preferencesFileName = "config.xml"

    /// The tables restored with merge semantics instead of replace.
    public static let mergedTables: Set<String> = ["books", "readRecord"]

    // MARK: - Name

    /// `"backup<yyyy-MM-dd>[-<device>].zip"`, normalised; `backup.zip` when
    /// only the latest backup is kept.
    public static func fileName(
        date: Date,
        settings: BackupSettings,
        timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    ) -> String {
        if settings.onlyLatestBackup { return "backup.zip" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        var name = "backup" + formatter.string(from: date)
        if let device = settings.deviceName, !device.isEmpty {
            name += "-" + device
        }
        return normalizeFileName(name) + ".zip"
    }

    /// Strips the characters that are illegal in a file name.
    static func normalizeFileName(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name.components(separatedBy: illegal).joined()
    }

    // MARK: - Backup

    /// Collects every file that belongs in a backup.
    ///
    /// - Parameters:
    ///   - preferences: flat preference key/value pairs (written as
    ///     `config.xml`, the way Android's SharedPreferences XML looks).
    ///   - extraFiles: files the app layer owns — reader configuration,
    ///     theme and cover configuration, downloaded rule bundles. They are
    ///     copied into the archive verbatim.
    public static func make(
        store: TableStore,
        settings: BackupSettings,
        preferences: [String: String] = [:],
        extraFiles: [BackupFile] = [],
        now: Date = Date()
    ) throws -> BackupArchive {
        var files: [BackupFile] = []
        for tableFile in tableFiles {
            let rows = try store.allRows(in: tableFile.table)
            // Upstream only writes non-empty lists.
            guard !rows.isEmpty else { continue }
            let text = try encodeRows(rows)
            if tableFile.table == "servers" {
                let cipher = settings.cipher
                // Fall back to plain JSON when encryption is unavailable —
                // upstream does the same, and a restore accepts both.
                let payload = (try? cipher.encryptBase64(text)) ?? text
                files.append(BackupFile(name: tableFile.fileName, string: payload))
            } else {
                files.append(BackupFile(name: tableFile.fileName, string: text))
            }
        }
        files.append(BackupFile(name: preferencesFileName, string: encodePreferences(preferences)))
        files.append(contentsOf: extraFiles)
        return BackupArchive(fileName: fileName(date: now, settings: settings), files: files)
    }

    // MARK: - Restore

    /// Restores a zipped backup.
    public static func restore(
        zipData: Data,
        store: TableStore,
        settings: BackupSettings
    ) throws -> RestoreSummary {
        let archive = try ZipArchive(data: zipData)
        var files: [BackupFile] = []
        for entry in archive.entries {
            files.append(BackupFile(name: entry.name, data: try archive.data(for: entry)))
        }
        return try restore(BackupArchive(fileName: "", files: files), store: store, settings: settings)
    }

    /// Restores the files of an archive. Files that are not part of the table
    /// list (reader configuration, theme, …) are reported in `summary.skipped`
    /// so the caller can apply them.
    public static func restore(
        _ archive: BackupArchive,
        store: TableStore,
        settings: BackupSettings
    ) throws -> RestoreSummary {
        var summary = RestoreSummary()
        let byName = Dictionary(archive.files.map { ($0.name, $0) }, uniquingKeysWith: { _, last in last })

        for tableFile in tableFiles {
            guard let file = byName[tableFile.fileName] else { continue }
            if file.data.isEmpty { continue }
            var text = file.string
            if tableFile.table == "servers", !looksLikeJSONArray(text) {
                text = try settings.cipher.decrypt(text)
            }
            let rows = try decodeRows(text)
            let inserted = try insert(rows, table: tableFile.table, store: store, settings: settings)
            summary.tables[tableFile.table] = inserted
        }

        let known = Set(tableFiles.map { $0.fileName }).union([preferencesFileName])
        summary.skipped = archive.files.map { $0.name }.filter { !known.contains($0) }
        return summary
    }

    /// The preference pairs of an archive, if it carries a `config.xml`.
    public static func preferences(in archive: BackupArchive) throws -> [String: String] {
        guard let file = archive.files.first(where: { $0.name == preferencesFileName }) else {
            return [:]
        }
        return try decodePreferences(file.string)
    }

    /// The preference pairs of a zipped backup — upstream `Restore.restoreConfig`.
    public static func preferences(inZipData data: Data) throws -> [String: String] {
        let archive = try ZipArchive(data: data)
        var files: [BackupFile] = []
        for entry in archive.entries {
            files.append(BackupFile(name: entry.name, data: try archive.data(for: entry)))
        }
        return try preferences(in: BackupArchive(fileName: "", files: files))
    }

    /// Writes the preferences of an archive back into the settings, skipping
    /// the ones the ignore configuration excludes — upstream
    /// `Restore.restoreConfig` + `BackupConfig.keyIsNotIgnore`.
    ///
    /// Returns the number of the restored preferences.
    @discardableResult
    public static func applyPreferences(
        _ preferences: [String: String],
        to settings: SettingsStore,
        ignore: BackupIgnoreConfig? = nil
    ) -> Int {
        var applied = 0
        for (key, value) in preferences {
            if let ignore, !ignore.shouldRestore(key) { continue }
            settings.set(value, forKey: key)
            applied += 1
        }
        return applied
    }

    // MARK: - Insertion

    private static func insert(
        _ rows: [StorageRow],
        table: String,
        store: TableStore,
        settings: BackupSettings
    ) throws -> Int {
        var inserted = 0
        try store.transaction {
            for row in rows {
                switch table {
                case "books":
                    if settings.ignoreLocalBook && isLocalBook(row) { continue }
                    // Merge: a book that is already present keeps the fields the
                    // archive does not carry (nothing, actually) but the row is
                    // never dropped from the shelf by a restore.
                    try store.insert(row, into: table)
                    inserted += 1
                case "readRecord":
                    if let existing = try store.firstRow(
                        in: table,
                        where: .equals(column: "deviceId", value: row["deviceId"] ?? .null)
                    ),
                       existing["bookName"] == row["bookName"],
                       let existingTime = existing["readTime"]?.intValue,
                       let incomingTime = row["readTime"]?.intValue,
                       existingTime > incomingTime {
                        continue
                    }
                    try store.insert(row, into: table)
                    inserted += 1
                default:
                    try store.insert(row, into: table)
                    inserted += 1
                }
            }
        }
        return inserted
    }

    private static func isLocalBook(_ row: StorageRow) -> Bool {
        let origin = row["origin"]?.stringValue ?? ""
        if origin.hasPrefix("local") || origin.hasPrefix("webDav") { return true }
        let type = row["type"]?.intValue ?? 0
        // BookType.local == 256
        return type & 256 != 0
    }

    // MARK: - JSON

    /// Encodes rows as a JSON array of objects, keeping integer and string
    /// values distinct so a round trip does not turn `1` into `"1"`.
    public static func encodeRows(_ rows: [StorageRow]) throws -> String {
        let objects: [String] = rows.map { row in
            let members: [String] = row.keys.sorted().map { key in
                "\"\(escape(key))\":\(encode(row[key] ?? .null))"
            }
            return "{" + members.joined(separator: ",") + "}"
        }
        return "[" + objects.joined(separator: ",") + "]"
    }

    /// Decodes the rows of a table dump. An empty list yields no rows, and a
    /// non-array document is rejected so a corrupt file cannot wipe a table.
    public static func decodeRows(_ text: String) throws -> [StorageRow] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        guard trimmed.first == "[" else {
            throw BackupError.invalidArchive("expected a JSON array")
        }
        let value = try JSONValue.parse(trimmed)
        guard case let .array(items) = value else {
            throw BackupError.invalidArchive("expected a JSON array")
        }
        return items.compactMap { item in
            guard case let .object(members) = item else { return nil }
            var row: StorageRow = [:]
            for (key, value) in members { row[key] = storageValue(value) }
            return row
        }
    }

    private static func storageValue(_ value: JSONValue) -> StorageValue {
        switch value {
        case .null: return .null
        case .bool(let flag): return .integer(flag ? 1 : 0)
        case .number(let number):
            if number.rounded() == number, abs(number) < 9.0e15 {
                return .integer(Int64(number))
            }
            return .real(number)
        case .string(let text): return .text(text)
        case .array, .object:
            // Nested structures are stored as their JSON text, matching how
            // Room columns hold serialised rule objects.
            return .text(value.jsonString)
        }
    }

    private static func encode(_ value: StorageValue) -> String {
        switch value {
        case .null: return "null"
        case .integer(let number): return String(number)
        case .real(let number):
            return number == number.rounded() && abs(number) < 9.0e15
                ? String(Int64(number))
                : String(number)
        case .text(let text): return "\"\(escape(text))\""
        case .blob(let data): return "\"\(escape(data.base64EncodedString()))\""
        }
    }

    private static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count + 8)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }

    private static func looksLikeJSONArray(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
    }

    // MARK: - Preferences (config.xml)

    /// Writes the Android `SharedPreferences` XML shape, so the file is still
    /// recognisable to the Android app.
    public static func encodePreferences(_ preferences: [String: String]) -> String {
        var lines = ["<?xml version='1.0' encoding='utf-8' standalone='yes' ?>", "<map>"]
        for key in preferences.keys.sorted() {
            let value = preferences[key] ?? ""
            lines.append("    <string name=\"\(escapeXML(key))\">\(escapeXML(value))</string>")
        }
        lines.append("</map>")
        return lines.joined(separator: "\n")
    }

    /// Parses `<string name="key">value</string>` lines.
    public static func decodePreferences(_ xml: String) throws -> [String: String] {
        guard xml.contains("<map") else { throw BackupError.invalidPreferences }
        let pattern = "<string[^>]*name=\"([^\"]*)\"[^>]*>(.*?)</string>"
        let regex = try NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
        let ns = xml as NSString
        var result: [String: String] = [:]
        for match in regex.matches(in: xml, options: [], range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges > 2 else { continue }
            let key = unescapeXML(ns.substring(with: match.range(at: 1)))
            let value = unescapeXML(ns.substring(with: match.range(at: 2)))
            result[key] = value
        }
        return result
    }

    private static func escapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func unescapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
