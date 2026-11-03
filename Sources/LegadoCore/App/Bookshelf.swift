//
//  Bookshelf.swift
//  LegadoCore
//
//  The bookshelf logic of the app shell:
//
//  · `ui/main/bookshelf/style1/books/BooksFragment.kt` — the sort of the books.
//  · `data/dao/BookDao.kt`                    — the book queries.
//  · `data/dao/BookGroupDao.kt`               — the visible groups.
//
//  The logic lives in `LegadoCore` so that it can be unit tested on Linux;
//  the SwiftUI shell only renders what this model returns.
//
//

import Foundation

/// The sort order of the bookshelf — upstream `BooksFragment.upRecyclerData`.
///
/// The raw values are the upstream `bookSort` values, they are stored in the
/// preference `bookshelfSort` and in the `bookSort` column of a group.
public enum BookshelfSort: Int, CaseIterable, Sendable {
    /// 0 — the default, the book that was read last comes first.
    case byDuration = 0
    /// 1 — the book with the newest chapter comes first.
    case byLatest = 1
    /// 2 — by name.
    case byName = 2
    /// 3 — by the manual order.
    case byOrder = 3
    /// 4 — 综合排序, the newest of both times (upstream issue #3192).
    case byMixed = 4
    /// 5 — by author.
    case byAuthor = 5

    /// The upstream name of the sort, used by the settings UI.
    public var name: String {
        switch self {
        case .byDuration: return "最近阅读"
        case .byLatest: return "最新更新"
        case .byName: return "书名排序"
        case .byOrder: return "手动排序"
        case .byMixed: return "综合排序"
        case .byAuthor: return "作者排序"
        }
    }

    /// Sorts the books — upstream `BooksFragment.upRecyclerData`.
    public func sort(_ books: [Book]) -> [Book] {
        switch self {
        case .byDuration:
            return books.sorted { $0.durChapterTime > $1.durChapterTime }
        case .byLatest:
            return books.sorted { $0.latestChapterTime > $1.latestChapterTime }
        case .byName:
            return books.sorted { TextComparison.isOrderedBefore($0.name, $1.name) }
        case .byOrder:
            return books.sorted { $0.order < $1.order }
        case .byMixed:
            return books.sorted {
                max($0.latestChapterTime, $0.durChapterTime) > max($1.latestChapterTime, $1.durChapterTime)
            }
        case .byAuthor:
            return books.sorted { TextComparison.isOrderedBefore($0.author, $1.author) }
        }
    }
}

/// The string comparison of the bookshelf.
///
/// Upstream uses `cnCompare`, a pinyin aware collation, so that the Chinese
/// titles are ordered by their pronunciation. A pinyin table is not part of
/// the port, so the comparison falls back to a case and diacritic insensitive
/// Unicode comparison — the ordering of the Latin titles is the same, the
/// ordering of the Chinese titles follows the code points.
public enum TextComparison {
    public static func isOrderedBefore(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return false }
        let left = lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
        if left != .orderedSame { return left == .orderedAscending }
        // A stable tie breaker so that the order does not depend on the sort
        // implementation.
        return lhs < rhs
    }
}

/// The bookshelf of the app — upstream `BookshelfViewModel`.
///
/// The model owns the queries; the views only ask it for the books of the
/// selected group and for the list of the visible groups.
public struct BookshelfModel {
    private let store: LegadoStore

    public init(store: LegadoStore) {
        self.store = store
    }

    /// The groups the bookshelf shows — upstream `BookGroupDao.show`.
    public func visibleGroups() throws -> [BookGroup] {
        try store.visibleGroups()
    }

    /// The books of a group — upstream `BookDao.flowByGroup` plus the sort.
    public func books(inGroup groupId: Int64, sort: BookshelfSort) throws -> [Book] {
        try sort.sort(store.books(inGroup: groupId))
    }

    /// The books of a group with the sort of the group — upstream
    /// `AppConfig.getBookSortByGroupId`.
    public func books(inGroup groupId: Int64, settings: AppSettings) throws -> [Book] {
        let sortValue = try groupSort(for: groupId, settings: settings)
        let sort = BookshelfSort(rawValue: sortValue) ?? .byDuration
        return try books(inGroup: groupId, sort: sort)
    }

    /// The sort of a group — upstream `AppConfig.getBookSortByGroupId`.
    public func groupSort(for groupId: Int64, settings: AppSettings) throws -> Int {
        if let group = try store.allGroups().first(where: { $0.groupId == groupId }) {
            return settings.bookSort(forGroup: group)
        }
        return settings.bookshelfSort
    }

    /// The books whose name or author contains the keyword — upstream
    /// `BookDao.flowSearch`.
    public func search(_ keyword: String) throws -> [Book] {
        guard !keyword.isEmpty else { return [] }
        let books = try store.allBooks()
        return books.filter {
            $0.name.range(of: keyword, options: [.caseInsensitive]) != nil
                || $0.author.range(of: keyword, options: [.caseInsensitive]) != nil
        }
    }

    /// The last read book — upstream `BookDao.lastReadBook`.
    public func lastReadBook() throws -> Book? {
        try store.lastReadBook()
    }
}
