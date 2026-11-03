import Foundation

/// Faithful port of `io.legado.app.model.analyzeRule.AnalyzeByRegex`.
///
/// Upstream: app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByRegex.kt (60 lines)
///
/// The regex strategy is *staged*: a rule may consist of several regular
/// expressions separated by `&&`. Every stage but the last concatenates all of
/// its matches and feeds them into the next stage, so
/// `<a href="(.*?)".*?<b>(.*?)</b>`-style rules work as a pipeline.
///
/// The last stage produces the groups: element 0 is the whole match, the
/// remaining entries are the capture groups.
public final class RegexMatcher: RuleMatcher {

    public init() {}

    // MARK: - RuleMatcher

    /// Port of `AnalyzeByRegex.getElement`.
    ///
    /// Only `element` and `elements` are meaningful for the regex strategy —
    /// upstream never routes `getString` / `getStringList` through it (those
    /// fall through to `else -> rule`), but the protocol requires them.
    public func element(_ content: RuleValue, _ rule: String) throws -> RuleValue? {
        let regs = rule.splitNotBlank("&&")
        guard let groups = try RegexMatcher.getElement(content.textValue, regs) else { return nil }
        return .list(groups.map { RuleValue.text($0) })
    }

    /// Port of `AnalyzeByRegex.getElements`.
    public func elements(_ content: RuleValue, _ rule: String) throws -> [RuleValue] {
        let regs = rule.splitNotBlank("&&")
        let books = try RegexMatcher.getElements(content.textValue, regs)
        return books.map { book in
            RuleValue.list(book.map { RuleValue.text($0) })
        }
    }

    public func string(_ content: RuleValue, _ rule: String) throws -> String? {
        rule.isEmpty ? nil : rule
    }

    public func stringList(_ content: RuleValue, _ rule: String) throws -> [String]? {
        rule.isEmpty ? [] : [rule]
    }

    public func firstString(_ content: RuleValue, _ rule: String) throws -> String? {
        rule.isEmpty ? nil : rule
    }

    // MARK: - The staged algorithm

    /// Port of `AnalyzeByRegex.getElement`.
    ///
    /// - Parameters:
    ///   - res: the text to match.
    ///   - regs: the stages of the rule.
    ///   - index: the current stage.
    static func getElement(_ res: String, _ regs: [String], _ index: Int = 0) throws -> [String]? {
        guard index < regs.count else { return nil }
        let results = try matches(regs[index], in: res)
        if results.isEmpty { return nil }

        // The last rule decides whether the groups are returned.
        if index + 1 == regs.count {
            return groups(of: results[0], in: res)
        }

        var concatenated = ""
        for result in results {
            if let range = Range(result.range, in: res) {
                concatenated += String(res[range])
            }
        }
        return try getElement(concatenated, regs, index + 1)
    }

    /// Port of `AnalyzeByRegex.getElements`.
    static func getElements(_ res: String, _ regs: [String], _ index: Int = 0) throws -> [[String]] {
        guard index < regs.count else { return [] }
        let results = try matches(regs[index], in: res)
        if results.isEmpty { return [] }

        if index + 1 == regs.count {
            var books: [[String]] = []
            for result in results {
                books.append(groups(of: result, in: res))
            }
            return books
        }

        var concatenated = ""
        for result in results {
            if let range = Range(result.range, in: res) {
                concatenated += String(res[range])
            }
        }
        return try getElements(concatenated, regs, index + 1)
    }

    // MARK: - Helpers

    /// All matches of `pattern` in `text`.
    private static func matches(_ pattern: String, in text: String) throws -> [NSTextCheckingResult] {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            throw RegexMatcherError.invalidPattern(pattern)
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range)
    }

    /// The capture groups of a match: index 0 is the whole match.
    private static func groups(of result: NSTextCheckingResult, in text: String) -> [String] {
        var info: [String] = []
        for index in 0..<result.numberOfRanges {
            let range = result.range(at: index)
            if range.location == NSNotFound {
                info.append("")
            } else if let swiftRange = Range(range, in: text) {
                info.append(String(text[swiftRange]))
            } else {
                info.append("")
            }
        }
        return info
    }
}

/// Errors raised by the regex matcher.
public enum RegexMatcherError: Error, Equatable {
    /// The pattern could not be compiled.
    case invalidPattern(String)
}
