import Foundation

/// Faithful port of `io.legado.app.model.analyzeRule.AnalyzeByJSonPath`.
///
/// Upstream: app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSonPath.kt (172 lines)
///
/// The upstream class exists to work around two conflicts:
/// - JSONPath itself supports `&&` / `||`, which clash with Legado's own
///   rule combinators — hence the `RuleAnalyzer(rule, true)` code-balanced
///   scanner before the path is evaluated.
/// - Legacy rules use the `{$.rule}` form to embed a JSONPath expression
///   inside another rule; the upstream `innerRule("{$.")` replacement is
///   reproduced here.
public final class JSONPathMatcher: RuleMatcher {

    public init() {}

    // MARK: - RuleMatcher

    /// Port of `AnalyzeByJSonPath.getString`.
    public func string(_ content: RuleValue, _ rule: String) throws -> String? {
        guard !rule.isEmpty else { return nil }
        guard let root = JSONPathMatcher.root(from: content) else { return nil }

        let analyzer = RuleAnalyzer(rule, code: true)
        let rules = try analyzer.splitRule("&&", "||")

        if rules.count == 1 {
            analyzer.reSetPos()
            let replaced = analyzer.innerRule(inner: "{$.") { raw in
                JSONPathMatcher.getString(root: root, rule: raw)
            }
            if replaced.isEmpty {
                // No embedded rule matched — read the path itself.
                guard let value = JSONPath.read(rule, in: root) else { return "" }
                if case .array(let items) = value {
                    return items.map { $0.textValue }.joined(separator: "\n")
                }
                return value.textValue
            }
            return replaced
        }

        var textList: [String] = []
        for rl in rules {
            let temp = JSONPathMatcher.getString(root: root, rule: rl)
            if !temp.isEmpty {
                textList.append(temp)
                if analyzer.elementsType == "||" { break }
            }
        }
        return textList.joined(separator: "\n")
    }

    /// Port of `AnalyzeByJSonPath.getStringList`.
    public func stringList(_ content: RuleValue, _ rule: String) throws -> [String]? {
        guard !rule.isEmpty else { return [] }
        guard let root = JSONPathMatcher.root(from: content) else { return [] }

        let analyzer = RuleAnalyzer(rule, code: true)
        let rules = try analyzer.splitRule("&&", "||", "%%")

        if rules.count == 1 {
            analyzer.reSetPos()
            let replaced = analyzer.innerRule(inner: "{$.") { raw in
                JSONPathMatcher.getString(root: root, rule: raw)
            }
            if replaced.isEmpty {
                guard let value = JSONPath.read(rule, in: root) else { return [] }
                if case .array(let items) = value {
                    return items.map { $0.textValue }
                }
                return [value.textValue]
            }
            return [replaced]
        }

        var results: [[String]] = []
        for rl in rules {
            let temp = try JSONPathMatcher.getStringList(root: root, rule: rl)
            if !temp.isEmpty {
                results.append(temp)
                if analyzer.elementsType == "||" { break }
            }
        }
        if !results.isEmpty {
            var result: [String] = []
            if analyzer.elementsType == "%%" {
                for index in results[0].indices {
                    for temp in results where index < temp.count {
                        result.append(temp[index])
                    }
                }
            } else {
                for temp in results {
                    result.append(contentsOf: temp)
                }
            }
            return result
        }
        return []
    }

    /// Port of `AnalyzeByJSonPath.getObject` — the raw value at the path.
    public func element(_ content: RuleValue, _ rule: String) throws -> RuleValue? {
        guard !rule.isEmpty else { return nil }
        guard let root = JSONPathMatcher.root(from: content) else { return nil }
        guard let value = JSONPath.read(rule, in: root) else { return nil }
        return .json(value)
    }

    /// Port of `AnalyzeByJSonPath.getList` — the raw values at the path.
    public func elements(_ content: RuleValue, _ rule: String) throws -> [RuleValue] {
        guard !rule.isEmpty else { return [] }
        guard let root = JSONPathMatcher.root(from: content) else { return [] }

        let analyzer = RuleAnalyzer(rule, code: true)
        let rules = try analyzer.splitRule("&&", "||", "%%")

        if rules.count == 1 {
            guard let value = JSONPath.read(rule, in: root) else { return [] }
            if case .array(let items) = value {
                return items.map { RuleValue.json($0) }
            }
            return [RuleValue.json(value)]
        }

        var results: [[JSONValue]] = []
        for rl in rules {
            let temp = try JSONPathMatcher.getList(root: root, rule: rl)
            if !temp.isEmpty {
                results.append(temp)
                if analyzer.elementsType == "||" { break }
            }
        }
        if !results.isEmpty {
            var result: [JSONValue] = []
            if analyzer.elementsType == "%%" {
                for index in results[0].indices {
                    for temp in results where index < temp.count {
                        result.append(temp[index])
                    }
                }
            } else {
                for temp in results {
                    result.append(contentsOf: temp)
                }
            }
            return result.map { RuleValue.json($0) }
        }
        return []
    }

    // MARK: - Internals

    /// The JSON document behind a rule value.
    private static func root(from content: RuleValue) -> JSONValue? {
        switch content {
        case .json(let value):
            return value
        case .text(let text):
            return try? JSONValue.parse(text)
        case .list(let items):
            return .array(items.map { JSONValue.from(ruleValue: $0) })
        case .object(let members):
            return .object(members.mapValues { JSONValue.from(ruleValue: $0) })
        case .scriptObject(let members):
            return .object(members.mapValues { JSONValue.from(ruleValue: $0) })
        default:
            return nil
        }
    }

    /// The recursive worker behind `string`.
    private static func getString(root: JSONValue, rule: String) -> String {
        guard !rule.isEmpty else { return "" }
        let analyzer = RuleAnalyzer(rule, code: true)
        guard let rules = try? analyzer.splitRule("&&", "||") else { return "" }
        if rules.count == 1 {
            analyzer.reSetPos()
            let replaced = analyzer.innerRule(inner: "{$.") { raw in
                getString(root: root, rule: raw)
            }
            if !replaced.isEmpty { return replaced }
            guard let value = JSONPath.read(rule, in: root) else { return "" }
            if case .array(let items) = value {
                return items.map { $0.textValue }.joined(separator: "\n")
            }
            return value.textValue
        }
        var textList: [String] = []
        for rl in rules {
            let temp = getString(root: root, rule: rl)
            if !temp.isEmpty {
                textList.append(temp)
                if analyzer.elementsType == "||" { break }
            }
        }
        return textList.joined(separator: "\n")
    }

    /// The recursive worker behind `stringList`.
    private static func getStringList(root: JSONValue, rule: String) throws -> [String] {
        guard !rule.isEmpty else { return [] }
        let analyzer = RuleAnalyzer(rule, code: true)
        let rules = try analyzer.splitRule("&&", "||", "%%")
        if rules.count == 1 {
            analyzer.reSetPos()
            let replaced = analyzer.innerRule(inner: "{$.") { raw in
                getString(root: root, rule: raw)
            }
            if !replaced.isEmpty { return [replaced] }
            guard let value = JSONPath.read(rule, in: root) else { return [] }
            if case .array(let items) = value {
                return items.map { $0.textValue }
            }
            return [value.textValue]
        }
        var results: [[String]] = []
        for rl in rules {
            let temp = try getStringList(root: root, rule: rl)
            if !temp.isEmpty {
                results.append(temp)
                if analyzer.elementsType == "||" { break }
            }
        }
        var result: [String] = []
        if analyzer.elementsType == "%%" {
            if let first = results.first {
                for index in first.indices {
                    for temp in results where index < temp.count {
                        result.append(temp[index])
                    }
                }
            }
        } else {
            for temp in results { result.append(contentsOf: temp) }
        }
        return result
    }

    /// The recursive worker behind `elements`.
    private static func getList(root: JSONValue, rule: String) throws -> [JSONValue] {
        guard !rule.isEmpty else { return [] }
        let analyzer = RuleAnalyzer(rule, code: true)
        let rules = try analyzer.splitRule("&&", "||", "%%")
        if rules.count == 1 {
            guard let value = JSONPath.read(rule, in: root) else { return [] }
            if case .array(let items) = value { return items }
            return [value]
        }
        var results: [[JSONValue]] = []
        for rl in rules {
            let temp = try getList(root: root, rule: rl)
            if !temp.isEmpty {
                results.append(temp)
                if analyzer.elementsType == "||" { break }
            }
        }
        var result: [JSONValue] = []
        if analyzer.elementsType == "%%" {
            if let first = results.first {
                for index in first.indices {
                    for temp in results where index < temp.count {
                        result.append(temp[index])
                    }
                }
            }
        } else {
            for temp in results { result.append(contentsOf: temp) }
        }
        return result
    }
}

extension JSONValue {
    /// Converts a rule value into a JSON value.
    static func from(ruleValue: RuleValue) -> JSONValue {
        switch ruleValue {
        case .text(let value):
            return .string(value)
        case .number(let value):
            return .number(value)
        case .json(let value):
            return value
        case .list(let items):
            return .array(items.map { JSONValue.from(ruleValue: $0) })
        case .object(let members):
            return .object(members.mapValues { JSONValue.from(ruleValue: $0) })
        case .scriptObject(let members):
            return .object(members.mapValues { JSONValue.from(ruleValue: $0) })
        case .null:
            return .null
        case .node(let node):
            return .string(node.nodeText)
        }
    }
}
