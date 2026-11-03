//
//  MemoryTableStore.swift
//  LegadoCore
//
//  An in-memory `TableStore`.
//
//  It backs the repositories in unit tests and on platforms where SQLite is
//  not available. It implements the same replace-on-primary-key semantics the
//  SQLite implementation uses, so the repositories behave identically.
//

import Foundation

/// A table store that keeps everything in memory.
public final class MemoryTableStore: TableStore {
    private var tables: [String: [StorageRow]] = [:]
    private var schemas: [String: TableDefinition] = [:]
    private var transactionDepth = 0
    private var rollbackSnapshot: [String: [StorageRow]]?

    public init() {}

    // MARK: - Schema

    public func createSchema() throws {
        for table in LegadoSchema.tables {
            schemas[table.name] = table
            if tables[table.name] == nil { tables[table.name] = [] }
        }
    }

    private func definition(_ table: String) throws -> TableDefinition {
        guard let definition = schemas[table] ?? LegadoSchema.table(table) else {
            throw StorageError.unknownTable(table)
        }
        schemas[table] = definition
        if tables[table] == nil { tables[table] = [] }
        return definition
    }

    // MARK: - Writing

    public func insert(_ row: StorageRow, into table: String) throws {
        let definition = try definition(table)
        var normalized = row
        for column in definition.columns {
            if normalized[column.name] == nil {
                normalized[column.name] = column.defaultValue ?? .null
            }
        }
        let key = primaryKeyValues(normalized, definition: definition)
        var rows = tables[table] ?? []
        if let index = rows.firstIndex(where: { primaryKeyValues($0, definition: definition) == key }) {
            rows[index] = normalized
        } else {
            rows.append(normalized)
        }
        tables[table] = rows
    }

    public func insert(_ rows: [StorageRow], into table: String) throws {
        try transaction {
            for row in rows { try insert(row, into: table) }
        }
    }

    @discardableResult
    public func update(_ table: String, set values: StorageRow, where predicate: RowPredicate) throws -> Int {
        _ = try definition(table)
        var rows = tables[table] ?? []
        var changed = 0
        for index in rows.indices where predicate.matches(rows[index]) {
            rows[index].merge(values) { _, new in new }
            changed += 1
        }
        tables[table] = rows
        return changed
    }

    @discardableResult
    public func delete(from table: String, where predicate: RowPredicate) throws -> Int {
        _ = try definition(table)
        let rows = tables[table] ?? []
        let kept = rows.filter { !predicate.matches($0) }
        tables[table] = kept
        return rows.count - kept.count
    }

    public func deleteAll(from table: String) throws {
        _ = try definition(table)
        tables[table] = []
    }

    // MARK: - Reading

    public func rows(in table: String, where predicate: RowPredicate = .all, orderBy: [OrderTerm] = []) throws -> [StorageRow] {
        _ = try definition(table)
        var result = (tables[table] ?? []).filter { predicate.matches($0) }
        for term in orderBy.reversed() {
            result.sort { lhs, rhs in
                let left = lhs[term.column]
                let right = rhs[term.column]
                let order = compare(left, right)
                return term.descending ? order > 0 : order < 0
            }
        }
        return result
    }

    public func firstRow(in table: String, where predicate: RowPredicate = .all) throws -> StorageRow? {
        try rows(in: table, where: predicate).first
    }

    public func count(in table: String, where predicate: RowPredicate = .all) throws -> Int {
        try rows(in: table, where: predicate).count
    }

    // MARK: - Transactions

    public func transaction(_ body: () throws -> Void) throws {
        if transactionDepth == 0 {
            rollbackSnapshot = tables
        }
        transactionDepth += 1
        do {
            try body()
        } catch {
            transactionDepth -= 1
            if transactionDepth == 0 {
                if let snapshot = rollbackSnapshot { tables = snapshot }
                rollbackSnapshot = nil
            }
            throw error
        }
        transactionDepth -= 1
        if transactionDepth == 0 { rollbackSnapshot = nil }
    }

    // MARK: - Helpers

    private func primaryKeyValues(_ row: StorageRow, definition: TableDefinition) -> [String: StorageValue] {
        var key: [String: StorageValue] = [:]
        for column in definition.primaryKey { key[column] = row[column] ?? .null }
        return key
    }

    private func compare(_ lhs: StorageValue?, _ rhs: StorageValue?) -> Int {
        switch (lhs, rhs) {
        case (nil, nil): return 0
        case (nil, _): return -1
        case (_, nil): return 1
        case (let left?, let right?):
            if let leftNumber = left.doubleValue, let rightNumber = right.doubleValue {
                if leftNumber == rightNumber { return 0 }
                return leftNumber < rightNumber ? -1 : 1
            }
            let leftText = left.stringValue
            let rightText = right.stringValue
            if leftText == rightText { return 0 }
            return leftText < rightText ? -1 : 1
        }
    }
}
