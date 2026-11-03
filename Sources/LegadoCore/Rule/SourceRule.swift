import Foundation

/// One step of a decomposed rule.
///
/// Port of the `SourceRule` inner class of
/// `io.legado.app.model.analyzeRule.AnalyzeRule`.
///
/// Upstream: app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt:530
public final class SourceRule {

    /// The five matching strategies of the rule engine.
    public enum Mode: String, Sendable, Equatable {
        /// Upstream `Mode.Default` — CSS selectors evaluated against the DOM.
        case css
        case xpath
        case json
        case js
        case regex
    }

    /// The (possibly rewritten) rule text.
    public var rule: String
    /// The strategy this step is evaluated with.
    public var mode: Mode
    /// `##regex` — the replacement pattern.
    public var replaceRegex: String = ""
    /// `##regex##replacement` — the replacement text.
    public var replacement: String = ""
    /// `##regex##replacement###` — replace only the first match.
    public var replaceFirst: Bool = false
    /// Variables declared with `@put:{...}`.
    public var putMap: [String: String] = [:]

    /// Parallel to `ruleType`: the literal / expression of each fragment.
    public private(set) var ruleParam: [String] = []
    /// `0` = literal, `>0` = capture group reference (`$n`), `-1` = `{{js}}`,
    /// `-2` = `@get:{key}`.
    public private(set) var ruleType: [Int] = []

    private static let getRuleType = -2
    private static let jsRuleType = -1
    private static let defaultRuleType = 0

    /// Creates a rule step.
    ///
    /// - Parameters:
    ///   - ruleStr: the raw rule fragment.
    ///   - mode: the strategy the fragment starts out with.
    ///   - isJSON: whether the analysed content is JSON — in that case a rule
    ///     that carries no explicit marker is treated as a JSONPath.
    public init(ruleStr: String, mode: Mode = .css, isJSON: Bool = false) {
        var currentMode = mode

        // Resolve the strategy marker.
        let resolved: String
        if currentMode == .js || currentMode == .regex {
            resolved = ruleStr
        } else if ruleStr.startsWithCaseInsensitive("@CSS:") {
            currentMode = .css
            resolved = ruleStr
        } else if ruleStr.hasPrefix("@@") {
            currentMode = .css
            resolved = String(ruleStr.dropFirst(2))
        } else if ruleStr.startsWithCaseInsensitive("@XPath:") {
            currentMode = .xpath
            resolved = String(ruleStr.dropFirst(7))
        } else if ruleStr.startsWithCaseInsensitive("@Json:") {
            currentMode = .json
            resolved = String(ruleStr.dropFirst(6))
        } else if isJSON || ruleStr.hasPrefix("$.") || ruleStr.hasPrefix("$[") {
            currentMode = .json
            resolved = ruleStr
        } else if ruleStr.hasPrefix("/") {
            // XPath is recognisable enough that it needs no explicit marker.
            currentMode = .xpath
            resolved = ruleStr
        } else {
            resolved = ruleStr
        }

        // Split off the `@put:{...}` declarations.
        var collectedPuts: [String: String] = [:]
        let withoutPuts = Self.splitPutRule(resolved, into: &collectedPuts)

        self.mode = currentMode
        self.rule = withoutPuts
        self.putMap = collectedPuts

        // Split off `@get:{...}` and `{{ ... }}`.
        var cursor = 0
        var isFirstMatch = true
        let ns = withoutPuts as NSString
        let matcher = RulePatterns.evalPattern
        let fullRange = NSRange(location: 0, length: ns.length)

        matcher.enumerateMatches(in: withoutPuts, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            let matchStart = match.range.location
            let matchEnd = matchStart + match.range.length
            let matched = ns.substring(with: match.range)

            if isFirstMatch {
                isFirstMatch = false
                let preceding = ns.substring(with: NSRange(location: 0, length: matchStart))
                if currentMode != .js && currentMode != .regex,
                   matchStart == 0 || !preceding.contains("##") {
                    self.mode = .regex
                    currentMode = .regex
                }
            }

            if matchStart > cursor {
                self.splitRegex(ns.substring(
                    with: NSRange(location: cursor, length: matchStart - cursor)
                ))
            }

            if matched.startsWithCaseInsensitive("@get:") {
                self.ruleType.append(Self.getRuleType)
                self.ruleParam.append(String(matched.dropFirst(6).dropLast()))
            } else if matched.hasPrefix("{{") {
                self.ruleType.append(Self.jsRuleType)
                self.ruleParam.append(String(matched.dropFirst(2).dropLast(2)))
            } else {
                self.splitRegex(matched)
            }

            cursor = matchEnd
            return
        }

        if ns.length > cursor {
            self.splitRegex(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)))
        }
    }

    /// Split `$\d{1,2}` capture-group references out of a literal.
    ///
    /// Upstream matches only against the part *before* the first `##`, but slices
    /// the original string — so the trailing `##…` stays inside the literal and
    /// is separated later by `makeUpRule`.
    private func splitRegex(_ ruleStr: String) {
        var cursor = 0
        let head = ruleStr.components(separatedBy: "##").first ?? ruleStr
        let ns = ruleStr as NSString
        let matcher = RulePatterns.regexPattern
        let range = NSRange(location: 0, length: (head as NSString).length)
        var hasMatch = false

        matcher.enumerateMatches(in: head, options: [], range: range) { match, _, _ in
            guard let match else { return }
            hasMatch = true
            if self.mode != .js && self.mode != .regex {
                self.mode = .regex
            }
            if match.range.location > cursor {
                self.ruleType.append(Self.defaultRuleType)
                self.ruleParam.append(ns.substring(
                    with: NSRange(location: cursor, length: match.range.location - cursor)
                ))
            }
            let token = ns.substring(with: match.range)
            self.ruleType.append(Int(token.dropFirst()) ?? 0)
            self.ruleParam.append(token)
            cursor = match.range.location + match.range.length
            return
        }

        if !hasMatch {
            // No capture-group reference — nothing was added above.
        }

        if ns.length > cursor {
            self.ruleType.append(Self.defaultRuleType)
            self.ruleParam.append(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)))
        }
    }

    /// Extract the `@put:{...}` declarations.
    ///
    /// Faithful to upstream: the matcher keeps scanning the *original* string
    /// while the working string shrinks, and every occurrence of the matched
    /// text is removed from the working string.
    private static func splitPutRule(_ ruleStr: String, into putMap: inout [String: String]) -> String {
        var working = ruleStr
        var collected: [String: String] = [:]
        let matcher = RulePatterns.putPattern
        let ns = ruleStr as NSString
        let range = NSRange(location: 0, length: ns.length)

        matcher.enumerateMatches(in: ruleStr, options: [], range: range) { match, _, _ in
            guard let match else { return }
            let matched = ns.substring(with: match.range)
            working = working.replacingOccurrences(of: matched, with: "")

            guard match.numberOfRanges > 1 else { return }
            let groupRange = match.range(at: 1)
            guard groupRange.location != NSNotFound else { return }
            let json = ns.substring(with: groupRange)

            if let strict = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: String] {
                collected.merge(strict) { _, new in new }
                return
            }
            if let lenient = LenientJSON.objectDictionary(json) {
                collected.merge(lenient) { _, new in new }
            }
            return
        }

        putMap.merge(collected) { _, new in new }
        return working
    }

    /// Number of fragments in this step.
    public var paramSize: Int { ruleParam.count }
}

/// A tiny forgiving JSON object parser, used as the "lenient" fallback for
/// `@put:{...}` declarations (upstream falls back to a lenient GSON instance).
public enum LenientJSON {

    /// Parse a JSON-ish object into `[String: String]`.
    public static func objectDictionary(_ text: String) -> [String: String]? {
        var scanner = Scanner(characters: Array(text))
        scanner.skipWhitespace()
        guard scanner.peek() == "{" else { return nil }
        scanner.advance()

        var result: [String: String] = [:]
        scanner.skipWhitespace()
        if scanner.peek() == "}" {
            scanner.advance()
            return result
        }

        while true {
            scanner.skipWhitespace()
            guard let key = scanner.scanKey() else { return nil }
            scanner.skipWhitespace()
            guard scanner.peek() == ":" else { return nil }
            scanner.advance()
            scanner.skipWhitespace()
            guard let value = scanner.scanValue() else { return nil }
            result[key] = value
            scanner.skipWhitespace()
            if scanner.peek() == "," {
                scanner.advance()
                scanner.skipWhitespace()
                // Gson's lenient reader rejects a trailing comma, so the port
                // rejects it as well.
                if scanner.peek() == "}" { return nil }
                continue
            }
            if scanner.peek() == "}" {
                scanner.advance()
                return result
            }
            return nil
        }
    }

    private struct Scanner {
        let characters: [Character]
        var index: Int = 0

        init(characters: [Character]) { self.characters = characters }

        var isAtEnd: Bool { index >= characters.count }

        func peek() -> Character? { isAtEnd ? nil : characters[index] }

        mutating func advance() { index += 1 }

        mutating func skipWhitespace() {
            while let current = peek(),
                  current == " " || current == "\n" || current == "\t" || current == "\r" {
                index += 1
            }
        }

        mutating func scanKey() -> String? {
            guard let first = peek() else { return nil }
            if first == "\"" || first == "'" { return scanString() }
            // Gson's lenient reader also accepts an unquoted name.
            var out = ""
            while let current = peek() {
                if current == ":" || current == " " || current == "\n" || current == "\t" || current == "\r" {
                    break
                }
                if current == "," || current == "}" || current == "]" { break }
                advance()
                out.append(current)
            }
            return out.isEmpty ? nil : out
        }

        mutating func scanString() -> String? {
            guard let quote = peek(), quote == "\"" || quote == "'" else { return nil }
            advance()
            var out = ""
            while let current = peek() {
                advance()
                if current == quote { return out }
                if current == "\\" {
                    guard let escaped = peek() else { return nil }
                    advance()
                    switch escaped {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "r": out.append("\r")
                    case "b": out.append("\u{8}")
                    case "f": out.append("\u{C}")
                    case "u":
                        var hex = ""
                        for _ in 0..<4 {
                            guard let digit = peek() else { return nil }
                            hex.append(digit)
                            advance()
                        }
                        if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                            out.append(Character(scalar))
                        }
                    default: out.append(escaped)
                    }
                    continue
                }
                out.append(current)
            }
            return nil
        }

        mutating func scanValue() -> String? {
            guard let first = peek() else { return nil }
            if first == "\"" || first == "'" { return scanString() }
            var out = ""
            while let current = peek() {
                if current == "," || current == "}" { break }
                advance()
                out.append(current)
            }
            let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
