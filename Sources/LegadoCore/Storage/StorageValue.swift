//
//  StorageValue.swift
//  LegadoCore
//
//  The value type used by the storage layer.
//
//  Upstream uses Room (SQLite) with typed columns. The port keeps the same
//  value shapes but talks to a `TableStore` protocol so that the data layer
//  can be unit tested on Linux CI, where SQLite is not part of the Swift
//  toolchain, while the iOS app uses the real SQLite implementation.
//

import Foundation

/// A value that can be stored in a table.
public enum StorageValue: Equatable, Hashable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    /// The value as a string, mirroring SQLite's dynamic typing.
    public var stringValue: String {
        switch self {
        case .null: return ""
        case .integer(let value): return String(value)
        case .real(let value): return String(value)
        case .text(let value): return value
        case .blob(let data): return String(decoding: data, as: UTF8.self)
        }
    }

    /// The value as an integer, or `nil` when it is not numeric.
    public var intValue: Int64? {
        switch self {
        case .integer(let value): return value
        case .real(let value): return Int64(value)
        case .text(let value): return Int64(value)
        default: return nil
        }
    }

    /// The value as a double, or `nil` when it is not numeric.
    public var doubleValue: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .real(let value): return value
        case .text(let value): return Double(value)
        default: return nil
        }
    }

    /// The value as a boolean — SQLite stores booleans as integers.
    public var boolValue: Bool {
        switch self {
        case .integer(let value): return value != 0
        case .real(let value): return value != 0
        case .text(let value): return value == "true" || value == "1"
        default: return false
        }
    }

    /// The value as raw bytes, or `nil` when it is not a blob.
    public var dataValue: Data? {
        if case .blob(let data) = self { return data }
        return nil
    }

    /// `true` when the value is `NULL`.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }
}

/// A row of a table — a column name to value mapping.
public typealias StorageRow = [String: StorageValue]

/// Errors raised by the storage layer.
public enum StorageError: Error, Equatable, LocalizedError {
    /// The store is not available on this platform.
    case unavailable(String)
    /// The table does not exist.
    case unknownTable(String)
    /// A column does not exist.
    case unknownColumn(String)
    /// A unique constraint was violated.
    case constraintViolation(String)
    /// The statement failed.
    case statementFailed(String)

    /// The message the UI shows.
    ///
    /// Without it `localizedDescription` is the useless "The operation
    /// couldn't be completed. (LegadoCore.StorageError error 4.)" — the SQL
    /// that failed is exactly what a bug report needs.
    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return "数据库不可用：\(reason)"
        case .unknownTable(let name): return "数据表不存在：\(name)"
        case .unknownColumn(let name): return "数据列不存在：\(name)"
        case .constraintViolation(let detail): return "数据不符合约束：\(detail)"
        case .statementFailed(let detail): return "数据库语句执行失败：\(detail)"
        }
    }
}
