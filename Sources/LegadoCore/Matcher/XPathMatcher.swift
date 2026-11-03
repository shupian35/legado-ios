//
//  XPathMatcher.swift
//  LegadoCore
//
//  Port of `app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByXPath.kt`.
//
//  Upstream evaluates XPath rules with `org.seimicrawler.xpath.JXDocument`;
//  the port uses the hand-written engine in `XPath.swift`.
//

import Foundation
import SwiftSoup

public final class XPathMatcher: RuleMatcher {

    public init() {}

    // MARK: - RuleMatcher

    public func string(_ content: RuleValue, _ rule: String) throws -> String? {
        let rules = try RuleAnalyzer(rule).splitRule("&&", "||")
        if rules.count == 1 {
            let nodes = try select(content, rule)
            guard !nodes.isEmpty else { return nil }
            return nodes.map(\.stringValue).joined(separator: "\n")
        }
        var textList: [String] = []
        let analyzer = RuleAnalyzer(rule)
        for part in rules {
            guard let text = try self.string(content, part), !text.isEmpty else { continue }
            textList.append(text)
            if analyzer.elementsType == "||" { break }
        }
        return textList.joined(separator: "\n")
    }

    public func stringList(_ content: RuleValue, _ rule: String) throws -> [String]? {
        let analyzer = RuleAnalyzer(rule)
        let rules = try analyzer.splitRule("&&", "||", "%%")
        if rules.count == 1 {
            return try select(content, rule).map(\.stringValue)
        }
        var results: [[String]] = []
        for part in rules {
            let temp = try stringList(content, part) ?? []
            if !temp.isEmpty {
                results.append(temp)
                if analyzer.elementsType == "||" { break }
            }
        }
        if results.isEmpty { return [] }
        if analyzer.elementsType == "%%" {
            var result: [String] = []
            for index in results[0].indices {
                for temp in results where index < temp.count {
                    result.append(temp[index])
                }
            }
            return result
        }
        return results.flatMap { $0 }
    }

    public func element(_ content: RuleValue, _ rule: String) throws -> RuleValue? {
        guard let node = try select(content, rule).first else { return nil }
        return .node(node)
    }

    public func elements(_ content: RuleValue, _ rule: String) throws -> [RuleValue] {
        try select(content, rule).map { RuleValue.node($0) }
    }

    public func firstString(_ content: RuleValue, _ rule: String) throws -> String? {
        guard let node = try select(content, rule).first else { return nil }
        return node.stringValue
    }

    // MARK: - Upstream `getElements`

    private func select(_ content: RuleValue, _ rule: String) throws -> [XPathNode] {
        if rule.isEmpty { return [] }
        let analyzer = RuleAnalyzer(rule)
        let rules = try analyzer.splitRule("&&", "||", "%%")
        if rules.count == 1 {
            return try evaluate(content, rules[0])
        }
        var results: [[XPathNode]] = []
        for part in rules {
            let temp = try select(content, part)
            if !temp.isEmpty {
                results.append(temp)
                if analyzer.elementsType == "||" { break }
            }
        }
        if results.isEmpty { return [] }
        if analyzer.elementsType == "%%" {
            var result: [XPathNode] = []
            for index in results[0].indices {
                for temp in results where index < temp.count {
                    result.append(temp[index])
                }
            }
            return result
        }
        return results.flatMap { $0 }
    }

    private func evaluate(_ content: RuleValue, _ rule: String) throws -> [XPathNode] {
        let document = try XPathMatcher.makeDocument(content)
        return try document.select(rule)
    }

    // MARK: - Upstream `parse` / `strToJXDocument`

    static func makeDocument(_ content: RuleValue) throws -> XPathDocument {
        switch content {
        case .text(let text):
            return try XPathMatcher.strToDocument(text)
        case .node(let node):
            if let element = node as? SwiftSoup.Element {
                return XPathDocument.parse(element: element)
            }
            if let xpathNode = node as? XPathNode {
                return XPathDocument(root: xpathNode)
            }
            return try XPathMatcher.strToDocument(node.nodeText)
        default:
            return try XPathMatcher.strToDocument(content.textValue)
        }
    }

    /// Port of upstream `strToJXDocument`: the HTML is wrapped in a table when
    /// it is a bare table row or cell, so that XPath expressions like
    /// `//td[1]` work on fragmentary responses.
    static func strToDocument(_ html: String) throws -> XPathDocument {
        var text = html
        if text.hasSuffix("</td>") {
            text = "<tr>\(text)</tr>"
        }
        if text.hasSuffix("</tr>") || text.hasSuffix("</tbody>") {
            text = "<table>\(text)</table>"
        }
        return try XPathDocument.parse(text)
    }
}
