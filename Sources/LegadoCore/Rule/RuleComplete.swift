//
//  RuleComplete.swift
//  LegadoCore
//
//  The rule auto-completion — upstream `app/src/main/java/io/legado/app/help/RuleComplete.kt`.
//
//  The upstream completes a *simple* rule so that the user does not have to
//  write the trailing `@text` / `@href` / `@src` by hand:
//
//      class.name            →  class.name@text
//      class.name&&class.year → class.name@text&&class.year
//
//  It only applies to the CSS / XPath rules — a rule that contains a script
//  (`{{…}}`, `@js:`, `<js>`, `@Json:`, `$.`) or that starts with `:` is left
//  alone.
//

import Foundation

/// The kind of value a rule is expected to produce.
public enum RuleCompleteType: Int, Sendable, CaseIterable {
    /// The text of an element.
    case text = 1
    /// The link of an element.
    case link = 2
    /// The image of an element.
    case image = 3
}

/// The rule auto-completion.
public enum RuleComplete {

    /// The suffixes that mean "this rule already says what to take".
    private static let completedSuffixes = [
        "attr", "text", "ownText", "textNodes", "href", "content", "html",
        "alt", "all", "value", "src"
    ]

    /// The characters that may precede a completed suffix (the upstream
    /// `[@|/^]|[|%&]{2}`).
    private static let prefixChars: Set<Character> = ["|", "%", "&"]

    /// Completes a simple rule.
    ///
    /// - Parameters:
    ///   - rules: the rule to complete.
    ///   - preRule: the rule the result is combined with — when it is complex
    ///     the completion is skipped (the upstream `notComplete` check).
    ///   - type: the kind of value the rule produces.
    /// - Returns: the completed rule, or the original one when it cannot be
    ///   completed.
    public static func autoComplete(
        rules: String?,
        preRule: String? = nil,
        type: RuleCompleteType = .text
    ) -> String? {
        guard let rules, !rules.isEmpty else { return rules }
        if isComplex(rules) { return rules }
        if let preRule, isComplex(preRule) { return rules }

        // The tail rule (`##…` or `,{…`) is kept as it is.
        let (cleaned, tail) = splitTail(rules)
        guard !cleaned.isEmpty else { return rules }

        // The upstream uses `^//|^@Xpath:` — a case-sensitive check that does
        // not match the rule engine's case-insensitive `@XPath:` prefix
        // (`AnalyzeRule.kt:558`). The port follows the engine.
        let isXPath = cleaned.hasPrefix("//")
            || cleaned.range(of: "@XPath:", options: [.caseInsensitive])?.lowerBound == cleaned.startIndex
        let textRule = isXPath ? "//text()" : "@text"
        let linkRule = isXPath ? "//@href" : "@href"
        let imageRule = isXPath ? "//@src" : "@src"

        var result: String
        switch type {
        case .text:
            result = applyCompletion(textRule, to: cleaned)
            result = applyImageFix(isXPath ? "/@alt" : "@alt", to: result)
        case .link:
            result = applyCompletion(linkRule, to: cleaned)
        case .image:
            result = applyCompletion(imageRule, to: cleaned)
        }
        return result + tail
    }

    /// The upstream `notComplete` check: a rule that contains a script or that
    /// starts with `:` / `##` is never completed.
    public static func isComplex(_ rule: String) -> Bool {
        if rule.hasPrefix(":") || rule.hasPrefix("##") { return true }
        for marker in ["{{", "@js:", "<js>", "@Json:", "$."] where rule.contains(marker) {
            return true
        }
        return false
    }

    /// Splits the tail rule (`##…` or `,{…`) off the rule.
    ///
    /// The upstream splits with the regular expression `##|,\{` and a limit of
    /// two, so the tail keeps its separator.
    static func splitTail(_ rule: String) -> (cleaned: String, tail: String) {
        let chars = Array(rule)
        var index = 0
        while index < chars.count {
            if chars[index] == "#", index + 1 < chars.count, chars[index + 1] == "#" {
                let separator = String(chars[index..<(index + 2)])
                let rest = String(chars[(index + 2)...])
                return (String(chars[0..<index]), separator + rest)
            }
            if chars[index] == ",", index + 1 < chars.count, chars[index + 1] == "{" {
                let separator = String(chars[index..<(index + 2)])
                let rest = String(chars[(index + 2)...])
                return (String(chars[0..<index]), separator + rest)
            }
            index += 1
        }
        return (rule, "")
    }

    /// Inserts the completion rule at every position that still needs it.
    ///
    /// A position needs the completion when it is one of the separators
    /// (`&&`, `%%`, `||`) or the end of the rule, and the text before it does
    /// not already name what to take.
    static func applyCompletion(_ rule: String, to text: String) -> String {
        let chars = Array(text)
        var result = ""
        var index = 0
        while index < chars.count {
            if index + 1 < chars.count, let separator = separator(chars, at: index) {
                if needsCompletion(String(chars[0..<index])) {
                    result += rule
                }
                result += separator
                index += 2
                continue
            }
            result.append(chars[index])
            index += 1
        }
        if needsCompletion(text) {
            result += rule
        }
        return result
    }

    /// The separator at the given position, if any.
    private static func separator(_ chars: [Character], at index: Int) -> String? {
        let first = chars[index]
        let second = chars[index + 1]
        guard first == second else { return nil }
        if first == "&" || first == "%" || first == "|" {
            return String([first, second])
        }
        return nil
    }

    /// Whether the text before a separator still needs the completion.
    ///
    /// The upstream look-behind is
    /// `(?<!(@|/|^|[|%&]{2})(attr|text|…)(\(\))?)` — the rule is complete when
    /// it already ends with one of the suffixes, optionally followed by `()`,
    /// and that suffix is preceded by `@`, `/`, the start of the rule or two
    /// characters of `[|%&]`.
    static func needsCompletion(_ prefix: String) -> Bool {
        for suffix in completedSuffixes {
            // The upstream look-behind allows the suffix to be followed by
            // empty parentheses: `text()`.
            if prefix.hasSuffix(suffix + "()") {
                let before = prefix.dropLast(suffix.count + 2)
                if isCompletePrefix(before) { return false }
                continue
            }
            if prefix.hasSuffix(suffix) {
                let before = prefix.dropLast(suffix.count)
                if isCompletePrefix(before) { return false }
            }
        }
        return true
    }

    /// Whether the text before a completed suffix blocks the completion.
    ///
    /// The upstream look-behind is
    /// `(?<!(@|/|^|[|%&]{2})(attr|text|…)(\(\))?)` — the suffix must be
    /// preceded by `@`, `/`, the start of the rule or two characters of
    /// `[|%&]`.
    private static func isCompletePrefix(_ before: Substring) -> Bool {
        if before.isEmpty { return true }
        if let last = before.last, last == "@" || last == "/" { return true }
        if before.count >= 2, before.suffix(2).allSatisfy({ prefixChars.contains($0) }) {
            return true
        }
        return false
    }

    /// Rewrites the `img…@text` rules into `img…@alt` — the upstream
    /// `fixImgInfo`.
    static func applyImageFix(_ altSuffix: String, to text: String) -> String {
        let chars = Array(text)
        var result = ""
        var index = 0
        while index < chars.count {
            if let match = imageMatch(chars, at: index) {
                result += "img" + match.attribute + altSuffix + match.separator
                index += match.length
                continue
            }
            result.append(chars[index])
            index += 1
        }
        return result
    }

    /// The image rule match at the given position.
    ///
    /// The upstream pattern is
    /// `(?<=(^|tag\.|[\+/@>~| &]))img(?<at>(\[@?.+\]|\.[-\w]+)?)[@/]+text(\(\))?(?<seq>…)`.
    private static func imageMatch(_ chars: [Character], at index: Int) -> (attribute: String, separator: String, length: Int)? {
        guard index + 3 <= chars.count,
              chars[index] == "i", chars[index + 1] == "m", chars[index + 2] == "g" else {
            return nil
        }
        if index > 0 {
            let preceded = index >= 4
                && chars[index - 4] == "t" && chars[index - 3] == "a"
                && chars[index - 2] == "g" && chars[index - 1] == "."
            let charBefore = chars[index - 1]
            let allowed = "+/@>~| &".contains(charBefore)
            guard preceded || allowed else { return nil }
        }
        var cursor = index + 3
        var attribute = ""
        if cursor < chars.count, chars[cursor] == "[",
           let close = chars[cursor...].lastIndex(of: "]"), close > cursor + 1 {
            let inner = Array(chars[(cursor + 1)..<close])
            if let first = inner.first, "@?..+".contains(first) {
                attribute = String(chars[cursor...close])
                cursor = close + 1
            }
        }
        if attribute.isEmpty, cursor < chars.count, chars[cursor] == "." {
            var end = cursor + 1
            while end < chars.count, chars[end].isLetter || chars[end].isNumber
                || chars[end] == "_" || chars[end] == "-" {
                end += 1
            }
            if end > cursor + 1 {
                attribute = String(chars[cursor..<end])
                cursor = end
            }
        }
        var slashes = 0
        while cursor < chars.count, chars[cursor] == "@" || chars[cursor] == "/" {
            cursor += 1
            slashes += 1
        }
        guard slashes > 0 else { return nil }
        guard cursor + 4 <= chars.count,
              chars[cursor] == "t", chars[cursor + 1] == "e",
              chars[cursor + 2] == "x", chars[cursor + 3] == "t" else {
            return nil
        }
        cursor += 4
        if cursor + 2 <= chars.count, chars[cursor] == "(", chars[cursor + 1] == ")" {
            cursor += 2
        }
        var trailing = ""
        if cursor + 1 < chars.count, let value = separator(chars, at: cursor) {
            trailing = value
            cursor += 2
        }
        return (attribute, trailing, cursor - index)
    }
}

/// The kind of a source rule.
public enum SourceRuleKind: String, Sendable, CaseIterable {
    case search
    case explore
    case bookInfo
    case toc
    case content
}

/// Completes the sub-rules of a source rule.
///
/// The upstream completes every sub-rule of a rule group with the list rule
/// of the group as the pre-rule (`BookSourceEditActivity.kt:408-539`).
public enum RuleAutoCompleter {

    /// The sub-rules of every rule group and the kind of value they produce.
    private static func fields(for kind: SourceRuleKind) -> (list: String, fields: [(String, RuleCompleteType)]) {
        switch kind {
        case .search, .explore:
            return ("bookList", [
                ("name", .text), ("author", .text), ("kind", .text), ("intro", .text),
                ("wordCount", .text), ("lastChapter", .text),
                ("coverUrl", .image), ("bookUrl", .link)
            ])
        case .bookInfo:
            return ("init", [
                ("name", .text), ("author", .text), ("kind", .text), ("intro", .text),
                ("wordCount", .text), ("lastChapter", .text), ("downloadUrls", .text),
                ("coverUrl", .image), ("tocUrl", .link)
            ])
        case .toc:
            return ("chapterList", [
                ("chapterName", .text), ("chapterUrl", .link), ("nextTocUrl", .link)
            ])
        case .content:
            return ("", [
                ("content", .text), ("title", .text), ("nextContentUrl", .link)
            ])
        }
    }

    /// Completes the sub-rules of a rule group.
    ///
    /// - Parameters:
    ///   - ruleJSON: the rule group as a JSON document.
    ///   - kind: the kind of the rule group.
    /// - Returns: the completed rule group, or the original one when it cannot
    ///   be parsed.
    public static func complete(ruleJSON: String?, kind: SourceRuleKind) -> String? {
        guard let ruleJSON, !ruleJSON.isEmpty else { return ruleJSON }
        guard var object = (try? JSONValue.parse(ruleJSON))?.objectValue else { return ruleJSON }
        let (listField, fields) = fields(for: kind)
        let listRule = object[listField]?.stringValue
        var changed = false
        for (field, type) in fields {
            guard let value = object[field]?.stringValue, !value.isEmpty else { continue }
            guard let completed = RuleComplete.autoComplete(rules: value, preRule: listRule, type: type),
                  completed != value else { continue }
            object[field] = .string(completed)
            changed = true
        }
        guard changed else { return ruleJSON }
        return JSONValue.object(object).jsonString
    }
}
