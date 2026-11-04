//
//  ImportUrlHistory.swift
//  LegadoCore
//
//  The history of the urls the documents were imported from.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/book/source/manage/BookSourceActivity.kt:585-614
//  app/src/main/java/io/legado/app/ui/rss/source/manage/RssSourceActivity.kt:350-375
//  app/src/main/java/io/legado/app/ui/replace/ReplaceRuleActivity.kt:270-300
//  app/src/main/java/io/legado/app/ui/dict/rule/DictRuleActivity.kt:205-235
//
//  The upstream keeps the urls in the `ACache` (a cache file, not the
//  preferences) as one comma separated string; the newest url is at the
//  front and an url that is already in the list is not added twice.
//

import Foundation

/// The history of the imported urls — upstream `ACache` + `importRecordKey`.
public enum ImportUrlHistory {

    /// The cache key of the history of every kind of import — upstream
    /// `importRecordKey`.
    public enum Kind: String, CaseIterable, Sendable {

        /// The book sources — upstream `BookSourceActivity.importRecordKey`.
        case bookSource = "bookSourceRecordKey"

        /// The RSS sources — upstream `RssSourceActivity.importRecordKey`.
        case rssSource = "rssSourceRecordKey"

        /// The replace rules — upstream `ReplaceRuleActivity.importRecordKey`.
        case replaceRule = "replaceRuleRecordKey"

        /// The dictionary rules — upstream `DictRuleActivity.importRecordKey`.
        case dictRule = "dictRuleUrls"

        /// The kind of the book sources — the port's `ImportKind`.
        public init?(importKind: ImportKind) {
            switch importKind {
            case .bookSource: self = .bookSource
            case .rssSource: self = .rssSource
            case .replaceRule: self = .replaceRule
            case .dictRule: self = .dictRule
            default: return nil
            }
        }
    }

    /// The urls of the history — upstream
    /// `aCache.getAsString(importRecordKey)?.splitNotBlank(",")`.
    public static func urls(_ kind: Kind, store: LegadoStore) -> [String] {
        guard let raw = try? store.cache(kind.rawValue, now: 0) else { return [] }
        return split(raw)
    }

    /// Adds an url to the history — upstream
    /// `if (it.isAbsUrl() && !cacheUrls.contains(it)) { cacheUrls.add(0, it) }`.
    ///
    /// The url is only kept when it is an absolute url that is not in the
    /// list yet; it becomes the newest entry.
    @discardableResult
    public static func add(_ url: String, _ kind: Kind, store: LegadoStore) -> [String] {
        var urls = urls(kind, store: store)
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAbsoluteURL(trimmed), !urls.contains(trimmed) else { return urls }
        urls.insert(trimmed, at: 0)
        save(urls, kind, store: store)
        return urls
    }

    /// Removes an url from the history — upstream
    /// `editView.delCallBack { cacheUrls.remove(it) }`.
    @discardableResult
    public static func remove(_ url: String, _ kind: Kind, store: LegadoStore) -> [String] {
        var urls = urls(kind, store: store)
        urls.removeAll { $0 == url }
        save(urls, kind, store: store)
        return urls
    }

    /// Writes the history — upstream `aCache.put(importRecordKey, …)`.
    public static func save(_ urls: [String], _ kind: Kind, store: LegadoStore) {
        try? store.putCache(kind.rawValue, value: urls.joined(separator: ","), deadline: 0)
    }

    /// Splits the raw value — upstream `splitNotBlank(",")`.
    static func split(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Whether the text is an absolute url — upstream `String.isAbsUrl()`.
    static func isAbsoluteURL(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
