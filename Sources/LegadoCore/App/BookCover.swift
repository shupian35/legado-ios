//
//  BookCover.swift
//  LegadoCore
//
//  Port of `app/src/main/java/io/legado/app/model/BookCover.kt`.
//
//  The cover rule searches the cover of a book with a search URL and a rule;
//  the configuration lives in the cache under `legadoCoverRuleConfig` (the
//  upstream's `CacheManager`).
//

import Foundation

// MARK: - The rule

/// The cover rule — upstream `BookCover.CoverRule`.
///
/// The rule is a `BaseSource` upstream, so it can carry a header, a login and
/// a rate limit.
public struct CoverRule: Codable, Equatable, Sendable {
    /// Whether the cover search is enabled.
    public var enable: Bool
    /// The search URL — the book name replaces the `key` placeholder.
    public var searchUrl: String
    /// The rule that extracts the cover URL out of the search result.
    public var coverRule: String
    /// The concurrent rate — upstream `BaseSource.concurrentRate`.
    public var concurrentRate: String?
    /// The login URL — upstream `BaseSource.loginUrl`.
    public var loginUrl: String?
    /// The login UI — upstream `BaseSource.loginUi`.
    public var loginUi: String?
    /// The header rule — upstream `BaseSource.header`.
    public var header: String?
    /// The JavaScript library — upstream `BaseSource.jsLib`.
    public var jsLib: String?
    /// Whether the cookie jar is enabled — upstream `BaseSource.enabledCookieJar`.
    public var enabledCookieJar: Bool

    public init(
        enable: Bool = true,
        searchUrl: String = "",
        coverRule: String = "",
        concurrentRate: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        header: String? = nil,
        jsLib: String? = nil,
        enabledCookieJar: Bool = false
    ) {
        self.enable = enable
        self.searchUrl = searchUrl
        self.coverRule = coverRule
        self.concurrentRate = concurrentRate
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.header = header
        self.jsLib = jsLib
        self.enabledCookieJar = enabledCookieJar
    }

    /// The default rule — upstream `DefaultData.coverRule`.
    public static let `default` = CoverRule(enable: false, searchUrl: "", coverRule: "")

    /// The JSON of the rule — upstream `GSON.toJson(config)`.
    public var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    /// Parses the rule — upstream `GSON.fromJsonObject<CoverRule>`.
    public static func parse(_ json: String) -> CoverRule? {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let data = trimmed.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(CoverRule.self, from: data)
    }
}

extension CoverRule: AnalyzeSource {
    /// The unique key of the rule — upstream `BaseSource.getKey()`.
    public var key: String { searchUrl }

    /// The tag of the rule — upstream `BaseSource.getTag()`.
    public var tag: String { searchUrl }

    /// Parse the header rule — upstream `BaseSource.getHeaderMap`.
    public func headerMap(
        hasLoginHeader: Bool = false,
        scriptEngine: RuleScriptEngine? = nil,
        userAgent: String = SourceSupport.defaultUserAgent,
        loginHeaderMap: [String: String]? = nil
    ) -> [String: String] {
        SourceSupport.headerMap(
            header: header,
            hasLoginHeader: hasLoginHeader,
            scriptEngine: scriptEngine,
            userAgent: userAgent,
            loginHeaderMap: loginHeaderMap
        )
    }
}

// MARK: - The service

/// The cover service — upstream `BookCover`.
public enum BookCoverService {

    /// The key of the configuration in the cache — upstream `coverRuleConfigKey`.
    public static let configCacheKey = "legadoCoverRuleConfig"

    /// The name of the exported configuration file — upstream `configFileName`.
    public static let configFileName = "coverRule.json"

    /// Reads the configuration — upstream `BookCover.getCoverRule`.
    ///
    /// The configuration lives in the cache; the default rule is used when
    /// there is none.
    public static func config(store: LegadoStore, now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> CoverRule {
        guard let json = try? store.cache(configCacheKey, now: now),
            let rule = CoverRule.parse(json) else {
            return .default
        }
        return rule
    }

    /// Stores the configuration — upstream `BookCover.saveCoverRule`.
    public static func save(_ config: CoverRule, store: LegadoStore) throws {
        try store.putCache(configCacheKey, value: config.jsonString, deadline: 0)
    }

    /// Removes the configuration — upstream `BookCover.delCoverRule`.
    public static func delete(store: LegadoStore) throws {
        try store.deleteCache(configCacheKey)
    }

    /// Searches the cover of a book — upstream `BookCover.searchCover`.
    ///
    /// The search URL receives the name of the book as its key; the rule
    /// extracts the cover URL out of the answer.
    public static func searchCover(
        book: Book,
        config: CoverRule,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> String? {
        guard config.enable,
            !config.searchUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !config.coverRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let analyzeUrl = AnalyzeUrl(
            url: config.searchUrl,
            key: book.name,
            source: config,
            hasLoginHeader: false,
            dependencies: dependencies
        )
        let response = try await analyzeUrl.strResponse()
        let analyzeRule = AnalyzeRule()
        try analyzeRule.setContent(.text(response.body ?? ""))
        analyzeRule.setRedirectUrl(response.url ?? "")
        let cover = try analyzeRule.getString(config.coverRule, isUrl: true)
        return cover.isEmpty ? nil : cover
    }
}

// MARK: - The cover source search

/// A cover that was found by searching the sources — upstream
/// `ChangeCoverViewModel`'s `SearchBook` entries.
public struct CoverSearchResult: Equatable, Identifiable, Sendable {
    /// The URL of the cover.
    public let coverUrl: String
    /// The name of the source that found it.
    public let originName: String
    /// The order of the source — the results are sorted by it.
    public let originOrder: Int64

    public init(coverUrl: String, originName: String, originOrder: Int64) {
        self.coverUrl = coverUrl
        self.originName = originName
        self.originOrder = originOrder
    }

    public var id: String { coverUrl }
}

public extension BookCoverService {

    /// Searches the covers of a book in the sources — upstream
    /// `ChangeCoverViewModel.search`.
    ///
    /// Only the sources whose search rule has a cover URL are used; the first
    /// result of each source is taken and it is kept only when the name and
    /// the author match the book exactly (the upstream's
    /// `searchBook.name == name && searchBook.author == author`).
    static func searchCovers(
        book: Book,
        sources: [BookSource],
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async -> [CoverSearchResult] {
        let name = book.name
        let author = ChangeSourceService.sanitizedAuthor(book.author)
        var results: [CoverSearchResult] = []
        for source in sources where source.enabled {
            guard let coverRule = source.searchRule?.coverUrl,
                !coverRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            do {
                let books = try await WebBook.searchBook(
                    bookSource: source,
                    key: name,
                    shouldBreak: { $0 > 0 },
                    dependencies: dependencies
                )
                guard let hit = books.first else { continue }
                guard hit.name == name, hit.author == author else { continue }
                let coverUrl = hit.coverUrl ?? ""
                guard !coverUrl.isEmpty else { continue }
                results.append(
                    CoverSearchResult(
                        coverUrl: coverUrl,
                        originName: source.bookSourceName,
                        originOrder: source.customOrder
                    )
                )
            } catch {
                // The upstream logs the failure and carries on with the next
                // source (`AppLog.put("封面换源搜索出错…")`).
                continue
            }
        }
        return results.sorted { $0.originOrder < $1.originOrder }
    }
}
