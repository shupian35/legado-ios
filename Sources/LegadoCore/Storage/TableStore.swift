//
//  TableStore.swift
//  LegadoCore
//
//  The storage abstraction the data layer is written against.
//
//  Upstream talks to Room directly (`data/dao/*`). The port keeps the same
//  table shapes but routes every access through this protocol, so the
//  repositories can be unit tested against the in-memory implementation on
//  Linux CI while the iOS app uses SQLite.
//

import Foundation

/// A relational table store.
public protocol TableStore: AnyObject {
    /// Creates the tables and indexes when they do not exist yet.
    func createSchema() throws
    /// Inserts a row, replacing an existing one with the same primary key.
    func insert(_ row: StorageRow, into table: String) throws
    /// Inserts many rows inside a single transaction.
    func insert(_ rows: [StorageRow], into table: String) throws
    /// Updates the rows matching `predicate` and returns the number of rows changed.
    @discardableResult
    func update(_ table: String, set values: StorageRow, where predicate: RowPredicate) throws -> Int
    /// Deletes the rows matching `predicate` and returns the number of rows removed.
    @discardableResult
    func delete(from table: String, where predicate: RowPredicate) throws -> Int
    /// Removes every row of a table.
    func deleteAll(from table: String) throws
    /// Reads the rows matching `predicate`.
    func rows(in table: String, where predicate: RowPredicate, orderBy: [OrderTerm]) throws -> [StorageRow]
    /// Reads a single row.
    func firstRow(in table: String, where predicate: RowPredicate) throws -> StorageRow?
    /// Counts the rows matching `predicate`.
    func count(in table: String, where predicate: RowPredicate) throws -> Int
    /// Runs `body` inside a transaction, rolling back when it throws.
    func transaction(_ body: () throws -> Void) throws

    /// Compacts the database file — upstream `ConfigViewModel.shrinkDatabase()`
    /// → `execSQL("VACUUM")`.
    func vacuum() throws
}

public extension TableStore {
    /// Reads every row of a table.
    func allRows(in table: String) throws -> [StorageRow] {
        try rows(in: table, where: .all, orderBy: [])
    }

    /// Reads the first matching row of a table.
    func anyRow(in table: String) throws -> StorageRow? {
        try firstRow(in: table, where: .all)
    }

    /// Counts every row of a table.
    func rowCount(in table: String) throws -> Int {
        try count(in: table, where: .all)
    }
}

/// A predicate over the columns of a row.
public enum RowPredicate: Equatable {
    /// Matches every row.
    case all
    /// Matches the rows where the column equals the value.
    case equals(column: String, value: StorageValue)
    /// Matches the rows where the column differs from the value.
    case notEquals(column: String, value: StorageValue)
    /// Matches the rows where the column is `NULL`.
    case isNull(column: String)
    /// Matches the rows where the column is not `NULL`.
    case notNull(column: String)
    /// Matches the rows where `column & mask != 0` — upstream's bitmask group model.
    case bitwiseAndNotZero(column: String, mask: Int64)
    /// Matches the rows where the numeric column is smaller than the value —
    /// upstream `delete from searchBooks where time < :time`.
    case lessThan(column: String, value: Int64)
    /// Matches the rows where the column equals the value, ignoring case.
    case equalsIgnoringCase(column: String, value: String)
    /// Matches the rows where the column contains the substring.
    case contains(column: String, value: String)
    /// Matches the rows where the column does NOT contain the substring.
    case notContains(column: String, value: String)
    /// Every predicate must match.
    case allOf([RowPredicate])
    /// At least one predicate must match.
    case anyOf([RowPredicate])

    /// Evaluates the predicate against a row.
    public func matches(_ row: StorageRow) -> Bool {
        switch self {
        case .all:
            return true
        case .equals(let column, let value):
            return row[column] == value
        case .notEquals(let column, let value):
            return row[column] != value
        case .isNull(let column):
            return row[column]?.isNull ?? true
        case .notNull(let column):
            return !(row[column]?.isNull ?? true)
        case .bitwiseAndNotZero(let column, let mask):
            guard let value = row[column]?.intValue else { return false }
            return (value & mask) != 0
        case .lessThan(let column, let value):
            guard let current = row[column]?.intValue else { return false }
            return current < value
        case .equalsIgnoringCase(let column, let value):
            return row[column]?.stringValue.lowercased() == value.lowercased()
        case .contains(let column, let value):
            return row[column]?.stringValue.contains(value) ?? false
        case .notContains(let column, let value):
            return !(row[column]?.stringValue.contains(value) ?? false)
        case .allOf(let predicates):
            return predicates.allSatisfy { $0.matches(row) }
        case .anyOf(let predicates):
            return predicates.contains { $0.matches(row) }
        }
    }
}

/// One term of an `ORDER BY` clause.
public struct OrderTerm: Equatable {
    public let column: String
    public let descending: Bool

    public init(column: String, descending: Bool = false) {
        self.column = column
        self.descending = descending
    }
}
