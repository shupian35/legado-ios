//
//  DocumentExport.swift
//  LegadoCore
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/toc/rule/TxtTocRuleActivity.kt:251-258
//  app/src/main/java/io/legado/app/ui/dict/rule/DictRuleActivity.kt:152-159
//  app/src/main/java/io/legado/app/ui/book/source/manage/BookSourceViewModel.kt
//
//  Upstream writes the exported objects with `GSON.toJson(...)` into a file
//  that the user picks.  The port writes the same JSON and hands the file to
//  the share sheet, because iOS has no arbitrary document save picker.
//

import Foundation

/// The export of the stored objects into a JSON document.
public enum DocumentExport {

    /// The rows as a JSON array — the upstream `GSON.toJson(list)`.
    public static func json(_ rows: [StorageRow]) -> String {
        JSONValue.array(rows.map { jsonValue($0) }).jsonString
    }

    /// The objects as a JSON array — the upstream `GSON.toJson(list)`.
    public static func json<T>(_ items: [T], row: (T) -> StorageRow) -> String {
        json(items.map { row($0) })
    }

    /// A stored row as a JSON object.
    public static func jsonValue(_ row: StorageRow) -> JSONValue {
        var object: [String: JSONValue] = [:]
        for (key, value) in row {
            object[key] = jsonValue(value)
        }
        return .object(object)
    }

    /// A stored value as a JSON value.
    public static func jsonValue(_ value: StorageValue) -> JSONValue {
        switch value {
        case .null: return .null
        case .integer(let number): return .number(Double(number))
        case .real(let number): return .number(number)
        case .text(let text): return .string(text)
        case .blob(let data): return .string(String(decoding: data, as: UTF8.self))
        }
    }
}
