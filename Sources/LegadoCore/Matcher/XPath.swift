//
//  XPath.swift
//  LegadoCore
//
//  A focused XPath 1.0 engine.
//
//  Upstream reference: the Android app evaluates XPath rules with
//  `org.seimicrawler.xpath.JXDocument` (see
//  `app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByXPath.kt`).
//  There is no Swift equivalent on Apple platforms, so this file implements
//  the subset of XPath 1.0 that book sources actually use.
//
//  Supported: absolute/relative location paths, the child, descendant,
//  descendant-or-self, attribute, self, parent, ancestor, ancestor-or-self,
//  following-sibling, preceding-sibling, following and preceding axes; node
//  tests by name, `*`, `text()`, `node()`, `comment()`; predicates with
//  position(), last(), attribute comparisons and nested paths; the union
//  operator; and the string/number/boolean functions.
//

import Foundation
import SwiftSoup

// MARK: - DOM

public enum XPathNodeKind: Int {
    case root
    case element
    case text
    case comment
    case attribute
}

public struct XPathAttribute {
    public let name: String
    public let value: String
}

/// A node of the XPath tree.
public final class XPathNode {
    public let kind: XPathNodeKind
    public let name: String
    public var value: String = ""
    public internal(set) weak var parent: XPathNode?
    public internal(set) var children: [XPathNode] = []
    public internal(set) var attributes: [XPathAttribute] = []
    /// 1-based position among the element siblings, as used by `position()`.
    public internal(set) var position: Int = 1
    /// The SwiftSoup node this node was built from, when there is one.
    internal var source: SwiftSoup.Node?

    init(kind: XPathNodeKind, name: String) {
        self.kind = kind
        self.name = name
    }

    /// The XPath string-value of the node: the concatenated text of all
    /// descendant text nodes.
    public var stringValue: String {
        switch kind {
        case .text, .comment, .attribute:
            return value
        case .element, .root:
            var result = ""
            for child in children {
                result += child.stringValue
            }
            return result
        }
    }

    /// The concatenated text of the direct text children (XPath `text()`).
    public var directText: String {
        var result = ""
        for child in children where child.kind == .text {
            result += child.value
        }
        return result
    }

    public func attribute(_ name: String) -> String? {
        let wanted = name.lowercased()
        return attributes.first { $0.name == wanted }?.value
    }
}

// MARK: - DOMNode conformance

extension XPathNode: DOMNode {
    public var nodeTag: String { name }

    public var nodeText: String { stringValue }

    public var nodeHTML: String {
        if let element = source as? SwiftSoup.Element {
            return (try? element.outerHtml()) ?? ""
        }
        return stringValue
    }

    public var nodeAttributes: [String: String] {
        var result: [String: String] = [:]
        for attribute in attributes {
            result[attribute.name] = attribute.value
        }
        return result
    }

    public var nodeChildren: [any DOMNode] { children }
}

// MARK: - Document

/// The root of an XPath evaluation.
public final class XPathDocument {
    public let root: XPathNode

    init(root: XPathNode) {
        self.root = root
    }

    /// Builds a document from an HTML/XML string.
    public static func parse(_ text: String) throws -> XPathDocument {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let document: SwiftSoup.Document
        if trimmed.lowercased().hasPrefix("<?xml") {
            document = try SwiftSoup.parseXML(text)
        } else {
            document = try SwiftSoup.parse(text)
        }
        let root = XPathNode(kind: .root, name: "")
        for child in document.getChildNodes() {
            guard let built = XPathDocument.build(from: child) else { continue }
            built.parent = root
            root.children.append(built)
        }
        return XPathDocument(root: root)
    }

    /// Builds a document from an already parsed element.
    public static func parse(element: SwiftSoup.Element) -> XPathDocument {
        let root = XPathNode(kind: .root, name: "")
        appendChildren(of: element, to: root)
        return XPathDocument(root: root)
    }

    private static func appendChildren(of element: SwiftSoup.Element, to parent: XPathNode) {
        var elementIndex = 0
        for child in element.getChildNodes() {
            guard let built = build(from: child) else { continue }
            if built.kind == .element {
                elementIndex += 1
                built.position = elementIndex
            }
            built.parent = parent
            parent.children.append(built)
        }
    }

    private static func build(from node: SwiftSoup.Node) -> XPathNode? {
        if let element = node as? SwiftSoup.Element {
            let result = XPathNode(kind: .element, name: element.tagName().lowercased())
            result.source = element
            if let attributes = element.getAttributes() {
                for attribute in attributes {
                    result.attributes.append(
                        XPathAttribute(name: attribute.getKey().lowercased(), value: attribute.getValue())
                    )
                }
            }
            appendChildren(of: element, to: result)
            return result
        }
        if let text = node as? SwiftSoup.TextNode {
            let result = XPathNode(kind: .text, name: "text()")
            result.source = text
            result.value = text.getWholeText()
            return result
        }
        if let data = node as? SwiftSoup.DataNode {
            let result = XPathNode(kind: .text, name: "text()")
            result.source = data
            result.value = data.getWholeData()
            return result
        }
        if let comment = node as? SwiftSoup.Comment {
            let result = XPathNode(kind: .comment, name: "comment()")
            result.source = comment
            result.value = comment.getData()
            return result
        }
        return nil
    }

    /// Evaluates `path` and returns every matching node.
    public func select(_ path: String) throws -> [XPathNode] {
        var parser = XPathParser(path)
        let expression = try parser.parseDocument()
        let evaluator = XPathEvaluator(document: self)
        switch try evaluator.evaluate(expression, contextNode: root, position: 1, size: 1) {
        case .nodes(let nodes):
            return nodes
        case .string(let text):
            return [XPathNode(kind: .text, name: "text()").withValue(text)]
        case .number(let number):
            let text = number == number.rounded() ? String(Int(number)) : String(number)
            return [XPathNode(kind: .text, name: "text()").withValue(text)]
        case .boolean(let flag):
            return [XPathNode(kind: .text, name: "text()").withValue(flag ? "true" : "false")]
        }
    }
}

private extension XPathNode {
    func withValue(_ text: String) -> XPathNode {
        let copy = XPathNode(kind: kind, name: name)
        copy.value = text
        return copy
    }
}

// MARK: - AST

public indirect enum XPathAxis {
    case child
    case descendant
    case descendantOrSelf
    case attribute
    case selfAxis
    case parent
    case ancestor
    case ancestorOrSelf
    case followingSibling
    case precedingSibling
    case following
    case preceding
}

public indirect enum XPathNodeTest {
    case name(String)
    case any
    case kind(XPathNodeKind)
}

public struct XPathStep {
    public var axis: XPathAxis = .child
    public var test: XPathNodeTest = .any
    public var predicates: [XPathExpr] = []
}

public indirect enum XPathNodeExpr {
    case root
    case context
    case node(XPathNode)
}

public indirect enum XPathPathExpr {
    case absolute(steps: [XPathStep])
    case relative(start: XPathNodeExpr, steps: [XPathStep])
}

public indirect enum XPathExpr {
    case literal(String)
    case number(Double)
    case path(XPathPathExpr)
    case binary(String, XPathExpr, XPathExpr)
    case unaryMinus(XPathExpr)
    case function(String, [XPathExpr])
    case variable(String)
}

// MARK: - Parser

public enum XPathError: Error {
    case syntax(String)
}

struct XPathParser {
    /// Names that introduce a node test rather than a function call.
    static let nodeTestNames: Set<String> = ["text", "comment", "node", "processing-instruction"]

    private let chars: [Character]
    private var index = 0

    init(_ text: String) {
        chars = Array(text)
    }

    // MARK: Lexer helpers

    private var current: Character? {
        index < chars.count ? chars[index] : nil
    }

    private func peek(_ offset: Int = 1) -> Character? {
        let position = index + offset
        return position < chars.count ? chars[position] : nil
    }

    private mutating func skipWhitespace() {
        while let character = current, character == " " || character == "\t" || character == "\n" || character == "\r" {
            index += 1
        }
    }

    private mutating func match(_ text: String) -> Bool {
        let candidate = Array(text)
        guard index + candidate.count <= chars.count else { return false }
        for (offset, character) in candidate.enumerated() where chars[index + offset] != character {
            return false
        }
        index += candidate.count
        return true
    }

    private mutating func matchName(_ text: String) -> Bool {
        let saved = index
        skipWhitespace()
        defer { index = saved }
        guard let character = current, character.isLetter || character == "_" else { return false }
        let start = index
        while let character = current,
              character.isLetter || character.isNumber || character == "_" || character == "-" || character == "." {
            index += 1
        }
        let word = String(chars[start..<index])
        guard word == text else { return false }
        index += 1
        return true
    }

    private mutating func readName() -> String {
        skipWhitespace()
        guard let character = current, character.isLetter || character == "_" else { return "" }
        let start = index
        while let character = current,
              character.isLetter || character.isNumber || character == "_" || character == "-" || character == "." {
            index += 1
        }
        return String(chars[start..<index])
    }

    // MARK: Grammar

    mutating func parseDocument() throws -> XPathExpr {
        let expression = try parseExpression()
        skipWhitespace()
        if index < chars.count {
            throw XPathError.syntax("unexpected character '\(chars[index])' at \(index)")
        }
        return expression
    }

    mutating func parseExpression() throws -> XPathExpr {
        try parseOr()
    }

    private mutating func parseOr() throws -> XPathExpr {
        var left = try parseAnd()
        while true {
            skipWhitespace()
            guard matchName("or") else { break }
            let right = try parseAnd()
            left = .binary("or", left, right)
        }
        return left
    }

    private mutating func parseAnd() throws -> XPathExpr {
        var left = try parseEquality()
        while true {
            skipWhitespace()
            guard matchName("and") else { break }
            let right = try parseEquality()
            left = .binary("and", left, right)
        }
        return left
    }

    private mutating func parseEquality() throws -> XPathExpr {
        var left = try parseRelational()
        while true {
            skipWhitespace()
            if match("!=") {
                let right = try parseRelational()
                left = .binary("!=", left, right)
            } else if match("=") {
                let right = try parseRelational()
                left = .binary("=", left, right)
            } else {
                break
            }
        }
        return left
    }

    private mutating func parseRelational() throws -> XPathExpr {
        var left = try parseAdditive()
        while true {
            skipWhitespace()
            if match("<=") {
                let right = try parseAdditive()
                left = .binary("<=", left, right)
            } else if match(">=") {
                let right = try parseAdditive()
                left = .binary(">=", left, right)
            } else if match("<") {
                let right = try parseAdditive()
                left = .binary("<", left, right)
            } else if match(">") {
                let right = try parseAdditive()
                left = .binary(">", left, right)
            } else {
                break
            }
        }
        return left
    }

    private mutating func parseAdditive() throws -> XPathExpr {
        var left = try parseMultiplicative()
        while true {
            skipWhitespace()
            if match("+") {
                let right = try parseMultiplicative()
                left = .binary("+", left, right)
            } else if current == "-" , peek() != "-", !(peek() ?? " ").isNumber {
                index += 1
                let right = try parseMultiplicative()
                left = .binary("-", left, right)
            } else {
                break
            }
        }
        return left
    }

    private mutating func parseMultiplicative() throws -> XPathExpr {
        var left = try parseUnary()
        while true {
            skipWhitespace()
            if match("*") {
                let right = try parseUnary()
                left = .binary("*", left, right)
            } else if matchName("div") {
                let right = try parseUnary()
                left = .binary("div", left, right)
            } else if matchName("mod") {
                let right = try parseUnary()
                left = .binary("mod", left, right)
            } else {
                break
            }
        }
        return left
    }

    private mutating func parseUnary() throws -> XPathExpr {
        skipWhitespace()
        if current == "-" {
            index += 1
            let operand = try parseUnary()
            return .unaryMinus(operand)
        }
        return try parseUnion()
    }

    private mutating func parseUnion() throws -> XPathExpr {
        var left = try parsePath()
        while true {
            skipWhitespace()
            guard current == "|", peek() != "|" else { break }
            index += 1
            let right = try parsePath()
            left = .binary("|", left, right)
        }
        return left
    }

    private mutating func parsePath() throws -> XPathExpr {
        skipWhitespace()
        if let character = current, character == "/" {
            return try parseAbsolutePath()
        }
        if current == "[" {
            let filter = try parseFilterExpression()
            return try parseRelativeSuffix(filter)
        }
        if current == "@" {
            var descendant = false
            if match("//") { descendant = true }
            var first = try parseStep()
            if descendant { first.axis = .descendant }
            var steps: [XPathStep] = [first]
            steps.append(contentsOf: try parseSteps())
            return .path(.relative(start: .context, steps: steps))
        }
        if current == "(" {
            index += 1
            let expression = try parseExpression()
            skipWhitespace()
            guard current == ")" else { throw XPathError.syntax("expected ')'") }
            index += 1
            return try parseRelativeSuffix(expression)
        }
        if current == "$" {
            index += 1
            return .variable(readName())
        }
        if current == "'" || current == "\"" {
            return .literal(try readStringLiteral())
        }
        if let character = current, character.isNumber {
            return .number(try readNumber())
        }
        // A name: either a function call or the first step of a relative path.
        let saved = index
        let name = readName()
        skipWhitespace()
        if current == "(" && !XPathParser.nodeTestNames.contains(name) {
            index += 1
            var arguments: [XPathExpr] = []
            skipWhitespace()
            if current != ")" {
                repeat {
                    arguments.append(try parseExpression())
                    skipWhitespace()
                    if current == "," {
                        index += 1
                        continue
                    }
                    break
                } while true
            }
            guard current == ")" else { throw XPathError.syntax("expected ')'") }
            index += 1
            return .function(name, arguments)
        }
        index = saved
        // A relative location path: the first step has no separator.
        var descendant = false
        if match("//") { descendant = true }
        var first = try parseStep()
        if descendant { first.axis = .descendant }
        var steps: [XPathStep] = [first]
        steps.append(contentsOf: try parseSteps())
        return .path(.relative(start: .context, steps: steps))
    }

    private mutating func parseFilterExpression() throws -> XPathExpr {
        index += 1 // consume '['
        let expression = try parseExpression()
        skipWhitespace()
        guard current == "]" else { throw XPathError.syntax("expected ']'") }
        index += 1
        return expression
    }

    /// After a filter expression or a parenthesised expression a location path
    /// may follow.
    private mutating func parseRelativeSuffix(_ expression: XPathExpr) throws -> XPathExpr {
        skipWhitespace()
        guard current == "/" else { return expression }
        var steps: [XPathStep] = []
        while true {
            skipWhitespace()
            if match("//") {
                steps.append(XPathStep(axis: .descendantOrSelf, test: .any))
                steps.append(contentsOf: try parseSteps())
                break
            }
            if current == "/" {
                index += 1
                steps.append(contentsOf: try parseSteps())
                break
            }
            break
        }
        guard !steps.isEmpty else { return expression }
        return .path(.relative(start: .context, steps: steps))
    }

    private mutating func parseAbsolutePath() throws -> XPathExpr {
        let steps = try parseSteps()
        return .path(.absolute(steps: steps))
    }

    /// Parses a sequence of steps, each optionally preceded by `/` or `//`.
    ///
    /// `//` is turned into the `descendant` axis so that a step such as
    /// `//a[2]` filters the whole node set — matching XPath's node-set
    /// semantics.
    private mutating func parseSteps() throws -> [XPathStep] {
        var steps: [XPathStep] = []
        while true {
            var descendant = false
            if match("//") {
                descendant = true
            } else if current == "/" {
                index += 1
            } else {
                break
            }
            var step = try parseStep()
            if descendant { step.axis = .descendant }
            steps.append(step)
        }
        return steps
    }

    private mutating func parseStep() throws -> XPathStep {
        skipWhitespace()
        var step = XPathStep()
        if current == "." , peek() != "." {
            index += 1
            step.axis = .selfAxis
            step.test = .any
            return step
        }
        if match("..") {
            step.axis = .parent
            step.test = .any
            return step
        }
        if current == "@" {
            index += 1
            step.axis = .attribute
            step.test = try parseNodeTest()
        } else if let character = current, character.isLetter || character == "_" {
            let saved = index
            let name = readName()
            skipWhitespace()
            if match("::") {
                step.axis = try parseAxis(name)
                step.test = try parseNodeTest()
            } else {
                index = saved
                step.axis = .child
                step.test = try parseNodeTest()
            }
        } else {
            step.axis = .child
            step.test = try parseNodeTest()
        }
        step.predicates = try parsePredicates()
        return step
    }

    private mutating func parseAxis(_ name: String) throws -> XPathAxis {
        switch name {
        case "child": return .child
        case "descendant": return .descendant
        case "descendant-or-self": return .descendantOrSelf
        case "attribute": return .attribute
        case "self": return .selfAxis
        case "parent": return .parent
        case "ancestor": return .ancestor
        case "ancestor-or-self": return .ancestorOrSelf
        case "following-sibling": return .followingSibling
        case "preceding-sibling": return .precedingSibling
        case "following": return .following
        case "preceding": return .preceding
        default: throw XPathError.syntax("unknown axis '\(name)'")
        }
    }

    private mutating func parseNodeTest() throws -> XPathNodeTest {
        skipWhitespace()
        if current == "*" {
            index += 1
            return .any
        }
        let name = readName()
        if name.isEmpty { throw XPathError.syntax("expected a node test at \(index)") }
        skipWhitespace()
        if current == "(" {
            // `text()`, `comment()`, `node()` and `processing-instruction()`.
            index += 1
            skipWhitespace()
            if current == ")" { index += 1 }
            switch name.lowercased() {
            case "text": return .kind(.text)
            case "comment": return .kind(.comment)
            case "node", "processing-instruction": return .any
            default: return .name(name.lowercased())
            }
        }
        return .name(name.lowercased())
    }

    private mutating func parsePredicates() throws -> [XPathExpr] {
        var predicates: [XPathExpr] = []
        while true {
            skipWhitespace()
            guard current == "[" else { break }
            index += 1
            let expression = try parseExpression()
            skipWhitespace()
            guard current == "]" else { throw XPathError.syntax("expected ']'") }
            index += 1
            predicates.append(expression)
        }
        return predicates
    }

    private mutating func readStringLiteral() throws -> String {
        let quote = chars[index]
        index += 1
        var result = ""
        while index < chars.count, chars[index] != quote {
            result.append(chars[index])
            index += 1
        }
        guard index < chars.count else { throw XPathError.syntax("unterminated string") }
        index += 1
        return result
    }

    private mutating func readNumber() throws -> Double {
        let start = index
        while index < chars.count, chars[index].isNumber || chars[index] == "." {
            index += 1
        }
        guard let value = Double(String(chars[start..<index])) else {
            throw XPathError.syntax("invalid number")
        }
        return value
    }
}

// MARK: - Evaluator

enum XPathValue {
    case nodes([XPathNode])
    case string(String)
    case number(Double)
    case boolean(Bool)
}

struct XPathEvaluator {
    let document: XPathDocument

    func evaluate(
        _ expression: XPathExpr,
        contextNode: XPathNode,
        position: Int,
        size: Int
    ) throws -> XPathValue {
        switch expression {
        case .literal(let text):
            return .string(text)
        case .number(let value):
            return .number(value)
        case .variable(let name):
            return .string("")
        case .unaryMinus(let operand):
            let value = try evaluate(operand, contextNode: contextNode, position: position, size: size)
            switch value {
            case .number(let number): return .number(-number)
            default: return .number(0)
            }
        case .binary(let op, let left, let right):
            return try evaluateBinary(op, left, right, contextNode: contextNode, position: position, size: size)
        case .path(let path):
            return try evaluatePath(path, contextNode: contextNode, position: position, size: size)
        case .function(let name, let arguments):
            return try evaluateFunction(name, arguments, contextNode: contextNode, position: position, size: size)
        }
    }

    private func evaluateBinary(
        _ op: String,
        _ left: XPathExpr,
        _ right: XPathExpr,
        contextNode: XPathNode,
        position: Int,
        size: Int
    ) throws -> XPathValue {
        if op == "|" {
            let leftNodes = try nodeSet(left, contextNode: contextNode, position: position, size: size)
            let rightNodes = try nodeSet(right, contextNode: contextNode, position: position, size: size)
            var result = leftNodes
            for node in rightNodes where !result.contains(where: { $0 === node }) {
                result.append(node)
            }
            return .nodes(result)
        }

        let leftValue = try evaluate(left, contextNode: contextNode, position: position, size: size)
        let rightValue = try evaluate(right, contextNode: contextNode, position: position, size: size)

        switch op {
        case "or":
            return .boolean(boolean(leftValue) || boolean(rightValue))
        case "and":
            return .boolean(boolean(leftValue) && boolean(rightValue))
        case "=":
            return .boolean(compareEqual(leftValue, rightValue))
        case "!=":
            return .boolean(!compareEqual(leftValue, rightValue))
        case "<", "<=", ">", ">=":
            let leftNumber = number(leftValue)
            let rightNumber = number(rightValue)
            switch op {
            case "<": return .boolean(leftNumber < rightNumber)
            case "<=": return .boolean(leftNumber <= rightNumber)
            case ">": return .boolean(leftNumber > rightNumber)
            default: return .boolean(leftNumber >= rightNumber)
            }
        case "+":
            return .number(number(leftValue) + number(rightValue))
        case "-":
            return .number(number(leftValue) - number(rightValue))
        case "*":
            return .number(number(leftValue) * number(rightValue))
        case "div":
            let divisor = number(rightValue)
            return .number(divisor == 0 ? 0 : number(leftValue) / divisor)
        case "mod":
            let divisor = number(rightValue)
            return .number(divisor == 0 ? 0 : number(leftValue).truncatingRemainder(dividingBy: divisor))
        default:
            return .string("")
        }
    }

    private func evaluatePath(
        _ path: XPathPathExpr,
        contextNode: XPathNode,
        position: Int,
        size: Int
    ) throws -> XPathValue {
        var current: [XPathNode]
        let steps: [XPathStep]
        switch path {
        case .absolute(let pathSteps):
            steps = pathSteps
            current = [document.root]
        case .relative(let start, let pathSteps):
            steps = pathSteps
            switch start {
            case .root:
                current = [document.root]
            case .context:
                current = [contextNode]
            case .node(let node):
                current = [node]
            }
        }

        for step in steps {
            var next: [XPathNode] = []
            for node in current {
                let candidates = axisNodes(step.axis, node)
                let matched = candidates.filter { matches(test: step.test, node: $0) }
                var filtered = matched
                for predicate in step.predicates {
                    filtered = try applyPredicate(predicate, to: filtered, contextNode: node)
                }
                next.append(contentsOf: filtered)
            }
            current = next
        }
        return .nodes(current)
    }

    private func axisNodes(_ axis: XPathAxis, _ node: XPathNode) -> [XPathNode] {
        switch axis {
        case .child:
            return node.children
        case .selfAxis:
            return [node]
        case .descendant:
            var result: [XPathNode] = []
            for child in node.children {
                result.append(child)
                result.append(contentsOf: axisNodes(.descendant, child))
            }
            return result
        case .descendantOrSelf:
            var result: [XPathNode] = [node]
            for child in node.children {
                result.append(contentsOf: axisNodes(.descendantOrSelf, child))
            }
            return result
        case .attribute:
            return node.attributes.map {
                let attribute = XPathNode(kind: .attribute, name: $0.name)
                attribute.value = $0.value
                return attribute
            }
        case .parent:
            return node.parent.map { [$0] } ?? []
        case .ancestor:
            var result: [XPathNode] = []
            var current = node.parent
            while let node = current {
                result.append(node)
                current = node.parent
            }
            return result
        case .ancestorOrSelf:
            var result: [XPathNode] = [node]
            var current = node.parent
            while let node = current {
                result.append(node)
                current = node.parent
            }
            return result
        case .followingSibling:
            guard let parent = node.parent else { return [] }
            var result: [XPathNode] = []
            var seen = false
            for child in parent.children {
                if seen { result.append(child) }
                if child === node { seen = true }
            }
            return result
        case .precedingSibling:
            guard let parent = node.parent else { return [] }
            var result: [XPathNode] = []
            for child in parent.children {
                if child === node { break }
                result.append(child)
            }
            return Array(result.reversed())
        case .following:
            var result: [XPathNode] = []
            var ancestor = node.parent
            while let current = ancestor {
                result.append(contentsOf: axisNodes(.followingSibling, current))
                ancestor = current.parent
            }
            return result
        case .preceding:
            var result: [XPathNode] = []
            var ancestor = node.parent
            while let current = ancestor {
                result.append(contentsOf: axisNodes(.precedingSibling, current))
                ancestor = current.parent
            }
            return Array(result.reversed())
        }
    }

    private func matches(test: XPathNodeTest, node: XPathNode) -> Bool {
        switch test {
        case .any:
            return node.kind != .attribute
        case .name(let name):
            // A name test matches an element or an attribute; the axis decides
            // which one is reachable.
            return (node.kind == .element || node.kind == .attribute) && node.name == name
        case .kind(let kind):
            return node.kind == kind
        }
    }

    private func applyPredicate(
        _ predicate: XPathExpr,
        to nodes: [XPathNode],
        contextNode: XPathNode
    ) throws -> [XPathNode] {
        var result: [XPathNode] = []
        for (offset, node) in nodes.enumerated() {
            let value = try evaluate(predicate, contextNode: node, position: offset + 1, size: nodes.count)
            switch value {
            case .number(let number):
                if Int(number) == offset + 1 { result.append(node) }
            case .boolean(let flag):
                if flag { result.append(node) }
            case .string(let text):
                if !text.isEmpty { result.append(node) }
            case .nodes(let matched):
                if !matched.isEmpty { result.append(node) }
            }
        }
        return result
    }

    // MARK: Value coercion

    private func nodeSet(
        _ expression: XPathExpr,
        contextNode: XPathNode,
        position: Int,
        size: Int
    ) throws -> [XPathNode] {
        switch try evaluate(expression, contextNode: contextNode, position: position, size: size) {
        case .nodes(let nodes): return nodes
        case .string(let text): return [XPathNode(kind: .text, name: "text()").withValue(text)]
        case .number, .boolean: return []
        }
    }

    private func string(_ value: XPathValue) -> String {
        switch value {
        case .string(let text): return text
        case .number(let number): return formatNumber(number)
        case .boolean(let flag): return flag ? "true" : "false"
        case .nodes(let nodes):
            if nodes.count == 1 { return nodes[0].stringValue }
            return nodes.map(\.stringValue).joined(separator: " ")
        }
    }

    private func number(_ value: XPathValue) -> Double {
        switch value {
        case .number(let number): return number
        case .boolean(let flag): return flag ? 1 : 0
        case .string(let text): return Double(text.trimmingCharacters(in: .whitespaces)) ?? 0
        case .nodes(let nodes): return nodes.isEmpty ? 0 : (Double(nodes[0].stringValue) ?? 0)
        }
    }

    private func boolean(_ value: XPathValue) -> Bool {
        switch value {
        case .boolean(let flag): return flag
        case .number(let number): return number != 0
        case .string(let text): return !text.isEmpty
        case .nodes(let nodes): return !nodes.isEmpty
        }
    }

    private func compareEqual(_ left: XPathValue, _ right: XPathValue) -> Bool {
        switch (left, right) {
        case (.nodes(let leftNodes), .nodes(let rightNodes)):
            for leftNode in leftNodes {
                for rightNode in rightNodes where leftNode.stringValue == rightNode.stringValue {
                    return true
                }
            }
            return false
        case (.nodes(let nodes), _):
            return nodes.contains { $0.stringValue == string(right) }
        case (_, .nodes(let nodes)):
            return nodes.contains { string(left) == $0.stringValue }
        default:
            if case .boolean = left { return boolean(left) == boolean(right) }
            if case .number = left { return number(left) == number(right) }
            return string(left) == string(right)
        }
    }

    private func formatNumber(_ value: Double) -> String {
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(value)
    }

    // MARK: Functions

    private func evaluateFunction(
        _ name: String,
        _ arguments: [XPathExpr],
        contextNode: XPathNode,
        position: Int,
        size: Int
    ) throws -> XPathValue {
        func argument(_ index: Int) throws -> XPathValue {
            guard index < arguments.count else { return .string("") }
            return try evaluate(arguments[index], contextNode: contextNode, position: position, size: size)
        }

        switch name {
        case "last":
            return .number(Double(size))
        case "position":
            return .number(Double(position))
        case "count":
            return .number(Double(try nodeSet(arguments[0], contextNode: contextNode, position: position, size: size).count))
        case "string":
            if arguments.isEmpty { return .string(contextNode.stringValue) }
            return .string(string(try argument(0)))
        case "concat":
            var result = ""
            for index in arguments.indices {
                result += string(try argument(index))
            }
            return .string(result)
        case "starts-with":
            let text = string(try argument(0))
            let prefix = string(try argument(1))
            return .boolean(text.hasPrefix(prefix))
        case "contains":
            let text = string(try argument(0))
            let needle = string(try argument(1))
            return .boolean(text.contains(needle))
        case "substring-before":
            let text = string(try argument(0))
            let needle = string(try argument(1))
            guard let range = text.range(of: needle) else { return .string("") }
            return .string(String(text[text.startIndex..<range.lowerBound]))
        case "substring-after":
            let text = string(try argument(0))
            let needle = string(try argument(1))
            guard let range = text.range(of: needle) else { return .string("") }
            return .string(String(text[range.upperBound...]))
        case "substring":
            let text = Array(string(try argument(0)))
            let start = number(try argument(1))
            var length = text.count == 1 ? Double(text.count) : number(try argument(2))
            if length < 0 { length = 0 }
            let begin = max(0, min(Double(text.count), roundHalfUp(start)))
            let end = max(begin, min(Double(text.count), roundHalfUp(start + length)))
            return .string(String(text[Int(begin)..<Int(end)]))
        case "string-length":
            let text = arguments.isEmpty ? contextNode.stringValue : string(try argument(0))
            return .number(Double(text.count))
        case "normalize-space":
            let text = arguments.isEmpty ? contextNode.stringValue : string(try argument(0))
            return .string(text.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" }).joined(separator: " "))
        case "translate":
            let text = string(try argument(0))
            let from = Array(string(try argument(1)))
            let to = Array(string(try argument(2)))
            var result = ""
            for character in text {
                if let index = from.firstIndex(of: character) {
                    if index < to.count { result.append(to[index]) }
                } else {
                    result.append(character)
                }
            }
            return .string(result)
        case "boolean":
            return .boolean(boolean(try argument(0)))
        case "not":
            return .boolean(!boolean(try argument(0)))
        case "true":
            return .boolean(true)
        case "false":
            return .boolean(false)
        case "floor":
            return .number(number(try argument(0)).rounded(.down))
        case "ceiling":
            return .number(number(try argument(0)).rounded(.up))
        case "round":
            return .number(number(try argument(0)).rounded())
        case "sum":
            let nodes = try nodeSet(arguments[0], contextNode: contextNode, position: position, size: size)
            return .number(nodes.reduce(0.0) { $0 + (Double($1.stringValue) ?? 0) })
        case "name", "local-name":
            let nodes = try nodeSet(arguments[0], contextNode: contextNode, position: position, size: size)
            return .string(nodes.first?.name ?? "")
        case "string", "data":
            return .string(string(try argument(0)))
        default:
            return .string("")
        }
    }

    private func roundHalfUp(_ value: Double) -> Double {
        (value * 1000).rounded() / 1000
    }
}
