import Foundation

/// Faithful port of `io.legado.app.model.analyzeRule.RuleAnalyzer`.
///
/// Upstream: app/src/main/java/io/legado/app/model/analyzeRule/RuleAnalyzer.kt
///
/// The Android implementation is a hand written scanner (deliberately *not* a
/// regular expression) that splits a rule string on top level separators while
/// skipping over balanced `[...]` / `(...)` filter groups.  It exists because
/// JSONPath already uses `&&` / `||` and because rule strings may legitimately
/// contain `&&`, `||`, `%%`, `@` inside a filter or a quoted literal.
///
/// The port keeps the upstream algorithm step for step, including the two
/// different "balanced group" scanners (`chompCodeBalanced` understands escape
/// sequences, `chompRuleBalanced` does not) and the two-phase split.
public final class RuleAnalyzer {

    private static let escapeCharacter: Character = "\\"

    /// The string being processed.
    private let queue: [Character]
    /// Current position.
    private var pos: Int = 0
    /// Start of the field currently being collected.
    private var start: Int = 0
    /// Start of the current rule (used for slicing).
    private var startX: Int = 0
    /// Split result.
    private var rule: [String] = []
    /// Length of the separator that was matched.
    private var step: Int = 0
    /// The separator that is currently in use.
    public private(set) var elementsType: String = ""

    /// When true the balanced-group scanner understands escape sequences
    /// (upstream: `code = true`, used for JSON / JavaScript rules).
    private let code: Bool

    public init(_ data: String, code: Bool = false) {
        self.queue = Array(data)
        self.code = code
    }

    // MARK: - Primitives

    /// Trim the leading `@` / whitespace of the current rule.
    public func trim() {
        guard pos < queue.count else { return }
        if queue[pos] == "@" || queue[pos].isJavaSpaceOrLess() {
            pos += 1
            while pos < queue.count, queue[pos] == "@" || queue[pos].isJavaSpaceOrLess() {
                pos += 1
            }
            start = pos
            startX = pos
        }
    }

    /// Reset the position so the analyzer can be reused.
    public func reSetPos() {
        pos = 0
        startX = 0
    }

    /// Pull a string out of the remaining input, up to (but excluding) `seq`.
    /// - Returns: `true` when the sequence was found.
    private func consumeTo(_ seq: String) -> Bool {
        start = pos
        guard let offset = indexOf(seq, from: pos) else { return false }
        pos = offset
        return true
    }

    /// Pull a string out of the remaining input, up to any of `seq`.
    private func consumeToAny(_ seq: [String]) -> Bool {
        var cursor = pos
        while cursor != queue.count {
            for candidate in seq {
                if regionMatches(cursor, candidate) {
                    step = candidate.count
                    pos = cursor
                    return true
                }
            }
            cursor += 1
        }
        return false
    }

    /// Find the first occurrence of any of `chars` at or after `pos`.
    private func findToAny(_ chars: [Character]) -> Int {
        var cursor = pos
        while cursor != queue.count {
            for candidate in chars where queue[cursor] == candidate {
                return cursor
            }
            cursor += 1
        }
        return -1
    }

    /// Pull out a balanced group, honouring escape sequences.
    private func chompCodeBalanced(open: Character, close: Character) -> Bool {
        var cursor = pos
        var depth = 0
        var otherDepth = 0
        var inSingleQuote = false
        var inDoubleQuote = false

        repeat {
            if cursor == queue.count { break }
            let character = queue[cursor]
            cursor += 1
            if character != Self.escapeCharacter {
                if character == "'" && !inDoubleQuote { inSingleQuote.toggle() }
                else if character == "\"" && !inSingleQuote { inDoubleQuote.toggle() }

                if inSingleQuote || inDoubleQuote { continue }

                if character == "[" { depth += 1 }
                else if character == "]" { depth -= 1 }
                else if depth == 0 {
                    if character == open { otherDepth += 1 }
                    else if character == close { otherDepth -= 1 }
                }
            } else {
                cursor += 1
            }
        } while depth > 0 || otherDepth > 0

        if depth > 0 || otherDepth > 0 { return false }
        pos = cursor
        return true
    }

    /// Pull out a balanced rule group.  Inside quotes an escape character has no
    /// special meaning (upstream: "经过仔细测试xpath和jsoup中，引号内转义字符无效").
    private func chompRuleBalanced(open: Character, close: Character) -> Bool {
        var cursor = pos
        var depth = 0
        var inSingleQuote = false
        var inDoubleQuote = false

        repeat {
            if cursor == queue.count { break }
            let character = queue[cursor]
            cursor += 1
            if character == "'" && !inDoubleQuote { inSingleQuote.toggle() }
            else if character == "\"" && !inSingleQuote { inDoubleQuote.toggle() }

            if inSingleQuote || inDoubleQuote { continue }
            if character == Self.escapeCharacter {
                cursor += 1
                continue
            }

            if character == open { depth += 1 }
            else if character == close { depth -= 1 }
        } while depth > 0

        if depth > 0 { return false }
        pos = cursor
        return true
    }

    /// The balanced-group scanner: code-aware when `code == true`.
    private func chompBalanced(open: Character, close: Character) -> Bool {
        code
            ? chompCodeBalanced(open: open, close: close)
            : chompRuleBalanced(open: open, close: close)
    }

    // MARK: - Splitting

    /// Split the rule on the given separators.
    ///
    /// Upstream exposes two overloads: `splitRule(vararg split: String)` (first
    /// phase) and a private `splitRule()` (second phase, reusing the separator
    /// that was found first).
    public func splitRule(_ split: String...) throws -> [String] {
        try splitRuleFirst(split)
    }

    /// First phase — locates the separator and hands over to the second phase.
    ///
    /// Upstream `tailrec fun splitRule(vararg split: String)` — it *resets*
    /// the shared `rule` list before collecting the segments.
    private func splitRuleFirst(_ split: [String]) throws -> [String] {
        if split.count == 1 {
            elementsType = split[0]
            if !consumeTo(elementsType) {
                rule.append(substring(from: startX))
                return rule
            }
            step = elementsType.count
            return try splitRuleNext()
        } else if !consumeToAny(split) {
            rule.append(substring(from: startX))
            return rule
        }

        let end = pos
        pos = start

        repeat {
            let filterStart = findToAny(["[", "("])

            if filterStart == -1 {
                rule = [substring(from: startX, to: end)]
                elementsType = substring(from: end, to: end + step)
                pos = end + step

                while consumeTo(elementsType) {
                    rule.append(substring(from: start, to: pos))
                    pos += step
                }

                rule.append(substring(from: pos))
                return rule
            }

            if filterStart > end {
                rule = [substring(from: startX, to: end)]
                elementsType = substring(from: end, to: end + step)
                pos = end + step

                while consumeTo(elementsType) && pos < filterStart {
                    rule.append(substring(from: start, to: pos))
                    pos += step
                }

                if pos > filterStart {
                    startX = start
                    // The current segment is not finished — continue with the
                    // second phase.
                    return try splitRuleNext()
                } else {
                    rule.append(substring(from: pos))
                    return rule
                }
            }

            pos = filterStart
            let next: Character = queue[pos] == "[" ? "]" : ")"

            guard chompBalanced(open: queue[pos], close: next) else {
                throw RuleAnalyzerError.unbalanced(prefix + "后未平衡")
            }
        } while end > pos

        start = pos
        return try splitRuleFirst(split)
    }

    /// Second phase — the separator is already known, so searching is cheaper.
    ///
    /// Upstream `private tailrec fun splitRule()` — it *appends* to the shared
    /// `rule` list.
    private func splitRuleNext() throws -> [String] {
        let end = pos
        pos = start

        repeat {
            let filterStart = findToAny(["[", "("])

            if filterStart == -1 {
                rule.append(substring(from: startX, to: end))
                pos = end + step

                while consumeTo(elementsType) {
                    rule.append(substring(from: start, to: pos))
                    pos += step
                }

                rule.append(substring(from: pos))
                return rule
            }

            if filterStart > end {
                rule.append(substring(from: startX, to: end))
                pos = end + step

                while consumeTo(elementsType) && pos < filterStart {
                    rule.append(substring(from: start, to: pos))
                    pos += step
                }

                if pos > filterStart {
                    startX = start
                    return try splitRuleNext()
                } else {
                    rule.append(substring(from: pos))
                    return rule
                }
            }

            pos = filterStart
            let next: Character = queue[pos] == "[" ? "]" : ")"

            guard chompBalanced(open: queue[pos], close: next) else {
                throw RuleAnalyzerError.unbalanced(prefix + "后未平衡")
            }
        } while end > pos

        start = pos

        if !consumeTo(elementsType) {
            rule.append(substring(from: startX))
            return rule
        }
        return try splitRuleNext()
    }

    /// Replace embedded rules of the form `inner … }`.
    ///
    /// - Parameters:
    ///   - inner: the opening marker, e.g. `{{`.
    ///   - startStep: number of characters of `inner` that are not part of the
    ///     embedded rule (upstream default 1).
    ///   - endStep: number of trailing characters that are not part of the
    ///     embedded rule (upstream default 1).
    ///   - transform: resolves the embedded rule.
    public func innerRule(
        inner: String,
        startStep: Int = 1,
        endStep: Int = 1,
        _ transform: (String) -> String?
    ) -> String {
        var output = ""

        while consumeTo(inner) {
            let positionBefore = pos
            if chompCodeBalanced(open: "{", close: "}") {
                let raw = substring(from: positionBefore + startStep, to: pos - endStep)
                if let resolved = transform(raw), !resolved.isEmpty {
                    output += substring(from: startX, to: positionBefore) + resolved
                    startX = pos
                    continue
                }
            }
            pos += inner.count
        }

        if startX == 0 { return "" }
        return output + substring(from: startX)
    }

    /// Replace embedded rules delimited by `startStr` … `endStr`.
    public func innerRule(
        startStr: String,
        endStr: String,
        _ transform: (String) -> String?
    ) -> String {
        var output = ""

        while consumeTo(startStr) {
            pos += startStr.count
            let positionBefore = pos
            if consumeTo(endStr) {
                let raw = substring(from: positionBefore, to: pos)
                let resolved = transform(raw) ?? ""
                output += substring(from: startX, to: positionBefore - startStr.count) + resolved
                pos += endStr.count
                startX = pos
            }
        }

        if startX == 0 { return substring(from: 0) }
        return output + substring(from: startX)
    }

    // MARK: - Low level helpers

    private var prefix: String { String(queue.prefix(start)) }

    private func substring(from lower: Int) -> String {
        guard lower <= queue.count else { return "" }
        return String(queue[lower...])
    }

    private func substring(from lower: Int, to upper: Int) -> String {
        guard lower >= 0, upper <= queue.count, lower <= upper else { return "" }
        return String(queue[lower..<upper])
    }

    private func regionMatches(_ offset: Int, _ candidate: String) -> Bool {
        let candidateChars = Array(candidate)
        guard offset >= 0, offset + candidateChars.count <= queue.count else { return false }
        for index in 0..<candidateChars.count where queue[offset + index] != candidateChars[index] {
            return false
        }
        return true
    }

    private func indexOf(_ needle: String, from offset: Int) -> Int? {
        let needleChars = Array(needle)
        if needleChars.isEmpty { return offset }
        guard offset >= 0, offset <= queue.count else { return nil }
        var cursor = offset
        while cursor + needleChars.count <= queue.count {
            var matched = true
            for index in 0..<needleChars.count where queue[cursor + index] != needleChars[index] {
                matched = false
                break
            }
            if matched { return cursor }
            cursor += 1
        }
        return nil
    }
}

/// Errors raised by the rule scanner.
public enum RuleAnalyzerError: Error, Equatable {
    /// A `[` / `(` filter group was never closed.
    case unbalanced(String)
}
