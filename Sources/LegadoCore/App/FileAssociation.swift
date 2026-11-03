//
//  FileAssociation.swift
//  LegadoCore
//
//  The port of
//  `app/src/main/java/io/legado/app/ui/association/FileAssociationViewModel.kt`.
//
//  Upstream `dispatchIntent` decides what a file that is opened with the app
//  is: an archive (it is unpacked and every book inside is dispatched), a
//  JSON document (the kind is detected and the import dialog is shown), a
//  book file (it is imported as a local book) or an unsupported file.
//

import Foundation

/// What a file that is opened with the app is.
public enum FileAssociationKind: Equatable, Sendable {
    /// A local book (txt / epub / umd / pdf / mobi / azw).
    case book
    /// A JSON document with a book source, an RSS source, a replace rule, …
    case json
    /// An archive that may contain books.
    case archive
    /// Anything else.
    case unsupported
}

/// The file association rules.
public enum FileAssociation {

    /// The upstream book file extensions — `AppPattern.bookFileRegex`
    /// (`constant/AppPattern.kt:28`): `txt|epub|umd|pdf|mobi|azw3|azw`.
    public static let bookExtensions: Set<String> = ["txt", "epub", "umd", "pdf", "mobi", "azw3", "azw"]

    /// The upstream archive extensions — `AppPattern.archiveFileRegex`
    /// (`constant/AppPattern.kt:26`): `zip|rar|7z`.
    public static let archiveExtensions: Set<String> = ["zip", "rar", "7z"]

    /// The extension of a file name (lower cased, without the dot).
    public static func fileExtension(of fileName: String) -> String {
        let name = (fileName as NSString).lastPathComponent
        let ext = (name as NSString).pathExtension
        return ext.lowercased()
    }

    /// Whether the content looks like JSON — upstream `InputStream.isJson()`.
    ///
    /// The upstream checks the first non-whitespace character for `{` or `[`.
    public static func looksLikeJSON(_ data: Data) -> Bool {
        guard let text = String(data: data, encoding: .utf8) else { return false }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
    }

    /// Decides what the file is.
    ///
    /// The upstream first tries the JSON detection (the content wins over the
    /// name), then the book file name, then the archive name.
    public static func kind(fileName: String, content: Data?) -> FileAssociationKind {
        if let content, looksLikeJSON(content) {
            return .json
        }
        let ext = fileExtension(of: fileName)
        if bookExtensions.contains(ext) {
            return .book
        }
        if archiveExtensions.contains(ext) {
            return .archive
        }
        return .unsupported
    }

    /// The import kind of a JSON document — the upstream `importJson` detects
    /// the kind from the fields of the first object.
    public static func importKind(ofJSON json: String) -> ImportKind? {
        try? DeepLink.detectKind(json: json)
    }
}
