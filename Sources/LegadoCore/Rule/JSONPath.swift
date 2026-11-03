import Foundation

/// A JSONPath 1.0 engine covering the subset used by Legado book sources.
///
/// Upstream uses `com.jayway.jsonpath.JsonPath` (see
/// `app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSonPath.kt`).
/// This port implements the same observable behaviour for the expressions that
/// appear in real book sources:
///
/// - `$` root, `.name`, `['name']`, `["name"]`
/// - `..name` recursive descent, `..[n]`, `..[*]`
/// - `.*`, `[*]`
/// - `[n]` (negative indexes count from the end), `[start:end]`, `[start:end:step]`
/// - `['a','b']` unions
/// - `[?(@.field == 'value')]` filters with `==`, `!=`, `>`, `>=`, `<`, `<=`,
///   `=~` (regex) and bare existence checks, combined with `&&` / `||`
public enum JSONPath {

    // MARK: - Steps

    /// One step of a JSONPath expression.
    public enum Step: Equatable {
        /// `.name`
        case child(String)
        /// `..name`
        case recursiveChild(String)
        /// `.*` / `[*]`
        case wildcard
        /// `..[*]`
        case recursiveWildcard
        /// `[n]`
        case index(Int)
        /// `[start:end:step]`
        case slice(start: Int?, end: Int?, step: Int?)
        /// `['a','b']`
        case union([String])
        /// `[?(...)]`
        case filter(Filter)
    }

    /// A filter expression.
    public struct Filter: Equatable {
        /// A single comparison inside a filter.
        public struct Condition: Equatable {
            /// The relative path, e.g. `["name", "author"]`.
            public var path: [String]
            /// `==`, `!=`, `>`, `>=`, `<`, `<=`, `=~` — empty means "exists".
            public var op: String
            /// The expected value.
            public var value: JSONValue?

            public init(path: [String], op: String = "", value: JSONValue? = nil) {
                self.path = path
                self.op = op
                self.value = value
            }

            func matches(_ node: JSONValue) -> Bool {
                let resolved = Condition.resolve(path, in: node)
                guard let actual = resolved else {
                    // A missing path only satisfies "!=" and fails everything else.
                    return op == "!=" && value != nil
                }
                switch op {
                case "":
                    // A bare path is an existence check.
                    return true
                case "==":
                    return Condition.equal(actual, value)
                case "!=":
                    return !Condition.equal(actual, value)
                case ">":
                    return Condition.compare(actual, value) > 0
                case ">=":
                    return Condition.compare(actual, value) >= 0
                case "<":
                    return Condition.compare(actual, value) < 0
                case "<=":
                    return Condition.compare(actual, value) <= 0
                case "=~":
                    guard let pattern = value?.textValue else { return false }
                    guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
                    let text = actual.textValue
                    let range = NSRange(text.startIndex..<text.endIndex, in: text)
                    return regex.firstMatch(in: text, options: [], range: range) != nil
                default:
                    return false
                }
            }

            private static func resolve(_ path: [String], in node: JSONValue) -> JSONValue? {
                var current = node
                for component in path {
                    if let next = current[component] {
                        current = next
                    } else {
                        return nil
                    }
                }
                return current
            }

            private static func equal(_ lhs: JSONValue, _ rhs: JSONValue?) -> Bool {
                guard let rhs else { return false }
                if case .number(let left) = lhs, case .number(let right) = rhs {
                    return left == right
                }
                if case .bool(let left) = lhs, case .bool(let right) = rhs {
                    return left == right
                }
                return lhs.textValue == rhs.textValue
            }

            private static func compare(_ lhs: JSONValue, _ rhs: JSONValue?) -> Int {
                guard let rhs else { return 0 }
                if case .number(let left) = lhs, case .number(let right) = rhs {
                    if left == right { return 0 }
                    return left < right ? -1 : 1
                }
                let left = lhs.textValue
                let right = rhs.textValue
                if left == right { return 0 }
                return left < right ? -1 : 1
            }
        }

        /// The conditions of the filter.
        public var conditions: [Condition]
        /// `&&` (default) or `||`.
        public var logic: String

        public init(conditions: [Condition], logic: String = "&&") {
            self.conditions = conditions
            self.logic = logic
        }

        /// Whether `node` satisfies the filter.
        public func matches(_ node: JSONValue) -> Bool {
            guard !conditions.isEmpty else { return true }
            let results = conditions.map { $0.matches(node) }
            return logic == "||" ? results.contains(true) : results.allSatisfy { $0 }
        }
    }

    // MARK: - Reading

    /// Reads a path out of `root`.
    ///
    /// Mirrors jayway's `JsonPath.read`:
    /// - a definite path returns the single value at that path (`nil` when the
    ///   path does not exist — jayway raises `PathNotFoundException`);
    /// - an *indefinite* path (one containing a wildcard or a filter) collects
    ///   every match into an array, exactly like jayway's "all in" semantics.
    public static func read(_ path: String, in root: JSONValue) -> JSONValue? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var parser = PathParser(trimmed)
        guard let parsed = try? parser.parse() else { return nil }
        let matches = select(parsed.steps, root: root)
        if parsed.indefinite {
            guard !matches.isEmpty else { return nil }
            return .array(matches)
        }
        return matches.first
    }

    /// Reads a path and returns every match, including zero.
    public static func select(_ path: String, in root: JSONValue) -> [JSONValue] {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        var parser = PathParser(trimmed)
        guard let parsed = try? parser.parse() else { return [] }
        return select(parsed.steps, root: root)
    }

    /// Applies the steps to `root`.
    public static func select(_ steps: [Step], root: JSONValue) -> [JSONValue] {
        var current = [root]
        for step in steps {
            var next: [JSONValue] = []
            for node in current {
                next.append(contentsOf: apply(step, to: node))
            }
            current = next
        }
        return current
    }

    private static func apply(_ step: Step, to node: JSONValue) -> [JSONValue] {
        switch step {
        case .child(let name):
            if let value = node[name] { return [value] }
            return []

        case .recursiveChild(let name):
            var found: [JSONValue] = []
            func walk(_ current: JSONValue) {
                switch current {
                case .object(let members):
                    for (key, value) in members {
                        if key == name { found.append(value) }
                        walk(value)
                    }
                case .array(let items):
                    for item in items { walk(item) }
                default:
                    break
                }
            }
            walk(node)
            return found

        case .wildcard:
            switch node {
            case .object(let members): return Array(members.values)
            case .array(let items): return items
            default: return []
            }

        case .recursiveWildcard:
            var found: [JSONValue] = []
            func walk(_ current: JSONValue) {
                found.append(current)
                switch current {
                case .object(let members):
                    for value in members.values { walk(value) }
                case .array(let items):
                    for item in items { walk(item) }
                default:
                    break
                }
            }
            walk(node)
            return found

        case .index(let position):
            switch node {
            case .array(let items):
                let resolved = position < 0 ? items.count + position : position
                if resolved >= 0 && resolved < items.count { return [items[resolved]] }
                return []
            case .object(let members):
                if let value = members[String(position)] { return [value] }
                return []
            default:
                return []
            }

        case .slice(let start, let end, let step):
            guard case .array(let items) = node else { return [] }
            let count = items.count
            let stepSize = step ?? 1
            guard stepSize != 0 else { return [] }
            var indices: [Int] = []
            if stepSize > 0 {
                var first = start ?? 0
                var last = end ?? (count - 1)
                if first < 0 { first += count }
                if last < 0 { last += count }
                first = max(0, min(first, count))
                last = max(-1, min(last, count - 1))
                if last >= first {
                    indices = Array(stride(from: first, to: last + 1, by: stepSize))
                }
            } else {
                var first = start ?? (count - 1)
                var last = end ?? 0
                if first < 0 { first += count }
                if last < 0 { last += count }
                first = max(-1, min(first, count - 1))
                last = max(-1, min(last, count - 1))
                if first >= last {
                    indices = Array(stride(from: first, to: last - 1, by: stepSize))
                }
            }
            return indices.map { items[$0] }

        case .union(let names):
            guard case .object(let members) = node else { return [] }
            return names.compactMap { members[$0] }

        case .filter(let filter):
            var candidates: [JSONValue] = []
            switch node {
            case .array(let items): candidates = items
            case .object(let members): candidates = Array(members.values)
            default: break
            }
            return candidates.filter { filter.matches($0) }
        }
    }
}

// MARK: - Parser

/// Parses a JSONPath expression into steps.
struct PathParser {
    private let chars: [Character]
    private var index = 0

    init(_ path: String) {
        chars = Array(path)
    }

    struct ParseResult {
        var steps: [JSONPath.Step]
        var indefinite: Bool
    }

    mutating func parse() throws -> ParseResult {
        var steps: [JSONPath.Step] = []
        var indefinite = false

        skipWhitespace()
        if index < chars.count, chars[index] == "$" {
            index += 1
        }

        while index < chars.count {
            skipWhitespace()
            guard index < chars.count else { break }

            if chars[index] == "." {
                if index + 1 < chars.count, chars[index + 1] == "." {
                    index += 2
                    guard index < chars.count else { break }
                    if chars[index] == "[" {
                        let step = try parseBracket()
                        steps.append(step)
                        indefinite = true
                    } else {
                        let name = try readName()
                        steps.append(.recursiveChild(name))
                        indefinite = true
                    }
                } else {
                    index += 1
                    guard index < chars.count else { break }
                    if chars[index] == "*" {
                        index += 1
                        steps.append(.wildcard)
                        indefinite = true
                    } else {
                        let name = try readName()
                        steps.append(.child(name))
                    }
                }
            } else if chars[index] == "[" {
                let step = try parseBracket()
                steps.append(step)
                if case .filter = step { indefinite = true }
                if case .wildcard = step { indefinite = true }
            } else {
                // A bare name at the root, e.g. "name".
                let name = try readName()
                steps.append(.child(name))
            }
        }

        return ParseResult(steps: steps, indefinite: indefinite)
    }

    // MARK: Brackets

    private mutating func parseBracket() throws -> JSONPath.Step {
        // The caller guarantees that chars[index] == "[".
        index += 1
        skipWhitespace()

        guard index < chars.count else { throw PathError.unexpectedEnd }

        if chars[index] == "?" {
            index += 1
            skipWhitespace()
            var body = ""
            var depth = 0
            if index < chars.count, chars[index] == "(" {
                index += 1
                while index < chars.count {
                    let character = chars[index]
                    if character == "(" {
                        depth += 1
                    } else if character == ")" {
                        if depth == 0 { break }
                        depth -= 1
                    }
                    body.append(character)
                    index += 1
                }
            } else {
                while index < chars.count, chars[index] != "]" {
                    body.append(chars[index])
                    index += 1
                }
            }
            // Skip the closing ")" and "]".
            while index < chars.count, chars[index] != "]" { index += 1 }
            if index < chars.count { index += 1 }
            var filterParser = FilterParser(body: body)
            return .filter(try filterParser.parse())
        }
        // Collect the raw bracket body.
        var body = ""
        var quote: Character?
        while index < chars.count {
            let character = chars[index]
            if let active = quote {
                body.append(character)
                if character == active { quote = nil }
                index += 1
                continue
            }
            if character == "'" || character == "\"" {
                quote = character
                body.append(character)
                index += 1
                continue
            }
            if character == "]" { break }
            body.append(character)
            index += 1
        }
        if index < chars.count, chars[index] == "]" { index += 1 }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == "*" { return .wildcard }

        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            let start = parts.count > 0 ? Int(parts[0].trimmingCharacters(in: .whitespaces)) : nil
            let end = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil
            let step = parts.count > 2 ? Int(parts[2].trimmingCharacters(in: .whitespaces)) : nil
            return .slice(start: start, end: end, step: step)
        }

        if trimmed.contains(",") {
            let names = trimmed
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'\" ")) }
            return .union(names)
        }

        let unquoted = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
        if let position = Int(unquoted) {
            return .index(position)
        }
        return .child(unquoted)
    }

    // MARK: Helpers

    private mutating func skipWhitespace() {
        while index < chars.count, chars[index] == " " || chars[index] == "\t" {
            index += 1
        }
    }

    private mutating func readName() throws -> String {
        var name = ""
        while index < chars.count {
            let character = chars[index]
            if character == "." || character == "[" { break }
            if character == " " || character == "\t" { break }
            name.append(character)
            index += 1
        }
        guard !name.isEmpty else { throw PathError.expectedName }
        return name
    }

    enum PathError: Error {
        case expectedName
        case unexpectedEnd
    }
}

// MARK: - Filter parser

/// Parses the body of a `[?(...)]` filter.
struct FilterParser {
    private let chars: [Character]
    private var index = 0

    init(body: String) {
        chars = Array(body)
    }

    mutating func parse() throws -> JSONPath.Filter {
        var conditions: [JSONPath.Filter.Condition] = []
        var logic = "&&"

        while index < chars.count {
            skipWhitespace()
            let condition = try parseCondition()
            conditions.append(condition)
            skipWhitespace()
            // Look for && or ||
            if index + 1 < chars.count {
                let pair = String(chars[index]) + String(chars[index + 1])
                if pair == "&&" || pair == "||" {
                    logic = pair
                    index += 2
                    continue
                }
            }
            break
        }

        return JSONPath.Filter(conditions: conditions, logic: logic)
    }

    private mutating func parseCondition() throws -> JSONPath.Filter.Condition {
        skipWhitespace()
        var path: [String] = []
        if index < chars.count, chars[index] == "@" {
            index += 1
            while index < chars.count, chars[index] == "." || chars[index] == "[" {
                if chars[index] == "." {
                    index += 1
                    var name = ""
                    while index < chars.count,
                          chars[index] != ".",
                          chars[index] != "[",
                          chars[index] != " ",
                          chars[index] != "\t" {
                        name.append(chars[index])
                        index += 1
                    }
                    if !name.isEmpty { path.append(name) }
                } else {
                    index += 1
                    var name = ""
                    while index < chars.count, chars[index] != "]" {
                        name.append(chars[index])
                        index += 1
                    }
                    if index < chars.count { index += 1 }
                    let cleaned = name.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))
                    if !cleaned.isEmpty { path.append(cleaned) }
                }
            }
        }

        skipWhitespace()
        var op = ""
        for candidate in ["==", "!=", ">=", "<=", "=~", ">", "<"] {
            if matches(candidate) {
                op = candidate
                index += candidate.count
                break
            }
        }

        var value: JSONValue?
        if !op.isEmpty {
            skipWhitespace()
            value = try parseLiteral()
        }

        return JSONPath.Filter.Condition(path: path, op: op, value: value)
    }

    private mutating func parseLiteral() throws -> JSONValue {
        skipWhitespace()
        guard index < chars.count else { return .null }
        let character = chars[index]
        if character == "'" || character == "\"" {
            index += 1
            var text = ""
            while index < chars.count, chars[index] != character {
                if chars[index] == "\\", index + 1 < chars.count {
                    index += 1
                }
                text.append(chars[index])
                index += 1
            }
            if index < chars.count { index += 1 }
            return .string(text)
        }
        var text = ""
        while index < chars.count, chars[index] != ")" && chars[index] != "&" && chars[index] != "|" {
            text.append(chars[index])
            index += 1
        }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed == "true" { return .bool(true) }
        if trimmed == "false" { return .bool(false) }
        if trimmed == "null" { return .null }
        if let number = Double(trimmed) { return .number(number) }
        return .string(trimmed)
    }

    private func matches(_ text: String) -> Bool {
        let target = Array(text)
        guard index + target.count <= chars.count else { return false }
        for offset in 0..<target.count where chars[index + offset] != target[offset] {
            return false
        }
        return true
    }

    private mutating func skipWhitespace() {
        while index < chars.count, chars[index] == " " || chars[index] == "\t" {
            index += 1
        }
    }
}
