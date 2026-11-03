//
//  RssSourceImport.swift
//  LegadoCore
//
//  The import of the RSS sources.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/association/ImportRssSourceViewModel.kt
//

import Foundation

/// The import of the RSS sources — upstream `ImportRssSourceViewModel`.
///
/// The upstream accepts
///
/// * a JSON object with a `sourceUrls` member — the URLs are downloaded,
/// * a JSON array of `RssSource` objects,
/// * a single `RssSource` object,
/// * an absolute URL — the document is downloaded and parsed,
/// * the content of a local file.
public enum RssSourceImport {

    /// The errors of the import.
    public enum ImportError: Error, Equatable {
        /// The document is not a JSON array of the RSS sources.
        case notAnArray
        /// The document does not hold any RSS source.
        case notAnRssSource
        /// The document is not JSON at all.
        case wrongFormat
    }

    /// The RSS sources of a JSON document — upstream
    /// `ImportRssSourceViewModel.importSourceAwait` (the JSON branches).
    ///
    /// The upstream rejects a document whose first source has an empty
    /// `sourceUrl` ("不是订阅源").
    public static func sources(json: String) throws -> [RssSource] {
        let value = try JSONValue.parse(json)
        let array: [JSONValue]
        switch value {
        case .array(let items): array = items
        case .object: array = [value]
        default: throw ImportError.wrongFormat
        }
        var sources: [RssSource] = []
        for item in array {
            if let source = RssSourceJSONBridge.decode(item) { sources.append(source) }
        }
        guard let first = sources.first else { throw ImportError.notAnRssSource }
        guard !first.sourceUrl.isEmpty else { throw ImportError.notAnRssSource }
        return sources
    }

    /// The source URLs of a JSON object with a `sourceUrls` member — upstream
    /// `ImportRssSourceViewModel.importSourceAwait` (the `sourceUrls` branch).
    public static func sourceURLs(json: String) throws -> [String] {
        let value = try JSONValue.parse(json)
        guard let object = value.objectValue,
              let urls = object["sourceUrls"]?.arrayValue else { return [] }
        return urls.compactMap { $0.stringValue }.filter { !$0.isEmpty }
    }

    /// Whether a text is an absolute URL — upstream `isAbsUrl`.
    public static func isAbsoluteURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard let url = URL(string: trimmed) else { return false }
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
