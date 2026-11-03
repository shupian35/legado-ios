//
//  RemoteImport.swift
//  LegadoCore
//
//  The port of
//  app/src/main/java/io/legado/app/ui/association/ImportBookSourceViewModel.kt,
//  ImportRssSourceViewModel.kt and ImportReplaceRuleViewModel.kt — the import
//  of the rules from a remote address. The upstream accepts a pasted JSON, a
//  JSON document with a `sourceUrls` array or a plain address, and the
//  subscription screen (ui/rss/subscription/RuleSubActivity.kt) reuses the
//  same code with a stored address.
//
//

import Foundation

/// The import of the rules from a remote address.
public enum RemoteImport {

    /// The errors of an import.
    public enum ImportError: Error, Equatable, Sendable {
        /// The text is neither JSON nor an address.
        case wrongFormat
        /// The address answered with nothing.
        case empty
        /// The address answered with an error status.
        case http(Int)
        /// The document contained no rule of the expected kind.
        case noValidRule(ImportKind)
    }

    /// The kind of the rules a subscription imports.
    ///
    /// Upstream `RuleSub.type`: 0 = a book source, 1 = an RSS source,
    /// 2 = a replace rule.
    public enum SubscriptionKind: Int, Equatable, CaseIterable, Sendable {
        case bookSource = 0
        case rssSource = 1
        case replaceRule = 2

        /// The import kind of the subscription.
        public var importKind: ImportKind {
            switch self {
            case .bookSource: return .bookSource
            case .rssSource: return .rssSource
            case .replaceRule: return .replaceRule
            }
        }

        /// The title of the subscription kind (the upstream dialog title).
        public var title: String {
            switch self {
            case .bookSource: return "书源"
            case .rssSource: return "RSS源"
            case .replaceRule: return "替换规则"
            }
        }
    }

    /// Downloads the text of an address.
    ///
    /// Upstream `importSourceUrl`: an address that ends with
    /// `#requestWithoutUA` is fetched without the user agent.
    public static func fetchText(
        from url: String,
        httpClient: HttpClient,
        userAgent: String = AppSettings.defaultUserAgent
    ) async throws -> String {
        var target = url
        var headers: [String: String] = [:]
        if target.hasSuffix(DeepLink.requestWithoutUserAgent) {
            target = String(target.dropLast(DeepLink.requestWithoutUserAgent.count))
            headers["User-Agent"] = "null"
        } else {
            headers["User-Agent"] = userAgent
        }
        let response = try await httpClient.send(HttpRequest(url: target, headers: headers))
        guard response.isSuccessful else {
            throw ImportError.http(response.code)
        }
        guard let text = response.body ?? response.data.map({ String(decoding: $0, as: UTF8.self) }) else {
            throw ImportError.empty
        }
        return text
    }

    /// The addresses of a JSON document with a `sourceUrls` array.
    ///
    /// Upstream `JsonPath.parse(mText).read<List<String>>("$.sourceUrls")`.
    public static func sourceURLs(in text: String) -> [String] {
        guard let value = try? JSONValue.parse(text) else { return [] }
        guard case .object = value else { return [] }
        guard let list = JSONPath.read("$.sourceUrls", in: value) else { return [] }
        switch list {
        case .array(let items):
            return items.compactMap { $0.stringValue }
        case .string(let single):
            return [single]
        default:
            return []
        }
    }

    /// Imports the rules of a text.
    ///
    /// The text is either a JSON document (an array or a single object), a
    /// JSON document with a `sourceUrls` array or a plain address. Upstream
    /// `importSource` / `importSourceAwait`.
    ///
    /// - Parameters:
    ///   - text: the text to import.
    ///   - kind: the kind of the rules; `nil` detects it from the document.
    ///   - httpClient: the transport.
    ///   - store: the database the rules are written to.
    /// - Returns: the number of imported rules.
    @discardableResult
    public static func importText(
        _ text: String,
        kind: SubscriptionKind?,
        httpClient: HttpClient,
        store: LegadoStore
    ) async throws -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.wrongFormat }

        // A plain address.
        if isAbsoluteURL(trimmed) {
            let body = try await fetchText(from: trimmed, httpClient: httpClient)
            return try await importText(body, kind: kind, httpClient: httpClient, store: store)
        }

        // A document with a list of addresses.
        let urls = sourceURLs(in: trimmed)
        if !urls.isEmpty {
            var count = 0
            for url in urls {
                let body = try await fetchText(from: url, httpClient: httpClient)
                count += try await importText(body, kind: kind, httpClient: httpClient, store: store)
            }
            return count
        }

        // A JSON document.
        guard let value = try? JSONValue.parse(trimmed) else {
            throw ImportError.wrongFormat
        }
        let importKind: ImportKind
        if let kind {
            importKind = kind.importKind
        } else {
            importKind = try DeepLink.detectKind(json: trimmed)
        }
        let summary = try DeepLink.importJSON(trimmed, kind: importKind, store: store)
        guard summary.count > 0 else { throw ImportError.noValidRule(importKind) }
        return summary.count
    }

    /// Imports the rules of an address — the flow of the subscription screen.
    ///
    /// Upstream `RuleSubActivity.openSubscription` opens the import dialog
    /// with the stored address.
    @discardableResult
    public static func importSubscription(
        _ sub: RuleSub,
        httpClient: HttpClient,
        store: LegadoStore
    ) async throws -> Int {
        let kind = SubscriptionKind(rawValue: Int(sub.type)) ?? .bookSource
        return try await importText(sub.url, kind: kind, httpClient: httpClient, store: store)
    }

    /// Whether the text is an absolute address.
    ///
    /// Upstream `String.isAbsUrl()`.
    public static func isAbsoluteURL(_ text: String) -> Bool {
        let lower = text.lowercased()
        guard let scheme = lower.range(of: "://") else { return false }
        let name = String(lower[lower.startIndex..<scheme.lowerBound])
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" || $0 == "." }) else {
            return false
        }
        return lower[scheme.upperBound...].contains("/") || lower[scheme.upperBound...].contains(".")
    }
}
