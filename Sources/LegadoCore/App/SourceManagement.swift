//
//  SourceManagement.swift
//  LegadoCore
//
//  The ordering and the selection of the book sources.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/book/source/manage/BookSourceAdapter.kt
//  app/src/main/java/io/legado/app/ui/book/source/manage/BookSourceActivity.kt
//

import Foundation

/// The ordering of the book sources — upstream `BookSourceAdapter`.
///
/// The upstream reorders the sources by dragging a row: the `customOrder` of
/// the two rows is swapped (`BookSourceAdapter.swap`, L307-319). When the moved
/// rows end up with the same order the whole list is renumbered by its
/// position (`BookSourceAdapter.onClearView`, L323-339).
public enum SourceOrdering {

    /// Swaps the order of two sources — upstream `BookSourceAdapter.swap`.
    ///
    /// Returns the two sources with their `customOrder` exchanged.
    public static func swap(_ lhs: BookSource, _ rhs: BookSource) -> (BookSource, BookSource) {
        var first = lhs
        var second = rhs
        let order = first.customOrder
        first.customOrder = second.customOrder
        second.customOrder = order
        return (first, second)
    }

    /// Renumbers the sources by their position — upstream
    /// `BookSourceAdapter.onClearView` (the `upOrder` branch that writes the
    /// whole list).
    ///
    /// The upstream numbers them by their index when the list is ascending and
    /// by the negated index when it is descending.
    public static func renumber(_ sources: [BookSource], ascending: Bool) -> [BookSource] {
        sources.enumerated().map { index, source in
            var updated = source
            updated.customOrder = ascending ? Int64(index) : -Int64(index)
            return updated
        }
    }

    /// Whether the orders of the moved sources collide — upstream
    /// `BookSourceAdapter.onClearView` (`movedItems.size > sortNumberSet.size`).
    public static func hasOrderCollision(_ sources: [BookSource]) -> Bool {
        let orders = Set(sources.map(\.customOrder))
        return orders.count < sources.count
    }

    /// The order a source gets when it is moved to the top — upstream
    /// `BookSourceDao.minOrder - 1` (`ChangeBookSourceViewModel.topSource`).
    public static func topOrder(of sources: [BookSource]) -> Int64 {
        (sources.map(\.customOrder).min() ?? 0) - 1
    }

    /// The order a source gets when it is moved to the bottom — upstream
    /// `BookSourceDao.maxOrder + 1` (`ChangeBookSourceViewModel.bottomSource`).
    public static func bottomOrder(of sources: [BookSource]) -> Int64 {
        (sources.map(\.customOrder).max() ?? 0) + 1
    }
}

/// The selection of the book sources — upstream `BookSourceAdapter`.
///
/// The upstream can select every source between the first and the last
/// selected one (`BookSourceAdapter.checkSelectedInterval`, L276-293) and it
/// can invert the selection (`BookSourceAdapter.revertSelection`, L264-274).
public enum SourceSelection {

    /// Selects every source between the first and the last selected one —
    /// upstream `BookSourceAdapter.checkSelectedInterval`.
    ///
    /// The selection is the set of the source URLs.
    public static func interval(selected: Set<String>, in sources: [BookSource]) -> Set<String> {
        interval(selected: selected, in: sources.map(\.bookSourceUrl))
    }

    /// Selects every entry between the first and the last selected one — the
    /// generic form of `checkSelectedInterval`.
    ///
    /// The RSS sources use their URL as the identity, the book sources their
    /// `bookSourceUrl`; both are the same rule of the upstream.
    public static func interval(selected: Set<String>, in sources: [String]) -> Set<String> {
        let positions = sources.enumerated().compactMap { index, url in
            selected.contains(url) ? index : nil
        }
        guard let first = positions.min(), let last = positions.max() else {
            return selected
        }
        var result = selected
        for index in first...last {
            result.insert(sources[index])
        }
        return result
    }

    /// Inverts the selection — upstream `BookSourceAdapter.revertSelection`.
    public static func inverted(selected: Set<String>, in sources: [BookSource]) -> Set<String> {
        var result = selected
        for source in sources where !selected.contains(source.bookSourceUrl) {
            result.insert(source.bookSourceUrl)
        }
        return result
    }

    /// Selects every source — upstream `BookSourceAdapter.selectAll`.
    public static func all(in sources: [BookSource]) -> Set<String> {
        Set(sources.map(\.bookSourceUrl))
    }
}
