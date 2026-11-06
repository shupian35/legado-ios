//
//  SQLiteTableStore.swift
//  LegadoCore
//
//  The SQLite backed `TableStore` — the iOS equivalent of the upstream Room
//  database.
//
//  SQLite is part of the Apple SDKs, so the implementation is only compiled on
//  Apple platforms. Everywhere else `UnavailableTableStore` reports the
//  missing capability.
//

import Foundation

#if canImport(SQLite3)

import SQLite3

/// A `TableStore` backed by SQLite.
public final class SQLiteTableStore: TableStore {
    private var handle: OpaquePointer?
    private var transactionDepth = 0

    /// Opens (or creates) a database file.
    public init(path: String) throws {
        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &pointer, flags, nil) == SQLITE_OK, let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let pointer { sqlite3_close_v2(pointer) }
            throw StorageError.statementFailed("cannot open database at \(path): \(message)")
        }
        handle = pointer
        // Foreign keys are off by default in SQLite.
        try execute("PRAGMA foreign_keys = ON")
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    // MARK: - Schema

    public func createSchema() throws {
        // One transaction, so a failing statement cannot leave a half created
        // schema behind: the app would otherwise fail on every query of the
        // tables that were never created.
        try transaction {
            for table in LegadoSchema.tables {
                try execute(table.createStatement)
                for statement in table.createIndexStatements { try execute(statement) }
            }
        }
    }

    // MARK: - Writing

    public func insert(_ row: StorageRow, into table: String) throws {
        let columns = row.keys.sorted()
        guard !columns.isEmpty else { return }
        let names = columns.map { "\"\($0)\"" }.joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
        let statement = "INSERT OR REPLACE INTO \"\(table)\" (\(names)) VALUES (\(placeholders))"
        try run(statement, values: columns.map { row[$0] ?? .null })
    }

    public func insert(_ rows: [StorageRow], into table: String) throws {
        try transaction {
            for row in rows { try insert(row, into: table) }
        }
    }

    @discardableResult
    public func update(_ table: String, set values: StorageRow, where predicate: RowPredicate) throws -> Int {
        guard !values.isEmpty else { return 0 }
        let assignments = values.keys.sorted().map { "\"\($0)\" = ?" }.joined(separator: ", ")
        let (clause, bindings) = sqlPredicate(predicate)
        let statement = "UPDATE \"\(table)\" SET \(assignments)\(clause)"
        var parameters = values.keys.sorted().map { values[$0] ?? .null }
        parameters.append(contentsOf: bindings)
        try run(statement, values: parameters)
        return try count(in: table, where: predicate)
    }

    @discardableResult
    public func delete(from table: String, where predicate: RowPredicate) throws -> Int {
        let (clause, bindings) = sqlPredicate(predicate)
        let statement = "DELETE FROM \"\(table)\"\(clause)"
        let removed = try count(in: table, where: predicate)
        try run(statement, values: bindings)
        return removed
    }

    public func deleteAll(from table: String) throws {
        try run("DELETE FROM \"\(table)\"", values: [])
    }

    // MARK: - Reading

    public func rows(in table: String, where predicate: RowPredicate = .all, orderBy: [OrderTerm] = []) throws -> [StorageRow] {
        let (clause, bindings) = sqlPredicate(predicate)
        var statement = "SELECT * FROM \"\(table)\"\(clause)"
        if !orderBy.isEmpty {
            let terms = orderBy.map { "\"\($0.column)\" \($0.descending ? "DESC" : "ASC")" }.joined(separator: ", ")
            statement += " ORDER BY \(terms)"
        }
        return try query(statement, values: bindings)
    }

    public func firstRow(in table: String, where predicate: RowPredicate = .all) throws -> StorageRow? {
        try rows(in: table, where: predicate).first
    }

    public func count(in table: String, where predicate: RowPredicate = .all) throws -> Int {
        let (clause, bindings) = sqlPredicate(predicate)
        let statement = "SELECT COUNT(*) FROM \"\(table)\"\(clause)"
        let rows = try query(statement, values: bindings)
        return rows.first?["count"]?.intValue.map(Int.init) ?? 0
    }

    // MARK: - Transactions

    public func transaction(_ body: () throws -> Void) throws {
        if transactionDepth == 0 { try execute("BEGIN TRANSACTION") }
        transactionDepth += 1
        do {
            try body()
        } catch {
            transactionDepth -= 1
            if transactionDepth == 0 { try? execute("ROLLBACK TRANSACTION") }
            throw error
        }
        transactionDepth -= 1
        if transactionDepth == 0 { try execute("COMMIT TRANSACTION") }
    }

    // MARK: - Maintenance

    /// Compacts the database file — upstream `ConfigViewModel.shrinkDatabase()`
    /// → `execSQL("VACUUM")`.
    public func vacuum() throws {
        try execute("VACUUM")
    }

    // MARK: - Low level

    private func execute(_ sql: String) throws {
        guard let handle else { throw StorageError.unavailable("the database is closed") }
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(handle, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorPointer)
            throw StorageError.statementFailed("\(message) — \(sql)")
        }
    }

    private func run(_ sql: String, values: [StorageValue]) throws {
        guard let handle else { throw StorageError.unavailable("the database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StorageError.statementFailed("\(String(cString: sqlite3_errmsg(handle))) — \(sql)")
        }
        defer { sqlite3_finalize(statement) }
        bind(values, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw StorageError.statementFailed("\(String(cString: sqlite3_errmsg(handle))) — \(sql)")
        }
    }

    private func query(_ sql: String, values: [StorageValue]) throws -> [StorageRow] {
        guard let handle else { throw StorageError.unavailable("the database is closed") }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw StorageError.statementFailed("\(String(cString: sqlite3_errmsg(handle))) — \(sql)")
        }
        defer { sqlite3_finalize(statement) }
        bind(values, to: statement)
        var result: [StorageRow] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                var row: StorageRow = [:]
                for index in 0..<sqlite3_column_count(statement) {
                    let name = String(cString: sqlite3_column_name(statement, index))
                    row[name] = columnValue(statement, index: index)
                }
                result.append(row)
            } else if step == SQLITE_DONE {
                break
            } else {
                throw StorageError.statementFailed("\(String(cString: sqlite3_errmsg(handle))) — \(sql)")
            }
        }
        return result
    }

    private func bind(_ values: [StorageValue], to statement: OpaquePointer) {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            switch value {
            case .null:
                sqlite3_bind_null(statement, index)
            case .integer(let number):
                sqlite3_bind_int64(statement, index, number)
            case .real(let number):
                sqlite3_bind_double(statement, index, number)
            case .text(let text):
                sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
            case .blob(let data):
                if data.isEmpty {
                    sqlite3_bind_blob(statement, index, nil, 0, SQLITE_TRANSIENT)
                } else {
                    _ = data.withUnsafeBytes { raw in
                        sqlite3_bind_blob(statement, index, raw.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                    }
                }
            }
        }
    }

    private func columnValue(_ statement: OpaquePointer, index: Int32) -> StorageValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, index) else { return .null }
            return .text(String(cString: text))
        case SQLITE_BLOB:
            let length = Int(sqlite3_column_bytes(statement, index))
            guard length > 0, let bytes = sqlite3_column_blob(statement, index) else { return .blob(Data()) }
            return .blob(Data(bytes: bytes, count: length))
        default:
            return .null
        }
    }

    /// Translates a predicate into a SQL clause and its bindings.
    private func sqlPredicate(_ predicate: RowPredicate) -> (String, [StorageValue]) {
        switch predicate {
        case .all:
            return ("", [])
        case .equals(let column, let value):
            return (" WHERE \"\(column)\" = ?", [value])
        case .notEquals(let column, let value):
            return (" WHERE (\"\(column)\" IS NULL OR \"\(column)\" <> ?)", [value])
        case .lessThan(let column, let value):
            return (" WHERE (\"\(column)\" IS NOT NULL AND \"\(column)\" < ?)", [.integer(value)])
        case .isNull(let column):
            return (" WHERE \"\(column)\" IS NULL", [])
        case .notNull(let column):
            return (" WHERE \"\(column)\" IS NOT NULL", [])
        case .bitwiseAndNotZero(let column, let mask):
            return (" WHERE (\"\(column)\" & ?) != 0", [.integer(mask)])
        case .equalsIgnoringCase(let column, let value):
            return (" WHERE LOWER(\"\(column)\") = LOWER(?)", [.text(value)])
        case .contains(let column, let value):
            return (" WHERE \"\(column)\" LIKE ?", [.text("%\(value)%")])
        case .notContains(let column, let value):
            return (" WHERE (\"\(column)\" IS NULL OR \"\(column)\" NOT LIKE ?)", [.text("%\(value)%")])
        case .allOf(let predicates):
            var clauses: [String] = []
            var bindings: [StorageValue] = []
            for item in predicates {
                let (clause, values) = sqlPredicate(item)
                guard !clause.isEmpty else { continue }
                clauses.append(String(clause.dropFirst(" WHERE ".count)))
                bindings.append(contentsOf: values)
            }
            guard !clauses.isEmpty else { return ("", []) }
            return (" WHERE " + clauses.map { "(\($0))" }.joined(separator: " AND "), bindings)
        case .anyOf(let predicates):
            var clauses: [String] = []
            var bindings: [StorageValue] = []
            for item in predicates {
                let (clause, values) = sqlPredicate(item)
                guard !clause.isEmpty else { continue }
                clauses.append(String(clause.dropFirst(" WHERE ".count)))
                bindings.append(contentsOf: values)
            }
            guard !clauses.isEmpty else { return ("", []) }
            return (" WHERE " + clauses.map { "(\($0))" }.joined(separator: " OR "), bindings)
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

#else

/// The store used where SQLite is not available — it reports the missing
/// capability instead of silently losing data.
public final class UnavailableTableStore: TableStore {
    private let reason: String

    public init(reason: String = "SQLite is only available on Apple platforms") {
        self.reason = reason
    }

    public func createSchema() throws { throw StorageError.unavailable(reason) }
    public func insert(_ row: StorageRow, into table: String) throws { throw StorageError.unavailable(reason) }
    public func insert(_ rows: [StorageRow], into table: String) throws { throw StorageError.unavailable(reason) }
    public func update(_ table: String, set values: StorageRow, where predicate: RowPredicate) throws -> Int { throw StorageError.unavailable(reason) }
    public func delete(from table: String, where predicate: RowPredicate) throws -> Int { throw StorageError.unavailable(reason) }
    public func deleteAll(from table: String) throws { throw StorageError.unavailable(reason) }
    public func rows(in table: String, where predicate: RowPredicate, orderBy: [OrderTerm]) throws -> [StorageRow] { throw StorageError.unavailable(reason) }
    public func firstRow(in table: String, where predicate: RowPredicate) throws -> StorageRow? { throw StorageError.unavailable(reason) }
    public func count(in table: String, where predicate: RowPredicate) throws -> Int { throw StorageError.unavailable(reason) }
    public func transaction(_ body: () throws -> Void) throws { throw StorageError.unavailable(reason) }
    public func vacuum() throws { throw StorageError.unavailable(reason) }
}

#endif
