import Foundation

/// The rule engine.
///
/// Port of `io.legado.app.model.analyzeRule.AnalyzeRule`.
///
/// Upstream: app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt
///
/// The class takes a document, splits a rule into steps and evaluates each
/// step against the result of the previous one. The five strategies (CSS,
/// XPath, JSONPath, regular expression and JavaScript) are selected by a marker
/// at the front of the rule text — see `SourceRule`.
public final class AnalyzeRule {

    // MARK: - State

    /// The document the rules are evaluated against.
    public private(set) var content: RuleContent?

    /// The base URL used to resolve relative links.
    public var baseUrl: String?

    /// The URL the response was finally served from (after redirects).
    public var redirectUrl: URL?

    /// Whether the current content should be treated as JSON.
    public private(set) var isJSON: Bool = false

    /// Set when a rule uses the `:` regex marker in "all in one" mode.
    public var isRegex: Bool = false

    /// The chapter the rule is evaluated for.
    public weak var chapter: RuleVariableHolder?

    /// The book the rule is evaluated for.
    public weak var book: RuleVariableHolder?

    /// The rule data (search result, RSS article, …).
    public weak var ruleData: RuleVariableHolder?

    /// The book source the rule belongs to.
    public weak var source: RuleVariableHolder?

    /// The name of the current book — the `bookName` variable.
    public var bookName: String = ""

    /// The title of the current chapter — the `title` variable.
    public var chapterTitle: String = ""

    /// The URL of the next chapter — the `nextChapterUrl` variable.
    public var nextChapterUrl: String?

    /// The chapter the rule is evaluated for — the upstream binds the whole
    /// chapter object to the `chapter` variable (`AnalyzeRule.kt:783`).
    public var chapterInfo: BookChapter?

    /// The book the rule is evaluated for — the upstream binds the whole book
    /// object to the `book` variable (`AnalyzeRule.kt:780`).
    public var bookInfo: Book?

    /// The JavaScript runtime used by `{{ ... }}` rules.
    public var scriptEngine: RuleScriptEngine?

    /// The CSS selector matcher.
    public var cssMatcher: RuleMatcher?

    /// The XPath matcher.
    public var xpathMatcher: RuleMatcher?

    /// The JSONPath matcher.
    public var jsonMatcher: RuleMatcher?

    /// The regular-expression matcher, used by `getElement`/`getElements`.
    public var regexMatcher: RuleMatcher?

    // MARK: - Caches (upstream keeps the same three)

    private var stringRuleCache: [String: [SourceRule]] = [:]
    private let singleRuleCache = LimitedCache<String, [SourceRule]>(limit: 16)
    private let regexCache = LimitedCache<String, NSRegularExpression?>(limit: 16)

    // MARK: - Life cycle

    /// Create a rule engine.
    public init(content: RuleContent? = nil, baseUrl: String? = nil) {
        self.content = content
        self.baseUrl = baseUrl
        self.isJSON = content?.isJSON ?? false
    }

    /// Set the document and reset the derived state.
    @discardableResult
    public func setContent(_ content: RuleContent?, baseUrl: String? = nil) throws -> AnalyzeRule {
        guard let content else {
            throw RuleEngineError.contentIsNull
        }
        self.content = content
        self.isJSON = content.isJSON
        setBaseUrl(baseUrl)
        return self
    }

    /// Set the base URL — upstream only overwrites it when the value is not nil.
    @discardableResult
    public func setBaseUrl(_ baseUrl: String?) -> AnalyzeRule {
        if let baseUrl { self.baseUrl = baseUrl }
        return self
    }

    /// Record the final URL of the response.
    @discardableResult
    public func setRedirectUrl(_ url: String) -> URL? {
        if url.hasPrefix("data:") { return redirectUrl }
        guard let parsed = URL(string: url) else { return redirectUrl }
        redirectUrl = parsed
        return parsed
    }

    // MARK: - Public API

    /// Extract a list of strings.
    ///
    /// - Parameters:
    ///   - rule: the rule text.
    ///   - mContent: an optional document to evaluate against; defaults to the
    ///     document the engine was created with.
    ///   - isUrl: resolve every result to an absolute URL and drop duplicates.
    public func getStringList(
        _ rule: String?,
        _ mContent: RuleContent? = nil,
        isUrl: Bool = false
    ) throws -> [String]? {
        guard let rule, !rule.isEmpty else { return nil }
        return try getStringList(splitSourceRuleCacheString(rule), mContent, isUrl: isUrl)
    }

    /// Extract a list of strings from an already split rule.
    public func getStringList(
        _ ruleList: [SourceRule],
        _ mContent: RuleContent? = nil,
        isUrl: Bool = false
    ) throws -> [String]? {
        var result: RuleValue?
        let document = mContent ?? content
        if let document, !ruleList.isEmpty {
            result = document.ruleValue
            if case .scriptObject(let members) = result {
                let sourceRule = ruleList[0]
                putRule(sourceRule.putMap)
                makeUpRule(sourceRule, result: result)
                result = sourceRule.paramSize > 1
                    ? RuleValue.text(sourceRule.rule)
                    : (members[sourceRule.rule] ?? .null)
                if !sourceRule.replaceRegex.isEmpty {
                    if case .list(let items) = result {
                        result = .list(items.map { .text(replaceRegex($0.textValue, sourceRule)) })
                    } else if let current = result, !current.isNull {
                        result = .text(replaceRegex(current.textValue, sourceRule))
                    }
                }
            } else {
                for sourceRule in ruleList {
                    putRule(sourceRule.putMap)
                    makeUpRule(sourceRule, result: result)
                    guard var current = result else { continue }
                    let rule = sourceRule.rule
                    if !rule.isEmpty {
                        current = try dispatchList(mode: sourceRule.mode, rule: rule, result: current)
                        result = current
                    }
                    if !sourceRule.replaceRegex.isEmpty {
                        if case .list(let items) = current {
                            result = .list(items.map { .text(replaceRegex($0.textValue, sourceRule)) })
                        } else {
                            result = .text(replaceRegex(current.textValue, sourceRule))
                        }
                    } else {
                        result = current
                    }
                }
            }
        }

        guard var value = result else { return nil }
        if case .text(let text) = value {
            value = .list(text.components(separatedBy: "\n").map { RuleValue.text($0) })
        }
        if isUrl {
            var urls: [String] = []
            if case .list(let items) = value {
                for item in items {
                    let absolute = RuleURL.absoluteURL(base: redirectUrl, item.textValue)
                    if !absolute.isEmpty && !urls.contains(absolute) { urls.append(absolute) }
                }
            }
            return urls
        }
        if case .list(let items) = value {
            return items.map(\.textValue)
        }
        return nil
    }

    /// Extract a single string.
    public func getString(
        _ ruleStr: String?,
        _ mContent: RuleContent? = nil,
        isUrl: Bool = false,
        unescape: Bool = true
    ) throws -> String {
        guard let ruleStr, !ruleStr.isEmpty else { return "" }
        return try getString(splitSourceRuleCacheString(ruleStr), mContent, isUrl: isUrl, unescape: unescape)
    }

    /// Extract a single string from an already split rule.
    public func getString(
        _ ruleList: [SourceRule],
        _ mContent: RuleContent? = nil,
        isUrl: Bool = false,
        unescape: Bool = true
    ) throws -> String {
        var result: RuleValue?
        let document = mContent ?? content
        if let document, !ruleList.isEmpty {
            result = document.ruleValue
            if case .scriptObject(let members) = result {
                let sourceRule = ruleList[0]
                putRule(sourceRule.putMap)
                makeUpRule(sourceRule, result: result)
                let raw = sourceRule.paramSize > 1
                    ? sourceRule.rule
                    : (members[sourceRule.rule]?.textValue ?? "")
                result = .text(replaceRegex(raw, sourceRule))
            } else {
                for sourceRule in ruleList {
                    putRule(sourceRule.putMap)
                    makeUpRule(sourceRule, result: result)
                    guard var current = result else { continue }
                    let rule = sourceRule.rule
                    if !rule.isBlank || sourceRule.replaceRegex.isEmpty {
                        current = try dispatchString(
                            mode: sourceRule.mode,
                            rule: rule,
                            result: current,
                            isUrl: isUrl
                        )
                        result = current
                    }
                    if !sourceRule.replaceRegex.isEmpty {
                        result = .text(replaceRegex(current.textValue, sourceRule))
                    }
                }
            }
        }

        guard let value = result else { return "" }
        let resultStr = value.textValue
        let text = (unescape && resultStr.contains("&"))
            ? RuleEntities.unescapeHTML4(resultStr)
            : resultStr
        if isUrl {
            return text.isBlank
                ? (baseUrl ?? "")
                : RuleURL.absoluteURL(base: redirectUrl, text)
        }
        return text
    }

    /// Extract a single element.
    public func getElement(_ ruleStr: String?) throws -> RuleValue? {
        guard let ruleStr, !ruleStr.isEmpty else { return nil }
        var result: RuleValue?
        guard let document = content else { return nil }
        let ruleList = splitSourceRule(ruleStr, allInOne: true)
        if !ruleList.isEmpty {
            result = document.ruleValue
            for sourceRule in ruleList {
                putRule(sourceRule.putMap)
                makeUpRule(sourceRule, result: result)
                guard let current = result else { continue }
                let rule = sourceRule.rule
                result = try dispatchElement(mode: sourceRule.mode, rule: rule, result: current)
                if !sourceRule.replaceRegex.isEmpty {
                    result = .text(replaceRegex((result ?? .null).textValue, sourceRule))
                }
            }
        }
        return result
    }

    /// Extract a list of elements.
    ///
    /// - Note: upstream does *not* call `makeUpRule` here — the port keeps that
    ///   behaviour so existing sources behave identically.
    public func getElements(_ ruleStr: String?) throws -> [RuleValue] {
        var result: RuleValue?
        guard let document = content else { return [] }
        let ruleList = splitSourceRule(ruleStr, allInOne: true)
        if !ruleList.isEmpty {
            result = document.ruleValue
            for sourceRule in ruleList {
                putRule(sourceRule.putMap)
                guard let current = result else { continue }
                let rule = sourceRule.rule
                result = try dispatchElements(mode: sourceRule.mode, rule: rule, result: current)
            }
        }
        if case .list(let items) = result { return items }
        return []
    }

    // MARK: - Rule splitting

    /// Split a rule into steps, caching the result.
    ///
    /// Upstream caches with an unbounded map; the port keeps the same shape.
    public func splitSourceRuleCacheString(_ ruleStr: String) -> [SourceRule] {
        if let cached = stringRuleCache[ruleStr] { return cached }
        let rules = splitSourceRule(ruleStr)
        stringRuleCache[ruleStr] = rules
        return rules
    }

    /// Split a rule into steps.
    ///
    /// - Parameters:
    ///   - ruleStr: the rule text.
    ///   - allInOne: when `true` a leading `:` marks the whole rule as a regular
    ///     expression. Upstream notes this conflicts with CSS pseudo classes.
    public func splitSourceRule(_ ruleStr: String?, allInOne: Bool = false) -> [SourceRule] {
        guard let ruleStr, !ruleStr.isEmpty else { return [] }
        var ruleList: [SourceRule] = []
        var mode: SourceRule.Mode = .css
        var start = 0

        // 仅首字符为:时为AllInOne，其实:与伪类选择器冲突，建议改成?更合理
        if allInOne && ruleStr.hasPrefix(":") {
            mode = .regex
            isRegex = true
            start = 1
        } else if isRegex {
            mode = .regex
        }

        let ns = ruleStr as NSString
        let range = NSRange(location: 0, length: ns.length)
        RulePatterns.jsPattern.enumerateMatches(in: ruleStr, options: [], range: range) { match, _, _ in
            guard let match else { return }
            if match.range.location > start {
                let tmp = ns.substring(
                    with: NSRange(location: start, length: match.range.location - start)
                ).trimmingJavaSpaces()
                if !tmp.isEmpty { ruleList.append(SourceRule(ruleStr: tmp, mode: mode, isJSON: self.isJSON)) }
            }
            let js = match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound
                ? ns.substring(with: match.range(at: 2))
                : ns.substring(with: match.range(at: 1))
            ruleList.append(SourceRule(ruleStr: js, mode: .js))
            start = match.range.location + match.range.length
            return
        }

        if ns.length > start {
            let tmp = ns.substring(with: NSRange(location: start, length: ns.length - start))
                .trimmingJavaSpaces()
            if !tmp.isEmpty { ruleList.append(SourceRule(ruleStr: tmp, mode: mode, isJSON: self.isJSON)) }
        }
        return ruleList
    }

    /// A single rule, used for nested rule evaluation.
    private func getOrCreateSingleSourceRule(_ rule: String) -> [SourceRule] {
        singleRuleCache.getOrPut(rule) { [SourceRule(ruleStr: rule, mode: .css, isJSON: isJSON)] }
    }

    // MARK: - Variables

    /// Store the variables declared with `@put:{...}`.
    private func putRule(_ map: [String: String]) {
        for (key, value) in map {
            put(key, (try? getString(value)) ?? "")
        }
    }

    /// Write a variable to the chapter, the book, the rule data and the source.
    public func put(_ key: String, _ value: String) {
        if key == "bookName" || key == "title" {
            // ≡变量 $key 在特定情况下会被覆盖，建议使用其他键名
            RuleLog.warning("变量 \(key) 在特定情况下会被覆盖，建议使用其他键名")
        }
        chapter?.putVariable(key, value)
        book?.putVariable(key, value)
        ruleData?.putVariable(key, value)
        source?.putVariable(key, value)
    }

    /// Read a variable.
    public func get(_ key: String) -> String {
        switch key {
        case "bookName":
            return bookName
        case "title":
            return chapterTitle
        default:
            let holders: [RuleVariableHolder?] = [chapter, book, ruleData, source]
            for holder in holders {
                if let value = holder?.getVariable(key), !value.isEmpty { return value }
            }
            return ""
        }
    }

    // MARK: - Rule composition

    /// Compose the fragments of a rule step into the final rule text.
    ///
    /// Port of `SourceRule.makeUpRule`.
    public func makeUpRule(_ sourceRule: SourceRule, result: RuleValue?) {
        var infoVal = ""
        var index = sourceRule.ruleParam.count - 1
        while index >= 0 {
            let param = sourceRule.ruleParam[index]
            let type = sourceRule.ruleType[index]
            if type > 0 {
                if let items = result?.listValue, items.count > type {
                    infoVal.insert(contentsOf: items[type].textValue, at: infoVal.startIndex)
                } else {
                    infoVal.insert(contentsOf: param, at: infoVal.startIndex)
                }
            } else if type == -1 {
                let evaluated: String?
                if isRule(param) {
                    // The fragment is itself a rule — evaluate it as one.
                    let nested = getOrCreateSingleSourceRule(param)
                    evaluated = try? getString(nested)
                } else {
                    // A JavaScript fragment. Upstream renders integral numbers
                    // with "%.0f"; the script engine is expected to do the same.
                    if let value = try? evalJS(param, result) {
                        evaluated = value.textValue
                    } else {
                        evaluated = nil
                    }
                }
                if let evaluated {
                    infoVal.insert(contentsOf: evaluated, at: infoVal.startIndex)
                }
            } else if type == -2 {
                let value = get(param)
                if !value.isEmpty { infoVal.insert(contentsOf: value, at: infoVal.startIndex) }
            } else {
                infoVal.insert(contentsOf: param, at: infoVal.startIndex)
            }
            index -= 1
        }

        let parts = infoVal.components(separatedBy: "##")
        sourceRule.rule = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        if parts.count > 1 { sourceRule.replaceRegex = parts[1] }
        if parts.count > 2 { sourceRule.replacement = parts[2] }
        if parts.count > 3 { sourceRule.replaceFirst = true }
    }

    /// Whether a rule fragment is itself a rule.
    public func isRule(_ ruleStr: String) -> Bool {
        ruleStr.hasPrefix("@")
            || ruleStr.hasPrefix("$.")
            || ruleStr.hasPrefix("$[")
            || ruleStr.hasPrefix("//")
    }

    // MARK: - Replacement

    /// Apply the `##regex##replacement` part of a rule step.
    public func replaceRegex(_ result: String, _ rule: SourceRule) -> String {
        if rule.replaceRegex.isEmpty { return result }
        let regex = compileRegexCache(rule.replaceRegex)
        if rule.replaceFirst {
            guard let regex else { return rule.replacement }
            // Upstream applies `replaceFirst` to the *matched* text.
            let ns = result as NSString
            let range = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: result, options: [], range: range) else { return "" }
            let matched = ns.substring(with: match.range)
            return Self.replaceFirst(matched, regex: regex, template: rule.replacement)
        }
        guard let regex else {
            return result.replacingOccurrences(of: rule.replaceRegex, with: rule.replacement)
        }
        return Self.literalReplace(result, regex: regex, with: rule.replacement)
    }

    /// Kotlin's `String.replaceFirst(Regex, String)` — the first match only, and
    /// the template may reference capture groups with `$1`.
    private static func replaceFirst(_ text: String, regex: NSRegularExpression, template: String) -> String {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else { return text }
        let replacement = expandTemplate(template, match: match, in: text)
        return ns.substring(with: NSRange(location: 0, length: match.range.location))
            + replacement
            + ns.substring(from: match.range.location + match.range.length)
    }

    /// Expand `$1` … `$99` and `${name}` in a replacement template.
    private static func expandTemplate(_ template: String, match: NSTextCheckingResult, in text: String) -> String {
        let ns = text as NSString
        var result = ""
        var index = template.startIndex
        while index < template.endIndex {
            let character = template[index]
            guard character == "$" else {
                result.append(character)
                index = template.index(after: index)
                continue
            }
            let next = template.index(after: index)
            guard next < template.endIndex else {
                result.append(character)
                index = next
                continue
            }
            if template[next] == "{",
               let close = template[next...].firstIndex(of: "}") {
                let name = String(template[template.index(after: next)..<close])
                let namedRange = match.range(withName: name)
                if namedRange.location != NSNotFound {
                    result += ns.substring(with: namedRange)
                }
                index = template.index(after: close)
                continue
            }
            var digits = ""
            var scan = next
            while scan < template.endIndex, template[scan].isNumber, digits.count < 2 {
                digits.append(template[scan])
                scan = template.index(after: scan)
            }
            if let groupIndex = Int(digits), groupIndex > 0, groupIndex < match.numberOfRanges {
                let range = match.range(at: groupIndex)
                if range.location != NSNotFound { result += ns.substring(with: range) }
                index = scan
                continue
            }
            result.append(character)
            index = next
        }
        return result
    }

    /// Kotlin's `String.replace(Regex, String)` — the replacement is literal.
    private static func literalReplace(_ text: String, regex: NSRegularExpression, with replacement: String) -> String {
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var result = ""
        var cursor = 0
        regex.enumerateMatches(in: text, options: [], range: range) { match, _, _ in
            guard let match else { return }
            result += ns.substring(
                with: NSRange(location: cursor, length: match.range.location - cursor)
            )
            result += replacement
            cursor = match.range.location + match.range.length
            return
        }
        result += ns.substring(from: cursor)
        return result
    }

    /// Compile (and cache) a regular expression.
    private func compileRegexCache(_ regex: String) -> NSRegularExpression? {
        regexCache.getOrPut(regex) {
            try? NSRegularExpression(pattern: regex)
        }
    }

    // MARK: - Scripting

    /// Evaluate a JavaScript fragment with the upstream binding names.
    @discardableResult
    public func evalJS(_ jsStr: String, _ result: RuleValue?) throws -> RuleValue {
        guard let engine = scriptEngine else { return .null }
        var bindings: [String: RuleValue] = [:]
        bindings["result"] = result ?? .null
        bindings["baseUrl"] = .text(baseUrl ?? "")
        bindings["title"] = .text(chapterTitle)
        bindings["src"] = content.map { .text($0.textValue) } ?? .null
        bindings["bookName"] = .text(bookName)
        // Upstream `AnalyzeRule.evalJS` binds the next chapter URL as well.
        if let nextChapterUrl {
            bindings["nextChapterUrl"] = .text(nextChapterUrl)
        }
        // Upstream binds the chapter and the book objects (the Rhino scope
        // receives the Kotlin instances); here they become plain objects.
        if let chapterInfo {
            bindings["chapter"] = .scriptObject([
                "url": .text(chapterInfo.url),
                "title": .text(chapterInfo.title),
                "index": .number(Double(chapterInfo.index)),
                "isVolume": .text(chapterInfo.isVolume ? "true" : "false"),
                "isVip": .text(chapterInfo.isVip ? "true" : "false"),
                "isPay": .text(chapterInfo.isPay ? "true" : "false"),
                "baseUrl": .text(chapterInfo.baseUrl),
                "bookUrl": .text(chapterInfo.bookUrl),
                "tag": chapterInfo.tag.map { .text($0) } ?? .null,
                "wordCount": chapterInfo.wordCount.map { .text($0) } ?? .null
            ])
            bindings["title"] = .text(chapterInfo.title)
        }
        if let bookInfo {
            bindings["book"] = .scriptObject([
                "name": .text(bookInfo.name),
                "author": .text(bookInfo.author),
                "bookUrl": .text(bookInfo.bookUrl),
                "origin": .text(bookInfo.origin),
                "originName": .text(bookInfo.originName),
                "tocUrl": .text(bookInfo.tocUrl),
                "kind": bookInfo.kind.map { .text($0) } ?? .null,
                "intro": bookInfo.intro.map { .text($0) } ?? .null,
                "coverUrl": bookInfo.coverUrl.map { .text($0) } ?? .null
            ])
        }
        // Upstream binds the source object as `java`, so the script reaches the
        // variables and the login data of the source it belongs to.
        return try engine.evaluate(jsStr, bindings: bindings, source: sourceContext())
    }

    /// The source the rule belongs to — the upstream `java` binding.
    private func sourceContext() -> ScriptSourceContext? {
        guard let box = source as? RuleDataBox, let key = box.sourceKey else { return nil }
        return ScriptSourceContext(key: key, name: box.sourceName ?? "", variables: box)
    }

    // MARK: - Dispatch

    /// Upstream creates its matchers lazily
    /// (`by lazy { AnalyzeByXPath(content!!) }`), so every mode always has a
    /// working matcher even when the caller injects none.
    private func matcher(for mode: SourceRule.Mode) -> RuleMatcher? {
        switch mode {
        case .css: return cssMatcher ?? CSSMatcher()
        case .xpath: return xpathMatcher ?? XPathMatcher()
        case .json: return jsonMatcher ?? JSONPathMatcher()
        case .regex: return regexMatcher ?? RegexMatcher()
        case .js: return nil
        }
    }

    private func dispatchList(mode: SourceRule.Mode, rule: String, result: RuleValue) throws -> RuleValue {
        switch mode {
        case .js:
            return try evalJS(rule, result)
        case .json:
            guard let matcher = matcher(for: .json) else { return .null }
            guard let list = try matcher.stringList(result, rule) else { return .null }
            return .list(list.map { RuleValue.text($0) })
        case .xpath:
            guard let matcher = matcher(for: .xpath) else { return .null }
            guard let list = try matcher.stringList(result, rule) else { return .null }
            return .list(list.map { RuleValue.text($0) })
        case .css:
            guard let matcher = matcher(for: .css) else { return .null }
            guard let list = try matcher.stringList(result, rule) else { return .null }
            return .list(list.map { RuleValue.text($0) })
        case .regex:
            // Upstream falls through to `else -> rule`.
            return .text(rule)
        }
    }

    private func dispatchString(
        mode: SourceRule.Mode,
        rule: String,
        result: RuleValue,
        isUrl: Bool
    ) throws -> RuleValue {
        switch mode {
        case .js:
            return try evalJS(rule, result)
        case .json:
            guard let matcher = matcher(for: .json) else { return .null }
            guard let text = try matcher.string(result, rule) else { return .null }
            return .text(text)
        case .xpath:
            guard let matcher = matcher(for: .xpath) else { return .null }
            guard let text = try matcher.string(result, rule) else { return .null }
            return .text(text)
        case .css:
            guard let matcher = matcher(for: .css) else { return .null }
            if isUrl {
                // Upstream uses `getString0` — the first match only.
                guard let text = try matcher.firstString(result, rule) else { return .null }
                return .text(text)
            }
            guard let text = try matcher.string(result, rule) else { return .null }
            return .text(text)
        case .regex:
            return .text(rule)
        }
    }

    private func dispatchElement(mode: SourceRule.Mode, rule: String, result: RuleValue) throws -> RuleValue {
        switch mode {
        case .regex:
            guard let matcher = matcher(for: .regex) else { return .null }
            return try matcher.element(result, rule) ?? .null
        case .js:
            return try evalJS(rule, result)
        case .json:
            guard let matcher = matcher(for: .json) else { return .null }
            return try matcher.element(result, rule) ?? .null
        case .xpath:
            guard let matcher = matcher(for: .xpath) else { return .null }
            return try matcher.element(result, rule) ?? .null
        case .css:
            guard let matcher = matcher(for: .css) else { return .null }
            return try matcher.element(result, rule) ?? .null
        }
    }

    private func dispatchElements(mode: SourceRule.Mode, rule: String, result: RuleValue) throws -> RuleValue {
        switch mode {
        case .regex:
            guard let matcher = matcher(for: .regex) else { return .null }
            return .list(try matcher.elements(result, rule))
        case .js:
            return try evalJS(rule, result)
        case .json:
            guard let matcher = matcher(for: .json) else { return .null }
            return .list(try matcher.elements(result, rule))
        case .xpath:
            guard let matcher = matcher(for: .xpath) else { return .null }
            return .list(try matcher.elements(result, rule))
        case .css:
            guard let matcher = matcher(for: .css) else { return .null }
            return .list(try matcher.elements(result, rule))
        }
    }
}

// MARK: - Errors

/// Errors raised by the rule engine.
public enum RuleEngineError: Error, Equatable {
    /// Upstream: `throw AssertionError("内容不可空（Content cannot be null）")`.
    case contentIsNull
}

/// A tiny logging hook so the core does not depend on `os.log`.
public enum RuleLog {
    /// Emit a warning.
    public static func warning(_ message: String) {
        print("[legado] ⚠︎ \(message)")
    }
}
