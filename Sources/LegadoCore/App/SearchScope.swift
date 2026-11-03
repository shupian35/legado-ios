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

/// The merge of the results of a search — upstream `SearchModel.mergeItems`.
public enum SearchResultMerge {

    /// Merges the results of the sources of a search — upstream
    /// `SearchModel.mergeItems(newDataS, precision)`.
    ///
    /// The books whose name or author are the keyword come first, then the
    /// books that only contain the keyword and — when the search is not
    /// precise — the rest. The books with the same name and author are
    /// merged into one.
    public static func merge(
        _ books: [SearchBook],
        keyword: String,
        precision: Bool
    ) -> [SearchBook] {
        var equal: [SearchBook] = []
        var contains: [SearchBook] = []
        var other: [SearchBook] = []
        // The position of every known book — the books with the same name
        // and author are merged into the first one (upstream
        // `pBook.addOrigin(nBook.origin)`).
        var index: [String: (Int, Int)] = [:]

        for book in books {
            let key = "\(book.name)\u{1}\(book.author)"
            if index[key] != nil { continue }
            if book.name == keyword || book.author == keyword {
                index[key] = (0, equal.count)
                equal.append(book)
            } else if book.name.contains(keyword) || book.author.contains(keyword) {
                index[key] = (1, contains.count)
                contains.append(book)
            } else {
                index[key] = (2, other.count)
                other.append(book)
            }
        }

        var result = equal
        result.append(contentsOf: contains)
        if !precision {
            result.append(contentsOf: other)
        }
        return result
    }
}
