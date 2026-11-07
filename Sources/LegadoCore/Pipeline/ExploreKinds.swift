//
//  ExploreKinds.swift
//  LegadoCore
//
//  The explore categories of a book source.
//
//  Upstream `help/source/BookSourceExtensions.kt:41-89` (`exploreKinds()`):
//
//  * the `exploreUrl` field holds the rule; when it starts with `<js>` or
//    `@js:` the rule is the result of that script (the upstream caches it);
//  * when the rule is a JSON ARRAY it is parsed as a list of `ExploreKind`
//    objects (`{"title": …, "url": …}`);
//  * otherwise the rule is a list of `分类::网址` pairs separated by the
//    regular expression `(&&|\n)+`.
//
//  The port keeps the exact parsing so that a source written for the Android
//  app offers the same categories. The script form is evaluated with the
//  source that owns the rule, so a source whose categories are built by a
//  script (the 起点/番茄 style sources) offers them instead of the text of the
//  script itself.
//

import Foundation

/// The parser of the explore categories.
public enum ExploreKinds {

    /// The categories already evaluated — upstream `exploreKindsMap` and the
    /// `explore` cache.
    ///
    /// The key is the source url plus the rule, so editing the rule of a
    /// source invalidates the entry without a manual refresh.
    private static var cache: [String: [ExploreKind]] = [:]
    private static let lock = NSLock()

    /// Parses the explore categories of a source.
    ///
    /// - Parameters:
    ///   - exploreUrl: the `exploreUrl` field of the source.
    ///   - engine: the script engine — a `<js>` / `@js:` rule needs it.
    ///   - source: the source the rule belongs to — the scripts read the
    ///     login data and the variables through it.
    public static func parse(
        _ exploreUrl: String?,
        engine: RuleScriptEngine? = nil,
        source: BookSource? = nil
    ) -> [ExploreKind] {
        guard let exploreUrl, !exploreUrl.isBlank else { return [] }
        let rule = exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if isScript(rule) {
            // Without an engine the script cannot run — and the empty answer
            // must not be cached, or a later call that does have the engine
            // would keep it.
            guard let engine else { return [] }
            let key = cacheKey(rule: rule, source: source)
            if let cached = cachedKinds(for: key) { return cached }
            guard let script = try? evaluate(rule, engine: engine, source: source) else {
                return []
            }
            let kinds = parseRule(script)
            store(kinds, for: key)
            return kinds
        }
        return parseRule(rule)
    }

    /// Drops every cached category list — upstream `clearExploreKindsCache()`;
    /// the rule script calls it with `source.refreshExplore()`.
    public static func clearCache() {
        lock.lock()
        cache.removeAll()
        lock.unlock()
    }

    // MARK: - The script form

    /// Whether the rule is a script — upstream
    /// `exploreUrl.startsWith("<js>", true) || startsWith("@js:", true)`.
    private static func isScript(_ rule: String) -> Bool {
        let lower = rule.lowercased()
        return lower.hasPrefix("<js>") || lower.hasPrefix("@js:")
    }

    /// Runs the script of the rule and returns its text.
    private static func evaluate(
        _ rule: String,
        engine: RuleScriptEngine?,
        source: BookSource?
    ) throws -> String {
        guard let engine else { return "" }
        // Upstream strips the wrapper: `substring(4)` for `@js:` and
        // `substring(4, lastIndexOf("<"))` for `<js>…</js>`.
        let script: String
        if rule.hasPrefix("@") {
            script = String(rule.dropFirst(4))
        } else if let end = rule.lastIndex(of: "<"), end > rule.startIndex {
            script = String(rule[rule.index(rule.startIndex, offsetBy: 4)..<end])
        } else {
            script = String(rule.dropFirst(4))
        }
        let context = source.map {
            ScriptSourceContext(
                key: $0.key,
                name: $0.bookSourceName,
                variables: $0.variableBox,
                bookSource: $0
            )
        }
        let value = try engine.evaluate(script, bindings: ["result": .null], source: context)
        return value.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - The rule form

    /// Parses an already evaluated rule.
    private static func parseRule(_ rule: String) -> [ExploreKind] {
        if let value = try? JSONValue.parse(rule), case .array(let items) = value {
            return items.compactMap { item in
                guard case .object(let members) = item else { return nil }
                let title = members["title"]?.textValue ?? ""
                let url = members["url"]?.textValue
                return ExploreKind(title: title, url: url)
            }
        }
        // The plain "分类::网址" list, separated by "(&&|\n)+".
        return split(separatorPattern: "(&&|\n)+", in: rule).map { part in
            let fields = part.components(separatedBy: "::")
            let title = fields.first ?? ""
            let url = fields.count > 1 ? fields[1] : nil
            return ExploreKind(title: title, url: url)
        }
    }

    // MARK: - The cache

    /// The key of the cached categories — upstream
    /// `MD5Utils.md5Encode(bookSourceUrl + exploreUrl)`.
    private static func cacheKey(rule: String, source: BookSource?) -> String {
        "\(source?.bookSourceUrl ?? "")\u{0}\(rule)"
    }

    private static func cachedKinds(for key: String) -> [ExploreKind]? {
        lock.lock()
        defer { lock.unlock() }
        return cache[key]
    }

    private static func store(_ kinds: [ExploreKind], for key: String) {
        lock.lock()
        cache[key] = kinds
        lock.unlock()
    }

    /// Splits a string on a regular expression (the upstream
    /// `split("(&&|\n)+".toRegex())`).
    private static func split(separatorPattern: String, in text: String) -> [String] {
        guard let separator = try? NSRegularExpression(pattern: separatorPattern) else {
            return [text]
        }
        var parts: [String] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\n" {
                parts.append(current)
                current = ""
                index = text.index(after: index)
                continue
            }
            if character == "&",
               text.index(after: index) < text.endIndex,
               text[text.index(after: index)] == "&" {
                parts.append(current)
                current = ""
                index = text.index(index, offsetBy: 2)
                continue
            }
            current.append(character)
            index = text.index(after: index)
        }
        parts.append(current)
        // The upstream drops the empty parts.
        return parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
