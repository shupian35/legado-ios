import Foundation
import SwiftSoup

/// Faithful port of `io.legado.app.model.analyzeRule.AnalyzeByJSoup`.
///
/// Upstream: app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt
///
/// The Android app uses `jsoup` for HTML parsing and CSS selection. The iOS
/// port uses **SwiftSoup**, which is a direct port of jsoup and therefore has
/// the same selector semantics (`tag`, `.class`, `#id`, `[attr=value]`, `>` …).
///
/// The rule language that this file implements has three layers:
///
/// 1. `@CSS:` rules are plain CSS selectors with a trailing *terminal* rule
///    separated by `@` — e.g. `div.book@text`, `div.book@href`.
/// 2. Non-`@CSS:` rules use the legacy "jsoup chain" syntax, where `@`
///    separates the steps: `div.list@div.item@text`.
/// 3. Every step may carry an *index* suffix — either the legacy
///    `tag.div.-1:10:2` form or the JSONPath-like `tag.div[-1, 3:-2:-10, 2]`
///    form (see `ElementsSingle`).
public final class CSSMatcher: RuleMatcher {

    public init() {}

    // MARK: - Parsing

    /// Port of `AnalyzeByJSoup.parse`.
    ///
    /// * an already parsed element is used as-is;
    /// * a document that starts with `<?xml` is parsed with the XML parser;
    /// * everything else is parsed as HTML.
    private static func parse(_ content: RuleValue) throws -> Element {
        if case .node(let node) = content, let element = node as? Element {
            return element
        }
        let text = content.textValue
        if text.lowercased().hasPrefix("<?xml") {
            return try SwiftSoup.parseXML(text)
        }
        return try SwiftSoup.parse(text)
    }

    // MARK: - RuleMatcher

    /// Port of `AnalyzeByJSoup.getString`.
    public func string(_ content: RuleValue, _ rule: String) throws -> String? {
        if rule.isEmpty { return nil }
        let list = try list(content, rule)
        if list.isEmpty { return nil }
        if list.count == 1 { return list[0] }
        return list.joined(separator: "\n")
    }

    /// Port of `AnalyzeByJSoup.getString0` — the first match only.
    public func firstString(_ content: RuleValue, _ rule: String) throws -> String? {
        let list = try list(content, rule)
        if list.isEmpty { return "" }
        return list[0]
    }

    /// Port of `AnalyzeByJSoup.getStringList`.
    public func stringList(_ content: RuleValue, _ rule: String) throws -> [String]? {
        try list(content, rule)
    }

    /// The body of `AnalyzeByJSoup.getStringList`.
    private func list(_ content: RuleValue, _ rule: String) throws -> [String] {
        var textS: [String] = []
        if rule.isEmpty { return textS }

        let element = try CSSMatcher.parse(content)
        let sourceRule = CSSSourceRule(rule)

        if sourceRule.elementsRule.isEmpty {
            textS.append(element.data())
        } else {
            let ruleAnalyzes = RuleAnalyzer(sourceRule.elementsRule)
            let ruleStrS = try ruleAnalyzes.splitRule("&&", "||", "%%")

            var results: [[String]] = []
            for ruleStrX in ruleStrS {
                var temp: [String] = []
                if sourceRule.isCss {
                    guard let lastIndex = ruleStrX.lastIndex(of: "@") else {
                        // Upstream would throw StringIndexOutOfBoundsException
                        // here because `lastIndexOf('@')` returns -1.
                        throw CSSMatcherError.missingTerminalRule(ruleStrX)
                    }
                    let selector = String(ruleStrX[ruleStrX.startIndex..<lastIndex])
                    let terminal = String(ruleStrX[ruleStrX.index(after: lastIndex)...])
                    temp = try getResultLast(Array(try element.select(selector)), terminal)
                } else {
                    temp = try getResultList(element, ruleStrX) ?? []
                }

                if !temp.isEmpty {
                    results.append(temp)
                    if ruleAnalyzes.elementsType == "||" { break }
                }
            }
            if !results.isEmpty {
                if ruleAnalyzes.elementsType == "%%" {
                    for i in results[0].indices {
                        for temp in results where i < temp.count {
                            textS.append(temp[i])
                        }
                    }
                } else {
                    for temp in results {
                        textS.append(contentsOf: temp)
                    }
                }
            }
        }
        return textS
    }

    /// Port of `AnalyzeByJSoup.getElement`.
    public func element(_ content: RuleValue, _ rule: String) throws -> RuleValue? {
        let elements = try getElements(try CSSMatcher.parse(content), rule)
        guard let first = elements.first else { return nil }
        return .node(first)
    }

    /// Port of `AnalyzeByJSoup.getElements`.
    public func elements(_ content: RuleValue, _ rule: String) throws -> [RuleValue] {
        let elements = try getElements(try CSSMatcher.parse(content), rule)
        return elements.map { RuleValue.node($0) }
    }

    // MARK: - Element selection

    /// Port of the private `AnalyzeByJSoup.getElements(temp, rule)`.
    private func getElements(_ temp: Element?, _ rule: String) throws -> [Element] {
        guard let temp, !rule.isEmpty else { return [] }

        var elements: [Element] = []

        let sourceRule = CSSSourceRule(rule)
        let ruleAnalyzes = RuleAnalyzer(sourceRule.elementsRule)
        let ruleStrS = try ruleAnalyzes.splitRule("&&", "||", "%%")

        var elementsList: [[Element]] = []
        if sourceRule.isCss {
            for ruleStr in ruleStrS {
                let tempS = Array(try temp.select(ruleStr))
                elementsList.append(tempS)
                if !tempS.isEmpty && ruleAnalyzes.elementsType == "||" {
                    break
                }
            }
        } else {
            for ruleStr in ruleStrS {
                let rsRule = RuleAnalyzer(ruleStr)
                rsRule.trim()   // trim the leading "@" / whitespace
                let rs = try rsRule.splitRule("@")

                var el: [Element] = []
                if rs.count > 1 {
                    // The parts are applied as a chain: every step narrows the
                    // result of the previous one.
                    el = [temp]
                    for rl in rs {
                        var es: [Element] = []
                        for et in el {
                            es.append(contentsOf: try getElements(et, rl))
                        }
                        el = es
                    }
                } else {
                    el = try ElementsSingle().getElementsSingle(temp, ruleStr)
                }

                elementsList.append(el)
                if !el.isEmpty && ruleAnalyzes.elementsType == "||" {
                    break
                }
            }
        }
        if !elementsList.isEmpty {
            if ruleAnalyzes.elementsType == "%%" {
                for i in 0..<elementsList[0].count {
                    for es in elementsList where i < es.count {
                        elements.append(es[i])
                    }
                }
            } else {
                for es in elementsList {
                    elements.append(contentsOf: es)
                }
            }
        }
        return elements
    }

    /// Port of the private `AnalyzeByJSoup.getResultList`.
    private func getResultList(_ element: Element, _ ruleStr: String) throws -> [String]? {
        if ruleStr.isEmpty { return nil }

        var elements: [Element] = [element]

        let rule = RuleAnalyzer(ruleStr)
        rule.trim()
        let rules = try rule.splitRule("@")

        let last = rules.count - 1
        if last < 0 { return nil }
        for i in 0..<last {
            var es: [Element] = []
            for elt in elements {
                es.append(contentsOf: try ElementsSingle().getElementsSingle(elt, rules[i]))
            }
            elements = es
        }
        if elements.isEmpty { return nil }
        return try getResultLast(elements, rules[last])
    }

    /// Port of the private `AnalyzeByJSoup.getResultLast`.
    ///
    /// The terminal rule decides what is extracted from the matched elements:
    /// `text`, `textNodes`, `ownText`, `html`, `all` or an attribute name.
    private func getResultLast(_ elements: [Element], _ lastRule: String) throws -> [String] {
        var textS: [String] = []
        switch lastRule {
        case "text":
            for element in elements {
                let text = try element.text()
                if !text.isEmpty { textS.append(text) }
            }
        case "textNodes":
            for element in elements {
                var tn: [String] = []
                for item in element.textNodes() {
                    let text = item.text().trimmingJavaSpaces()
                    if !text.isEmpty { tn.append(text) }
                }
                if !tn.isEmpty { textS.append(tn.joined(separator: "\n")) }
            }
        case "ownText":
            for element in elements {
                let text = element.ownText()
                if !text.isEmpty { textS.append(text) }
            }
        case "html":
            for element in elements {
                for script in try element.select("script") { try script.remove() }
                for style in try element.select("style") { try style.remove() }
            }
            let html = try outerHtml(elements)
            if !html.isEmpty { textS.append(html) }
        case "all":
            textS.append(try outerHtml(elements))
        default:
            for element in elements {
                let url = try element.attr(lastRule)
                if url.isBlank || textS.contains(url) { continue }
                textS.append(url)
            }
        }
        return textS
    }

    /// The outer HTML of a list of elements, joined without a separator.
    private func outerHtml(_ elements: [Element]) throws -> String {
        var result = ""
        for element in elements {
            result += try element.outerHtml()
        }
        return result
    }
}

/// Port of the inner `AnalyzeByJSoup.SourceRule` class.
struct CSSSourceRule {
    /// Whether the rule is a plain CSS selector (`@CSS:` prefix).
    var isCss = false
    /// The rule with the `@CSS:` prefix removed.
    var elementsRule: String

    init(_ ruleStr: String) {
        if ruleStr.lowercased().hasPrefix("@css:") {
            isCss = true
            elementsRule = String(ruleStr.dropFirst(5)).trimmingJavaSpaces()
        } else {
            elementsRule = ruleStr
        }
    }
}

/// Errors raised by the CSS matcher.
public enum CSSMatcherError: Error, Equatable {
    /// A `@CSS:` rule without a trailing terminal rule (`…@text`).
    case missingTerminalRule(String)
}
