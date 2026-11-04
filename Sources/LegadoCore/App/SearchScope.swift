//
//  SearchScope.swift
//  LegadoCore
//
//  The scope of a search.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/book/search/SearchScope.kt
//  app/src/main/java/io/legado/app/model/webBook/SearchModel.kt
//

import Foundation

/// The scope of a search — upstream `SearchScope`.
///
/// The scope is a string:
///
/// * an empty string — every enabled source,
/// * a comma separated list of the groups of the sources,
/// * `sourceName::sourceUrl` — a single source.
public struct SearchScope: Equatable {

    /// The scope of every source.
    public static let all = SearchScope(scope: "")

    /// The raw preference key of the scope — upstream `AppConfig.searchScope`
    /// (`app/src/main/java/io/legado/app/help/config/AppConfig.kt:521-524`).
    public static let scopeKey = "searchScope"

    /// The raw preference key of the single group of the scope — upstream
    /// `AppConfig.searchGroup` (`AppConfig.kt:527-530`).
    public static let groupKey = "searchGroup"

    /// The raw scope.
    public var scope: String

    public init(scope: String) {
        self.scope = scope
    }

    /// The scope of a single source — upstream `SearchScope("name::url")`.
    public init(source: BookSource) {
        self.scope = "\(source.bookSourceName)::\(source.bookSourceUrl)"
    }

    /// Whether the scope is a single source — upstream `SearchScope.isSource`.
    public var isSource: Bool { scope.contains("::") }

    /// Whether the scope covers every source — upstream `SearchScope.isAll`.
    public var isAll: Bool { scope.isEmpty }

    /// The name of the source of a single source scope — upstream
    /// `SearchScope.display`.
    public var sourceName: String? {
        guard isSource else { return nil }
        let parts = scope.components(separatedBy: "::")
        return parts.first?.trimmingCharacters(in: .whitespaces)
    }

    /// The groups of the scope — upstream `SearchScope.displayNames`.
    public var groupNames: [String] {
        guard !isSource else { return [] }
        return scope
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The title of the scope — upstream `SearchScope.display`.
    public var display: String {
        if isSource { return sourceName ?? scope }
        if isAll { return "全部书源" }
        return groupNames.joined(separator: ",")
    }

    /// Removes a group from the scope — upstream `SearchScope.remove`.
    ///
    /// The scope of a single source is cleared, a group is dropped.
    public func removing(_ name: String) -> SearchScope {
        if isSource { return SearchScope.all }
        let rest = groupNames.filter { $0 != name }
        return SearchScope(scope: rest.joined(separator: ","))
    }

    /// The sources of the scope — upstream `SearchScope.getBookSourceParts`.
    ///
    /// Every enabled source when the scope is empty, the source itself when
    /// the scope is a source, the enabled sources of the groups otherwise.
    /// When the groups hold no enabled source every enabled source is used.
    public func sources(from all: [BookSource]) -> [BookSource] {
        let enabled = all.filter { $0.enabled }
        if isSource {
            let url = scope.components(separatedBy: "::").dropFirst().joined(separator: "::")
            return all.filter { $0.bookSourceUrl == url }
        }
        if isAll { return sorted(enabled) }
        let groups = groupNames
        let matched = enabled.filter { source in
            groups.contains { source.hasGroup($0) }
        }
        return sorted(matched.isEmpty ? enabled : matched)
    }

    /// The sources of the scope, sorted by the custom order — upstream
    /// `SearchScope.getBookSourceParts` (`sortedBy { it.customOrder }`).
    private func sorted(_ sources: [BookSource]) -> [BookSource] {
        sources.sorted { $0.customOrder < $1.customOrder }
    }
}

public extension AppSettings {

    /// The scope of the search — upstream `AppConfig.searchScope`.
    ///
    /// The upstream stores the scope under the raw preference key
    /// "searchScope" (it is not a `PreferKey` constant, so the port reads it
    /// through the settings store directly).
    var searchScope: SearchScope {
        SearchScope(scope: settingsStore.string(forKey: SearchScope.scopeKey) ?? "")
    }

    /// Sets the scope of the search — upstream `SearchScope.save()`.
    ///
    /// The scope is written to "searchScope"; the single group of the scope
    /// is also written to "searchGroup" (the upstream keeps the group there
    /// for the change-source screen).
    func setSearchScope(_ scope: SearchScope) {
        settingsStore.set(scope.scope, forKey: SearchScope.scopeKey)
        let isSingleGroup = !scope.isAll && !scope.isSource && scope.groupNames.count == 1
        settingsStore.set(isSingleGroup ? scope.scope : "", forKey: SearchScope.groupKey)
    }

    /// The group of the change-source screen — upstream
    /// `AppConfig.searchGroup` (`AppConfig.kt:527-530`).
    ///
    /// The upstream keeps the group of the search scope here so that the
    /// change-source dialog can be scoped to it.
    var searchGroup: String {
        get { settingsStore.string(forKey: SearchScope.groupKey) ?? "" }
        set { settingsStore.set(newValue, forKey: SearchScope.groupKey) }
    }
}

/// The merge of the results of a search — upstream `SearchModel.mergeItems`.
public enum SearchResultMerge {
    /// Merges the results of the sources of a search — upstream
    /// `SearchModel.mergeItems(newDataS, precision)`.
    ///
    /// The books whose name or author are the keyword come first, then the
    /// books that only contain the keyword and — when the search is not
    /// precise — the rest. The books with the same name and author are
    /// merged into one and the origins of the merged books are collected
    /// (upstream `pBook.addOrigin(nBook.origin)`); the books are sorted by
    /// the number of their origins (upstream `sortByDescending { it.origins.size }`).
    public static func merge(
        _ books: [SearchBook],
        keyword: String,
        precision: Bool
    ) -> [SearchBook] {
        // The books with the same name and author are merged into the first
        // one; the order of the books is kept.
        var order: [String] = []
        var merged: [String: SearchBook] = [:]

        for book in books {
            let key = "\(book.name)\u{1}\(book.author)"
            if var existing = merged[key] {
                // Upstream `addOrigin` — the origins are unique and keep
                // their order.
                if !existing.origins.contains(book.origin) {
                    existing.origins.append(book.origin)
                    merged[key] = existing
                }
            } else {
                var copy = book
                copy.origins = [book.origin]
                merged[key] = copy
                order.append(key)
            }
        }

        var equal: [SearchBook] = []
        var contains: [SearchBook] = []
        var other: [SearchBook] = []

        for key in order {
            guard let book = merged[key] else { continue }
            if book.name == keyword || book.author == keyword {
                equal.append(book)
            } else if book.name.contains(keyword) || book.author.contains(keyword) {
                contains.append(book)
            } else {
                other.append(book)
            }
        }

        var result = sortedByOrigins(equal)
        result.append(contentsOf: sortedByOrigins(contains))
        if !precision {
            result.append(contentsOf: other)
        }
        return result
    }

    /// Sorts the books by the number of their origins — upstream
    /// `sortByDescending { it.origins.size }` (a stable sort).
    private static func sortedByOrigins(_ books: [SearchBook]) -> [SearchBook] {
        books.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.origins.count != rhs.element.origins.count {
                    return lhs.element.origins.count > rhs.element.origins.count
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}
