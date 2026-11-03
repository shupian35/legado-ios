//
//  RuleDataBox.swift
//  LegadoCore
//
//  The Swift counterpart of the upstream `RuleDataInterface` — a small
//  key/value store that the rule engine writes its `@put` variables into.
//
//  Upstream: app/src/main/java/io/legado/app/model/analyzeRule/RuleDataInterface.kt
//            app/src/main/java/io/legado/app/data/entities/BaseBook.kt
//

import Foundation

/// A mutable variable store used as the rule data of a rule evaluation.
///
/// Upstream the `variable` column of a book holds a JSON object with the
/// variables that the rules have written; the port keeps the same shape.
public final class RuleDataBox: RuleVariableHolder, Hashable {

    public private(set) var variables: [String: String]

    /// Called after every write — used by the source store, whose variables live
    /// in a global cache (upstream `CacheManager`) instead of in the entity.
    private let onChange: (([String: String]) -> Void)?

    /// The key of the source the box belongs to.
    ///
    /// Upstream binds the source object as `java` when a rule script runs, so
    /// the script needs to know which source it belongs to. The box carries
    /// the key so the rule engine can hand it to the script engine.
    public let sourceKey: String?
    /// The name of the source the box belongs to (upstream `sourceName`).
    ///
    /// The verification dialog shows it as the subtitle of the dialog.
    public let sourceName: String?

    public init(
        variables: [String: String] = [:],
        sourceKey: String? = nil,
        sourceName: String? = nil,
        onChange: (([String: String]) -> Void)? = nil
    ) {
        self.variables = variables
        self.sourceKey = sourceKey
        self.sourceName = sourceName
        self.onChange = onChange
    }

    /// Decode the upstream `variable` JSON column.
    public init(
        json: String?,
        sourceKey: String? = nil,
        sourceName: String? = nil,
        onChange: (([String: String]) -> Void)? = nil
    ) {
        self.variables = RuleDataBox.decode(json)
        self.sourceKey = sourceKey
        self.sourceName = sourceName
        self.onChange = onChange
    }

    /// Replace the variables with the ones of a JSON document.
    ///
    /// Upstream `BaseSource.setVariable(variable)` stores the JSON in the
    /// `variable` column of the source; the port keeps the same shape.
    public func setVariables(json: String) {
        variables = RuleDataBox.decode(json)
        onChange?(variables)
    }

    public func putVariable(_ key: String, _ value: String) {
        variables[key] = value
        onChange?(variables)
    }

    public func getVariable(_ key: String) -> String? {
        variables[key]
    }

    // MARK: - Hashable
    //
    // The box is compared BY IDENTITY: two chapters with the same variables are
    // still two different chapters, exactly like two different Java objects.

    public static func == (lhs: RuleDataBox, rhs: RuleDataBox) -> Bool {
        lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    /// The JSON representation stored in the `variable` column.
    ///
    /// Upstream `RuleData.getVariable()` returns `null` when the map is empty.
    public var json: String? {
        RuleDataBox.encode(variables)
    }

    // MARK: - JSON

    private static func decode(_ json: String?) -> [String: String] {
        guard let json, !json.isEmpty else { return [:] }
        guard let value = try? JSONValue.parse(json) else { return [:] }
        guard case .object(let members) = value else { return [:] }
        var result: [String: String] = [:]
        for (key, member) in members {
            result[key] = member.textValue
        }
        return result
    }

    private static func encode(_ variables: [String: String]) -> String? {
        guard !variables.isEmpty else { return nil }
        var parts: [String] = []
        for key in variables.keys.sorted() {
            let value = variables[key] ?? ""
            parts.append("\"\(RuleDataBox.escape(key))\":\"\(RuleDataBox.escape(value))\"")
        }
        return "{" + parts.joined(separator: ",") + "}"
    }

    private static func escape(_ text: String) -> String {
        var result = ""
        for character in text.unicodeScalars {
            switch character {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if character.value < 0x20 {
                    result += String(format: "\\u%04x", character.value)
                } else {
                    result.unicodeScalars.append(character)
                }
            }
        }
        return result
    }
}

/// The errors the pipeline can raise.
public enum PipelineError: Error, Equatable {
    /// The response body was empty — upstream `NoStackTraceException`.
    case emptyContent(String)
    /// The chapter list is empty — upstream `TocEmptyException`.
    case tocEmpty
    /// The chapter content is empty — upstream `ContentEmptyException`.
    case contentEmpty
    /// The download links of a file book are empty — upstream `NoStackTraceException`.
    case downloadUrlsEmpty
    /// A rule could not be evaluated.
    case ruleFailed(String)
}
