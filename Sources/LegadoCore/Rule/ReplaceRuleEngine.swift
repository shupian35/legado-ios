//
//  ReplaceRuleEngine.swift
//  LegadoCore
//
//  The Swift port of the replace / purify rules.
//
//  Upstream references:
//    * data/entities/ReplaceRule.kt      — the entity and `isValid()`
//    * help/ReplaceAnalyzer.kt           — the JSON import
//    * utils/RegexExtensions.kt          — the timeout guarded regex replace
//    * data/entities/BookChapter.kt      — `getDisplayTitle()`
//    * help/book/ContentProcessor.kt     — `getContent()`
//

import Foundation

/// The errors the replace engine can raise.
public enum ReplaceRuleError: Error, Equatable {
    /// The rule has an empty pattern or an invalid regular expression.
    case invalidRule(String)
    /// The replacement did not finish within the rule timeout.
    case timeout(String)
    /// A `@js:` replacement failed.
    case scriptFailed(String)
}

/// The result of processing a chapter — upstream `BookContent`.
public struct ProcessedContent {
    /// Whether the duplicated title was removed from the content.
    public var sameTitleRemoved: Bool
    /// The paragraphs of the chapter.
    public var contents: [String]
    /// The rules that actually changed the content.
    public var effectiveReplaceRules: [ReplaceRule]

    public init(sameTitleRemoved: Bool = false, contents: [String] = [], effectiveReplaceRules: [ReplaceRule] = []) {
        self.sameTitleRemoved = sameTitleRemoved
        self.contents = contents
        self.effectiveReplaceRules = effectiveReplaceRules
    }
}

/// Converts between simplified and traditional Chinese.
///
/// Upstream uses `io.legado.app.utils.ChineseUtils`, which wraps the
/// `quickChineseTransfer` tables. The tables are large, so the port keeps the
/// conversion behind a protocol and ships a no-op implementation.
public protocol ChineseConverting {
    func toSimplified(_ text: String) -> String
    func toTraditional(_ text: String) -> String
}

/// A converter that leaves the text unchanged.
public final class NoChineseConverter: ChineseConverting {
    public init() {}
    public func toSimplified(_ text: String) -> String { text }
    public func toTraditional(_ text: String) -> String { text }
}

/// The Chinese conversion mode — upstream `AppConfig.chineseConverterType`.
///
/// 0 = off, 1 = traditional to simplified, 2 = simplified to traditional.
public enum ChineseConversionMode: Int, CaseIterable, Sendable {
    case off = 0
    case traditionalToSimplified = 1
    case simplifiedToTraditional = 2
}

/// Re-applies the paragraphs of a chapter — upstream `ContentHelp.reSegment`.
///
/// The upstream implementation is a 600 line heuristic; the port keeps it
/// behind a protocol so that it can be plugged in.
public protocol ContentResegmenter {
    func reSegment(_ content: String, chapterName: String) -> String
}

/// A resegmenter that leaves the content unchanged.
public final class NoOpResegmenter: ContentResegmenter {
    public init() {}
    public func reSegment(_ content: String, chapterName: String) -> String { content }
}

/// The replace / purify engine.
public enum ReplaceRuleEngine {

    // MARK: - The rule itself

    /// Whether the rule can be applied — upstream `ReplaceRule.isValid()`.
    public static func isValid(_ rule: ReplaceRule) -> Bool {
        if rule.pattern.isEmpty { return false }
        if rule.isRegex {
            if (try? NSRegularExpression(pattern: rule.pattern)) == nil { return false }
            // `Pattern.compile` succeeds but the replacement can time out —
            // that usually means the expression was not finished being edited.
            if rule.pattern.hasSuffix("|") && !rule.pattern.hasSuffix("\\|") {
                return false
            }
        }
        return true
    }

    /// The effective timeout — upstream `ReplaceRule.getValidTimeoutMillisecond()`.
    public static func validTimeoutMillisecond(_ rule: ReplaceRule) -> Int64 {
        rule.timeoutMillisecond <= 0 ? 3000 : rule.timeoutMillisecond
    }

    /// Applies a single rule to a text.
    ///
    /// Upstream `CharSequence.replace(regex, replacement, timeout)`; a
    /// replacement that starts with `@js:` is evaluated as JavaScript for
    /// every match, with the matched text bound to `result`.
    public static func apply(
        _ rule: ReplaceRule,
        to text: String,
        scriptEngine: RuleScriptEngine? = nil
    ) throws -> String {
        if rule.pattern.isEmpty { return text }
        if !rule.isRegex {
            return text.replacingOccurrences(of: rule.pattern, with: rule.replacement)
        }
        guard let expression = try? NSRegularExpression(pattern: rule.pattern) else {
            throw ReplaceRuleError.invalidRule(rule.pattern)
        }
        let isJs = rule.replacement.hasPrefix("@js:")
        let replacement = isJs ? String(rule.replacement.dropFirst(4)) : rule.replacement
        let timeout = validTimeoutMillisecond(rule)
        let start = Date()
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        var result = ""
        var last = 0
        expression.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match else { return }
            let matched = nsText.substring(with: match.range)
            var replacementText = replacement
            if isJs {
                if let engine = scriptEngine {
                    do {
                        let value = try engine.evaluate(replacement, bindings: ["result": .text(matched)])
                        replacementText = value.textValue
                    } catch {
                        replacementText = ""
                    }
                } else {
                    replacementText = ""
                }
            }
            let expanded = ReplaceRuleEngine.expand(replacementText, match: match, text: nsText)
            result += nsText.substring(with: NSRange(location: last, length: match.range.location - last))
            result += expanded
            last = match.range.location + match.range.length
        }
        result += nsText.substring(from: last)
        if Date().timeIntervalSince(start) * 1000 > Double(timeout) {
            throw ReplaceRuleError.timeout(rule.name)
        }
        return result
    }

    /// Expands the `$1` / `${name}` references of a replacement.
    private static func expand(_ replacement: String, match: NSTextCheckingResult, text: NSString) -> String {
        guard replacement.contains("$") else { return replacement }
        var result = ""
        var index = replacement.startIndex
        while index < replacement.endIndex {
            let character = replacement[index]
            if character != "$" {
                result.append(character)
                index = replacement.index(after: index)
                continue
            }
            let next = replacement.index(after: index)
            guard next < replacement.endIndex else {
                result.append(character)
                break
            }
            if replacement[next] == "$" {
                result.append("$")
                index = replacement.index(after: next)
                continue
            }
            if replacement[next] == "{" {
                guard let close = replacement[next...].firstIndex(of: "}") else {
                    result.append(character)
                    index = next
                    continue
                }
                let name = String(replacement[replacement.index(after: next)..<close])
                if match.range(withName: name).location != NSNotFound {
                    result.append(text.substring(with: match.range(withName: name)))
                }
                index = replacement.index(after: close)
                continue
            }
            var digits = ""
            var cursor = next
            while cursor < replacement.endIndex, replacement[cursor].isNumber, digits.count < 2 {
                digits.append(replacement[cursor])
                cursor = replacement.index(after: cursor)
            }
            if digits.isEmpty {
                result.append(character)
                index = next
                continue
            }
            let groupNumber = Int(digits)!
            if groupNumber < match.numberOfRanges {
                result.append(text.substring(with: match.range(at: groupNumber)))
            }
            index = cursor
        }
        return result
    }

    // MARK: - The chapter title

    /// The display title of a chapter — upstream `BookChapter.getDisplayTitle()`.
    public static func displayTitle(
        _ chapter: BookChapter,
        replaceRules: [ReplaceRule]?,
        useReplace: Bool = true,
        chineseConvert: Bool = true,
        conversionMode: ChineseConversionMode = .off,
        converter: ChineseConverting = NoChineseConverter(),
        scriptEngine: RuleScriptEngine? = nil
    ) throws -> String {
        var displayTitle = chapter.title.replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        if chineseConvert {
            switch conversionMode {
            case .traditionalToSimplified:
                displayTitle = converter.toSimplified(displayTitle)
            case .simplifiedToTraditional:
                displayTitle = converter.toTraditional(displayTitle)
            case .off:
                break
            }
        }
        if useReplace, let replaceRules {
            for rule in replaceRules where !rule.pattern.isEmpty {
                do {
                    let replaced = try apply(rule, to: displayTitle, scriptEngine: scriptEngine)
                    if !replaced.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        displayTitle = replaced
                    }
                } catch {
                    // Upstream logs the error and keeps the previous title.
                }
            }
        }
        return displayTitle
    }

    // MARK: - The chapter content

    /// Processes the content of a chapter — upstream `ContentProcessor.getContent()`.
    public static func processContent(
        book: Book,
        chapter: BookChapter,
        content: String,
        includeTitle: Bool = true,
        useReplace: Bool = true,
        chineseConvert: Bool = true,
        reSegment: Bool = true,
        titleRules: [ReplaceRule],
        contentRules: [ReplaceRule],
        paragraphIndent: String = "　　",
        conversionMode: ChineseConversionMode = .off,
        converter: ChineseConverting = NoChineseConverter(),
        resegmenter: ContentResegmenter = NoOpResegmenter(),
        scriptEngine: RuleScriptEngine? = nil,
        removeSameTitle: Bool = true
    ) throws -> ProcessedContent {
        var text = content
        var sameTitleRemoved = false
        var effectiveReplaceRules: [ReplaceRule] = []
        if content != "null" {
            // Remove the duplicated title.
            do {
                let name = NSRegularExpression.escapedPattern(for: book.name)
                var title = NSRegularExpression.escapedPattern(for: chapter.title)
                    .replacingOccurrences(of: "\\s+", with: "\\s*")
                var pattern = "^(\\s|\\p{P}|\(name))*\(title)(\\s)*"
                if removeSameTitle, let expression = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(text.startIndex..<text.endIndex, in: text)
                    if let match = expression.firstMatch(in: text, options: [], range: range) {
                        text = String(text.dropFirst(match.range.location + match.range.length))
                        sameTitleRemoved = true
                    } else if useReplace && book.useReplaceRule {
                        title = NSRegularExpression.escapedPattern(for: try displayTitle(
                            chapter,
                            replaceRules: titleRules,
                            useReplace: useReplace,
                            chineseConvert: false
                        ))
                        pattern = "^(\\s|\\p{P}|\(name))*\(title)(\\s)*"
                        if let expression = try? NSRegularExpression(pattern: pattern) {
                            let range = NSRange(text.startIndex..<text.endIndex, in: text)
                            if let match = expression.firstMatch(in: text, options: [], range: range) {
                                text = String(text.dropFirst(match.range.location + match.range.length))
                                sameTitleRemoved = true
                            }
                        }
                    }
                }
            } catch {
                // Upstream logs "去除重复标题出错" and keeps the content.
            }
            if reSegment && book.reSegment {
                text = resegmenter.reSegment(text, chapterName: chapter.title)
            }
            if chineseConvert {
                switch conversionMode {
                case .traditionalToSimplified:
                    text = converter.toSimplified(text)
                case .simplifiedToTraditional:
                    text = converter.toTraditional(text)
                case .off:
                    break
                }
            }
            if useReplace && book.useReplaceRule {
                effectiveReplaceRules = []
                text = text
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: "\n")
                for rule in contentRules {
                    if rule.pattern.isEmpty { continue }
                    do {
                        let replaced = try apply(rule, to: text, scriptEngine: scriptEngine)
                        if replaced != text {
                            effectiveReplaceRules.append(rule)
                            text = replaced
                        }
                    } catch {
                        // Upstream logs the error and keeps the content.
                    }
                }
            }
        }
        if includeTitle {
            // Add the title back.
            let title = try displayTitle(
                chapter,
                replaceRules: titleRules,
                useReplace: useReplace && book.useReplaceRule,
                chineseConvert: chineseConvert,
                conversionMode: conversionMode,
                converter: converter,
                scriptEngine: scriptEngine
            )
            text = title + "\n" + text
        }
        var contents: [String] = []
        for line in text.components(separatedBy: "\n") {
            let paragraph = line.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "　"))
            if paragraph.isEmpty { continue }
            if contents.isEmpty && includeTitle {
                contents.append(paragraph)
            } else {
                contents.append(paragraphIndent + paragraph)
            }
        }
        return ProcessedContent(
            sameTitleRemoved: sameTitleRemoved,
            contents: contents,
            effectiveReplaceRules: effectiveReplaceRules
        )
    }

    // MARK: - The JSON import

    /// Parses a replace rule from JSON — upstream `ReplaceAnalyzer.jsonToReplaceRule()`.
    ///
    /// The modern format uses the entity field names; the legacy format uses
    /// `regex`, `replaceSummary`, `useTo`, `enable` and `serialNumber`.
    public static func jsonToReplaceRule(_ json: String) throws -> ReplaceRule {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = try? JSONValue.parse(trimmed), case .object(let object) = value else {
            throw ReplaceRuleError.invalidRule(trimmed)
        }
        var rule = ReplaceRule()
        if let pattern = object["pattern"]?.textValue, !pattern.isEmpty {
            rule.id = object["id"]?.intValue ?? Int64(Date().timeIntervalSince1970 * 1000)
            rule.name = object["name"]?.textValue ?? ""
            rule.group = object["group"]?.textValue
            rule.pattern = pattern
            rule.replacement = object["replacement"]?.textValue ?? ""
            rule.scope = object["scope"]?.textValue
            rule.scopeTitle = object["scopeTitle"]?.boolValue ?? false
            rule.scopeContent = object["scopeContent"]?.boolValue ?? true
            rule.excludeScope = object["excludeScope"]?.textValue
            rule.isEnabled = object["isEnabled"]?.boolValue ?? true
            rule.isRegex = object["isRegex"]?.boolValue ?? true
            rule.timeoutMillisecond = object["timeoutMillisecond"]?.intValue ?? 3000
            rule.sortOrder = object["sortOrder"]?.intValue ?? 0
            return rule
        }
        // The legacy format.
        rule.id = object["id"]?.intValue ?? Int64(Date().timeIntervalSince1970 * 1000)
        rule.pattern = object["regex"]?.textValue ?? ""
        if rule.pattern.isEmpty { throw ReplaceRuleError.invalidRule(trimmed) }
        rule.name = object["replaceSummary"]?.textValue ?? ""
        rule.replacement = object["replacement"]?.textValue ?? ""
        rule.isRegex = object["isRegex"]?.boolValue ?? true
        rule.scope = object["useTo"]?.textValue
        rule.isEnabled = object["enable"]?.boolValue ?? true
        rule.sortOrder = object["serialNumber"]?.intValue ?? 0
        return rule
    }

    /// Parses a list of replace rules — upstream `ReplaceAnalyzer.jsonToReplaceRules()`.
    public static func jsonToReplaceRules(_ json: String) throws -> [ReplaceRule] {
        guard let value = try? JSONValue.parse(json) else {
            throw ReplaceRuleError.invalidRule(json)
        }
        var rules: [ReplaceRule] = []
        switch value {
        case .array(let items):
            for item in items {
                let rule = try jsonToReplaceRule(item.jsonString)
                if isValid(rule) { rules.append(rule) }
            }
        case .object:
            let rule = try jsonToReplaceRule(json)
            if isValid(rule) { rules.append(rule) }
        default:
            throw ReplaceRuleError.invalidRule(json)
        }
        return rules
    }
}
