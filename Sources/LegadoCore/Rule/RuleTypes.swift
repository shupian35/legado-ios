import Foundation

// MARK: - JSON

/// A JSON value.
///
/// The rule engine needs to talk about JSON documents without depending on
/// `JSONSerialization`'s untyped `Any` trees, so the port introduces a small
/// explicit value type.
public indirect enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    /// Parse a JSON document.
    public init(data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw JSONValueError.notUTF8
        }
        self = try JSONValue.parse(text)
    }

    /// Parse a JSON document from text.
    public init(text: String) throws {
        self = try JSONValue.parse(text)
    }

    /// Parse a JSON document.
    ///
    /// The port uses its own parser instead of `JSONSerialization` because the
    /// latter cannot tell a JSON boolean from the number `1` on every
    /// platform, and the rule engine has to keep that distinction.
    public static func parse(_ text: String) throws -> JSONValue {
        var parser = JSONParser(Array(text.unicodeScalars))
        parser.skipWhitespace()
        let value = try parser.parseValue()
        parser.skipWhitespace()
        guard parser.isAtEnd else { throw JSONValueError.trailingData }
        return value
    }

    /// Convert a `JSONSerialization` tree into a `JSONValue`.
    public init(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let bool as Bool where value is Bool:
            self = .bool(bool)
        case let number as NSNumber:
            self = .number(number.doubleValue)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map { JSONValue(any: $0) })
        case let dictionary as [String: Any]:
            var result: [String: JSONValue] = [:]
            for (key, element) in dictionary { result[key] = JSONValue(any: element) }
            self = .object(result)
        default:
            self = .string(String(describing: value))
        }
    }

    /// The value rendered the way Kotlin would render the equivalent `Any`.
    public var textValue: String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let value):
            if value == value.rounded(), abs(value) < 1e15 {
                return String(Int64(value))
            }
            return String(value)
        case .string(let value): return value
        case .array(let items): return items.map(\.textValue).joined(separator: ",")
        case .object(let members):
            return members
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value.textValue)" }
                .joined(separator: ",")
        }
    }

    /// Look up a member of an object.
    public subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    /// The members of an object — `nil` for every other kind.
    public var objectValue: [String: JSONValue]? {
        if case .object(let members) = self { return members }
        return nil
    }

    /// The items of an array — `nil` for every other kind.
    public var arrayValue: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    /// The value as a boolean — a number is true when it is not zero.
    public var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .number(let value): return value != 0
        case .string(let value):
            if value == "true" { return true }
            if value == "false" { return false }
            return nil
        default: return nil
        }
    }

    /// The value as an integer.
    public var intValue: Int64? {
        switch self {
        case .number(let value): return Int64(value)
        case .bool(let value): return value ? 1 : 0
        case .string(let value): return Int64(value)
        default: return nil
        }
    }

    /// The value as a double.
    public var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .bool(let value): return value ? 1 : 0
        case .string(let value): return Double(value)
        default: return nil
        }
    }

    /// The value as a string — a number or a boolean is rendered.
    public var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return RuleValue.formatNumber(value)
        case .bool(let flag): return flag ? "true" : "false"
        default: return nil
        }
    }

    /// The value rendered as a JSON document.
    public var jsonString: String {
        var result = ""
        JSONValue.write(self, into: &result)
        return result
    }

    private static func write(_ value: JSONValue, into result: inout String) {
        switch value {
        case .null:
            result += "null"
        case .bool(let flag):
            result += flag ? "true" : "false"
        case .number(let number):
            if number == number.rounded(), abs(number) < 1e15 {
                result += String(Int64(number))
            } else {
                result += String(number)
            }
        case .string(let text):
            result += "\"\(escape(text))\""
        case .array(let items):
            result += "["
            for (index, item) in items.enumerated() {
                if index > 0 { result += "," }
                write(item, into: &result)
            }
            result += "]"
        case .object(let members):
            result += "{"
            var first = true
            for key in members.keys.sorted() {
                if !first { result += "," }
                first = false
                result += "\"\(escape(key))\":"
                write(members[key]!, into: &result)
            }
            result += "}"
        }
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
            case "\u{8}": result += "\\b"
            case "\u{C}": result += "\\f"
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

// MARK: - DOM

/// A minimal DOM abstraction.
///
/// The CSS and XPath matchers need to walk a document; keeping the surface
/// small lets the iOS port reuse `SwiftSoup` (or any other conforming tree)
/// without dragging the Android DOM into the core.
public protocol DOMNode: AnyObject {
    /// The tag name of the node.
    var nodeTag: String { get }
    /// The concatenated text of the node.
    var nodeText: String { get }
    /// The outer HTML of the node.
    var nodeHTML: String { get }
    /// The node attributes.
    var nodeAttributes: [String: String] { get }
    /// The direct children of the node.
    var nodeChildren: [any DOMNode] { get }
}

// MARK: - Rule values

/// A value produced by the rule engine.
public enum RuleValue {
    case null
    case text(String)
    /// A number — the upstream Rhino `Double` / `Integer` results.
    case number(Double)
    case list([RuleValue])
    case object([String: RuleValue])
    /// A JavaScript object (the upstream `NativeObject`).
    ///
    /// The upstream engine treats a Rhino `NativeObject` differently from a
    /// JSON object: member access happens directly on the script result, so
    /// the port keeps the two apart.
    case scriptObject([String: RuleValue])
    /// A raw JSON value — the upstream `getObject` / `getList` results.
    case json(JSONValue)
    case node(any DOMNode)

    /// The text rendering of the value, mirroring Kotlin's `toString()`.
    ///
    /// A `null` value is Kotlin's `null` — `result?.toString() ?: ""` yields an
    /// empty string, not the literal "null".
    public var textValue: String {
        switch self {
        case .null: return ""
        case .text(let value): return value
        case .number(let value): return RuleValue.formatNumber(value)
        case .list(let items): return items.map(\.textValue).joined(separator: ",")
        case .object(let members):
            return members
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value.textValue)" }
                .joined(separator: ",")
        case .scriptObject(let members):
            return members
                .sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value.textValue)" }
                .joined(separator: ",")
        case .json(let value): return value.textValue
        case .node(let node): return node.nodeText
        }
    }

    /// The value as a list, or `nil` when it is not a list.
    public var listValue: [RuleValue]? {
        if case .list(let items) = self { return items }
        if case .number(let value) = self { return [.number(value)] }
        if case .json(.array(let items)) = self { return items.map { RuleValue.from(json: $0) } }
        return nil
    }

    /// Kotlin's `Double.toString()` — `3.0` stays `3.0`.
    public static func formatNumber(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return "\(value)"
        }
        return "\(value)"
    }

    /// The value as a member of an object, or `nil`.
    public func member(_ key: String) -> RuleValue? {
        switch self {
        case .object(let members): return members[key]
        case .scriptObject(let members): return members[key]
        case .json(let value): return value[key].map { RuleValue.from(json: $0) }
        default: return nil
        }
    }

    /// `nil` for `.null`, otherwise the value itself.
    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// The tag name of the node, when the value is one.
    public var nodeTag: String? {
        if case .node(let node) = self { return node.nodeTag }
        return nil
    }

    /// The text of the node, when the value is one.
    public var nodeText: String? {
        if case .node(let node) = self { return node.nodeText }
        return nil
    }

    /// The outer HTML of the node, when the value is one.
    public var nodeHTML: String? {
        if case .node(let node) = self { return node.nodeHTML }
        return nil
    }

    /// Convert a JSON value into a rule value.
    public static func from(json: JSONValue) -> RuleValue {
        switch json {
        case .null: return .null
        case .bool(let value): return .text(value ? "true" : "false")
        case .number(let value): return .text(JSONValue.number(value).textValue)
        case .string(let value): return .text(value)
        case .array(let items): return .list(items.map { RuleValue.from(json: $0) })
        case .object(let members):
            var result: [String: RuleValue] = [:]
            for (key, value) in members { result[key] = RuleValue.from(json: value) }
            return .object(result)
        }
    }
}

extension RuleValue: Equatable {
    public static func == (lhs: RuleValue, rhs: RuleValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.text(let a), .text(let b)): return a == b
        case (.number(let a), .number(let b)): return a == b
        case (.list(let a), .list(let b)):
            guard a.count == b.count else { return false }
            return zip(a, b).allSatisfy { $0 == $1 }
        case (.object(let a), .object(let b)):
            guard a.count == b.count else { return false }
            return a.allSatisfy { key, value in b[key] == value }
        case (.scriptObject(let a), .scriptObject(let b)):
            guard a.count == b.count else { return false }
            return a.allSatisfy { key, value in b[key] == value }
        case (.json(let a), .json(let b)): return a == b
        case (.node(let a), .node(let b)): return a === b
        default: return false
        }
    }
}

// MARK: - Content

/// The document a rule is evaluated against.
public enum RuleContent {
    /// Plain text or HTML.
    case text(String)
    /// A JSON document.
    case json(JSONValue)
    /// A DOM tree.
    case dom(any DOMNode)
    /// A script object (the result of a JavaScript expression).
    case object([String: RuleValue])

    /// Whether the content should be treated as JSON by the rule engine.
    ///
    /// Upstream: `content.toString().isJson()` for everything that is not a
    /// DOM node.
    public var isJSON: Bool {
        switch self {
        case .json: return true
        case .dom: return false
        case .object: return false
        case .text(let value): return JSONValue.isJSONText(value)
        }
    }
}

extension JSONValue {
    /// Whether a string looks like a JSON document.
    ///
    /// Mirrors upstream `String.isJson()`, which only inspects the first and
    /// last non-whitespace characters.
    public static func isJSONText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, let last = trimmed.last else { return false }
        return (first == "{" && last == "}") || (first == "[" && last == "]")
    }
}

extension RuleContent {
    /// The content seen as a rule value.
    public var ruleValue: RuleValue {
        switch self {
        case .text(let value): return .text(value)
        case .json(let value): return RuleValue.from(json: value)
        case .dom(let node): return .node(node)
        case .object(let members): return .scriptObject(members)
        }
    }

    /// The text rendering of the content.
    public var textValue: String {
        switch self {
        case .text(let value): return value
        case .json(let value): return value.textValue
        case .dom(let node): return node.nodeHTML
        case .object(let members): return RuleValue.object(members).textValue
        }
    }

    /// Build a document from a rule result — used when a rule step narrows the
    /// document down to a sub element (upstream `analyzeRule.setContent(item)`).
    public static func from(ruleValue: RuleValue) -> RuleContent {
        switch ruleValue {
        case .text(let value): return .text(value)
        case .json(let value): return .json(value)
        case .node(let node): return .dom(node)
        case .object(let members): return .object(members)
        case .scriptObject(let members): return .object(members)
        case .list(let items):
            if items.count == 1 { return from(ruleValue: items[0]) }
            return .text(items.map(\.textValue).joined(separator: "\n"))
        case .null: return .text("")
        case .number(let value): return .text(RuleValue.formatNumber(value))
        }
    }
}

// MARK: - Collaborators

/// A matcher for one of the five rule strategies.
///
/// Upstream the matchers are constructed with the *current* rule result, which
/// may be the original document or the output of a previous rule step — so the
/// port passes the value instead of the document.
public protocol RuleMatcher: AnyObject {
    /// Extract a single string.
    func string(_ content: RuleValue, _ rule: String) throws -> String?
    /// Extract a list of strings.
    func stringList(_ content: RuleValue, _ rule: String) throws -> [String]?
    /// Extract a single element.
    func element(_ content: RuleValue, _ rule: String) throws -> RuleValue?
    /// Extract a list of elements.
    func elements(_ content: RuleValue, _ rule: String) throws -> [RuleValue]
    /// Extract only the first match.
    ///
    /// Upstream `AnalyzeByJSoup.getString0` returns the first match instead of
    /// joining all of them.
    func firstString(_ content: RuleValue, _ rule: String) throws -> String?
}

public extension RuleMatcher {
    /// Extract only the first match.
    ///
    /// Upstream `AnalyzeByJSoup.getString0` returns the first match instead of
    /// joining all of them; the port exposes that as a matcher method with a
    /// generic default implementation.
    func firstString(_ content: RuleValue, _ rule: String) throws -> String? {
        guard let element = try element(content, rule) else { return nil }
        return element.textValue
    }
}

/// A holder of rule variables (`@put:` / `@get:`).
public protocol RuleVariableHolder: AnyObject {
    func putVariable(_ key: String, _ value: String)
    func getVariable(_ key: String) -> String?
}

/// The JavaScript runtime used by `{{ ... }}` rules.
public protocol RuleScriptEngine: AnyObject {
    /// Evaluate a script with the given bindings and return its result.
    func evaluate(_ script: String, bindings: [String: RuleValue]) throws -> RuleValue
    /// Evaluate a script that belongs to a source.
    ///
    /// Upstream binds the source object itself as `java`
    /// (`BaseSource.evalJS` → `bindings["java"] = this`), so the script can
    /// read and write the variables and the login data of the source that is
    /// being evaluated. The port passes the source down to the engine, which
    /// builds the `java` facade from it.
    func evaluate(
        _ script: String,
        bindings: [String: RuleValue],
        source: ScriptSourceContext?
    ) throws -> RuleValue
}

public extension RuleScriptEngine {
    /// The default implementation ignores the source.
    func evaluate(
        _ script: String,
        bindings: [String: RuleValue],
        source: ScriptSourceContext?
    ) throws -> RuleValue {
        try evaluate(script, bindings: bindings)
    }
}

// MARK: - Helpers

/// URL helpers used by the rule engine.
public enum RuleURL {

    /// Resolve `url` against `base`.
    ///
    /// Port of `NetworkUtils.getAbsoluteURL(baseURL: URL?, relativePath: String)`
    /// (app/src/main/java/io/legado/app/utils/NetworkUtils.kt:174):
    ///
    /// * an empty relative path stays empty;
    /// * an absolute URL (`isAbsUrl`) and a data URL are returned unchanged;
    /// * a `javascript:` URL resolves to an empty string;
    /// * everything else is resolved against the base URL the way
    ///   `java.net.URL(base, relative)` does — the last path segment of the
    ///   base is replaced and `.` / `..` segments are folded away.
    public static func absoluteURL(base: URL?, _ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        guard let base else { return trimmed }
        if trimmed.contains("://") { return trimmed }             // isAbsUrl
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("data:") { return trimmed }       // isDataUrl
        if lowercased.hasPrefix("javascript") { return "" }

        // Split the relative reference into path, query and fragment.
        var relativePath = trimmed
        var fragment = ""
        var query = ""
        if let hash = relativePath.firstIndex(of: "#") {
            fragment = String(relativePath[relativePath.index(after: hash)...])
            relativePath = String(relativePath[..<hash])
        }
        if let mark = relativePath.firstIndex(of: "?") {
            query = String(relativePath[relativePath.index(after: mark)...])
            relativePath = String(relativePath[..<mark])
        }

        guard let scheme = base.scheme, let host = base.host else { return trimmed }
        let authority = base.port.map { "\(host):\($0)" } ?? host

        var path: String
        if relativePath.hasPrefix("/") {
            path = relativePath
        } else {
            // Resolve against the *directory* of the base URL.
            var directory = base.path
            if !directory.isEmpty, !directory.hasSuffix("/") {
                if let lastSlash = directory.lastIndex(of: "/") {
                    directory = String(directory[..<directory.index(after: lastSlash)])
                } else {
                    directory = "/"
                }
            }
            if directory.isEmpty { directory = "/" }
            path = directory + relativePath
        }

        return "\(scheme)://\(authority)\(foldPath(path))\(query)\(fragment)"
    }

    /// Fold `.` and `..` segments out of a URL path.
    private static func foldPath(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        var segments: [String] = []
        for segment in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch segment {
            case ".":
                continue
            case "..":
                if !segments.isEmpty { segments.removeLast() }
            default:
                segments.append(String(segment))
            }
        }
        var result = segments.joined(separator: "/")
        if isAbsolute { result = "/" + result }
        if result.isEmpty { result = isAbsolute ? "/" : "" }
        if path.hasSuffix("/"), !result.hasSuffix("/") { result += "/" }
        return result
    }
}

/// Errors raised while parsing JSON.
public enum JSONValueError: Error, Equatable {
    case notUTF8
    case unexpectedCharacter(Unicode.Scalar)
    case unexpectedEnd
    case trailingData
}

/// A small recursive-descent JSON parser.
struct JSONParser {
    private let scalars: [Unicode.Scalar]
    private var index: Int = 0

    init(_ scalars: [Unicode.Scalar]) { self.scalars = scalars }

    var isAtEnd: Bool { index >= scalars.count }

    mutating func skipWhitespace() {
        while index < scalars.count {
            switch scalars[index] {
            case " ", "\n", "\t", "\r": index += 1
            default: return
            }
        }
    }

    mutating func parseValue() throws -> JSONValue {
        skipWhitespace()
        guard index < scalars.count else { throw JSONValueError.unexpectedEnd }
        switch scalars[index] {
        case "{": return try parseObject()
        case "[": return try parseArray()
        case "\"": return .string(try parseString())
        case "t":
            try expect("true")
            return .bool(true)
        case "f":
            try expect("false")
            return .bool(false)
        case "n":
            try expect("null")
            return .null
        default:
            return .number(try parseNumber())
        }
    }

    private mutating func expect(_ literal: String) throws {
        for character in literal.unicodeScalars {
            guard index < scalars.count, scalars[index] == character else {
                throw JSONValueError.unexpectedEnd
            }
            index += 1
        }
    }

    private mutating func parseObject() throws -> JSONValue {
        index += 1 // '{'
        var members: [String: JSONValue] = [:]
        skipWhitespace()
        if index < scalars.count, scalars[index] == "}" {
            index += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            let key = try parseString()
            skipWhitespace()
            guard index < scalars.count, scalars[index] == ":" else {
                throw JSONValueError.unexpectedEnd
            }
            index += 1
            let value = try parseValue()
            members[key] = value
            skipWhitespace()
            guard index < scalars.count else { throw JSONValueError.unexpectedEnd }
            if scalars[index] == "," {
                index += 1
                continue
            }
            if scalars[index] == "}" {
                index += 1
                return .object(members)
            }
            throw JSONValueError.unexpectedCharacter(scalars[index])
        }
    }

    private mutating func parseArray() throws -> JSONValue {
        index += 1 // '['
        var items: [JSONValue] = []
        skipWhitespace()
        if index < scalars.count, scalars[index] == "]" {
            index += 1
            return .array(items)
        }
        while true {
            items.append(try parseValue())
            skipWhitespace()
            guard index < scalars.count else { throw JSONValueError.unexpectedEnd }
            if scalars[index] == "," {
                index += 1
                continue
            }
            if scalars[index] == "]" {
                index += 1
                return .array(items)
            }
            throw JSONValueError.unexpectedCharacter(scalars[index])
        }
    }

    private mutating func parseString() throws -> String {
        guard index < scalars.count, scalars[index] == "\"" else {
            throw index < scalars.count
                ? JSONValueError.unexpectedCharacter(scalars[index])
                : JSONValueError.unexpectedEnd
        }
        index += 1
        var result = String.UnicodeScalarView()
        while index < scalars.count {
            let scalar = scalars[index]
            index += 1
            if scalar == "\"" { return String(result) }
            if scalar != "\\" {
                result.append(scalar)
                continue
            }
            guard index < scalars.count else { throw JSONValueError.unexpectedEnd }
            let escaped = scalars[index]
            index += 1
            switch escaped {
            case "\"": result.append("\"")
            case "\\": result.append("\\")
            case "/": result.append("/")
            case "b": result.append("\u{8}")
            case "f": result.append("\u{C}")
            case "n": result.append("\n")
            case "r": result.append("\r")
            case "t": result.append("\t")
            case "u":
                var hex = ""
                for _ in 0..<4 {
                    guard index < scalars.count else { throw JSONValueError.unexpectedEnd }
                    hex.unicodeScalars.append(scalars[index])
                    index += 1
                }
                guard let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) else {
                    throw JSONValueError.unexpectedEnd
                }
                result.append(scalar)
            default:
                result.append(escaped)
            }
        }
        throw JSONValueError.unexpectedEnd
    }

    private mutating func parseNumber() throws -> Double {
        var text = ""
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "-" || scalar == "+" || scalar == "." || scalar == "e" || scalar == "E"
                || (scalar.value >= 48 && scalar.value <= 57) {
                text.unicodeScalars.append(scalar)
                index += 1
                continue
            }
            break
        }
        guard let value = Double(text) else {
            throw index < scalars.count
                ? JSONValueError.unexpectedCharacter(scalars[index])
                : JSONValueError.unexpectedEnd
        }
        return value
    }
}

/// HTML entity decoding used by `getString(unescape: true)`.
public enum RuleEntities {

    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": "\u{00A0}", "copy": "©", "reg": "®", "trade": "™",
        "hellip": "…", "mdash": "—", "ndash": "–", "lsquo": "‘",
        "rsquo": "’", "ldquo": "“", "rdquo": "”", "laquo": "«",
        "raquo": "»", "middot": "·", "bull": "•", "deg": "°",
        "times": "×", "divide": "÷", "plusmn": "±", "frac12": "½",
        "frac14": "¼", "frac34": "¾", "sup2": "²", "sup3": "³",
        "micro": "µ", "para": "¶", "sect": "§", "dagger": "†",
        "permil": "‰", "prime": "′", "Prime": "″", "euro": "€",
        "pound": "£", "yen": "¥", "cent": "¢", "curren": "¤",
        "larr": "←", "uarr": "↑", "rarr": "→", "darr": "↓",
        "harr": "↔", "alpha": "α", "beta": "β", "gamma": "γ",
        "delta": "δ", "pi": "π", "sigma": "σ", "omega": "ω",
        "infin": "∞", "ne": "≠", "le": "≤", "ge": "≥"
    ]

    /// Decode HTML 4 entities.
    public static func unescapeHTML4(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        result.reserveCapacity(text.count)
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&" else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            // Find the terminating semicolon within a reasonable window.
            let searchEnd = text.index(index, offsetBy: 12, limitedBy: text.endIndex) ?? text.endIndex
            guard let semicolon = text[index..<searchEnd].firstIndex(of: ";") else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let body = String(text[text.index(after: index)..<semicolon])
            if body.hasPrefix("#") {
                let digits = String(body.dropFirst())
                let scalarValue: UInt32?
                if digits.lowercased().hasPrefix("x") {
                    scalarValue = UInt32(digits.dropFirst(), radix: 16)
                } else {
                    scalarValue = UInt32(digits, radix: 10)
                }
                if let scalarValue, let scalar = Unicode.Scalar(scalarValue) {
                    result.append(Character(scalar))
                    index = text.index(after: semicolon)
                    continue
                }
            } else if let replacement = named[body] {
                result.append(replacement)
                index = text.index(after: semicolon)
                continue
            }
            result.append(character)
            index = text.index(after: index)
        }
        return result
    }
}
