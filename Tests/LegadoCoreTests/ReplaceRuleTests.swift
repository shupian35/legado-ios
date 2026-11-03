import XCTest
@testable import LegadoCore

/// Tests for the replace / purify rules — upstream `help/ReplaceAnalyzer.kt`,
/// `data/entities/ReplaceRule.kt`, `utils/RegexExtensions.kt` and
/// `help/book/ContentProcessor.kt`.
final class ReplaceRuleTests: XCTestCase {

    // MARK: - Validity

    func testAnEmptyPatternIsInvalid() {
        XCTAssertFalse(ReplaceRuleEngine.isValid(ReplaceRule(pattern: "")))
    }

    func testANonRegexRuleIsValid() {
        XCTAssertTrue(ReplaceRuleEngine.isValid(ReplaceRule(pattern: "abc", isRegex: false)))
    }

    func testAValidRegexIsValid() {
        XCTAssertTrue(ReplaceRuleEngine.isValid(ReplaceRule(pattern: "a+b", isRegex: true)))
    }

    func testAnInvalidRegexIsInvalid() {
        XCTAssertFalse(ReplaceRuleEngine.isValid(ReplaceRule(pattern: "a(b", isRegex: true)))
    }

    func testATrailingPipeIsInvalidUnlessEscaped() {
        XCTAssertFalse(ReplaceRuleEngine.isValid(ReplaceRule(pattern: "a|", isRegex: true)))
        XCTAssertTrue(ReplaceRuleEngine.isValid(ReplaceRule(pattern: "a\\|", isRegex: true)))
    }

    func testTheTimeoutFallsBackToThreeSeconds() {
        XCTAssertEqual(ReplaceRuleEngine.validTimeoutMillisecond(ReplaceRule(timeoutMillisecond: 0)), 3000)
        XCTAssertEqual(ReplaceRuleEngine.validTimeoutMillisecond(ReplaceRule(timeoutMillisecond: -1)), 3000)
        XCTAssertEqual(ReplaceRuleEngine.validTimeoutMillisecond(ReplaceRule(timeoutMillisecond: 500)), 500)
    }

    // MARK: - Applying a rule

    func testALiteralRuleReplacesEveryOccurrence() throws {
        let rule = ReplaceRule(pattern: "abc", replacement: "xyz", isRegex: false)
        XCTAssertEqual(try ReplaceRuleEngine.apply(rule, to: "abcabc"), "xyzxyz")
    }

    func testARegexRuleExpandsTheCaptureGroups() throws {
        let rule = ReplaceRule(pattern: "(\\w+)@(\\w+)", replacement: "$2:$1", isRegex: true)
        XCTAssertEqual(try ReplaceRuleEngine.apply(rule, to: "user@host"), "host:user")
    }

    func testARegexRuleExpandsNamedGroups() throws {
        let rule = ReplaceRule(pattern: "(?<first>\\w+) (?<second>\\w+)", replacement: "${second} ${first}", isRegex: true)
        XCTAssertEqual(try ReplaceRuleEngine.apply(rule, to: "one two"), "two one")
    }

    func testAnEmptyPatternLeavesTheTextAlone() throws {
        let rule = ReplaceRule(pattern: "", replacement: "x", isRegex: true)
        XCTAssertEqual(try ReplaceRuleEngine.apply(rule, to: "untouched"), "untouched")
    }

    func testAnInvalidRegexThrows() {
        let rule = ReplaceRule(pattern: "a(b", replacement: "x", isRegex: true)
        XCTAssertThrowsError(try ReplaceRuleEngine.apply(rule, to: "text"))
    }

    func testAJavaScriptReplacementUsesTheMatchedText() throws {
        let rule = ReplaceRule(pattern: "(\\d+)", replacement: "@js:result + '!'", isRegex: true)
        let engine = ScriptAppendBangEngine()
        XCTAssertEqual(try ReplaceRuleEngine.apply(rule, to: "a1b2", scriptEngine: engine), "a1!b2!")
    }

    // MARK: - The chapter title

    func testTheDisplayTitleRemovesLineBreaks() throws {
        let chapter = BookChapter(url: "u", title: "第一\r\n章")
        let title = try ReplaceRuleEngine.displayTitle(chapter, replaceRules: [])
        XCTAssertEqual(title, "第一章")
    }

    func testTheDisplayTitleAppliesTheRules() throws {
        let chapter = BookChapter(url: "u", title: "第一章")
        let rule = ReplaceRule(pattern: "第一", replacement: "第1", isRegex: false)
        let title = try ReplaceRuleEngine.displayTitle(chapter, replaceRules: [rule])
        XCTAssertEqual(title, "第1章")
    }

    func testTheDisplayTitleKeepsThePreviousValueWhenTheRuleBlanksIt() throws {
        let chapter = BookChapter(url: "u", title: "第一章")
        let rule = ReplaceRule(pattern: ".*", replacement: "", isRegex: true)
        let title = try ReplaceRuleEngine.displayTitle(chapter, replaceRules: [rule])
        XCTAssertEqual(title, "第一章")
    }

    // MARK: - The chapter content

    private func makeBook(name: String = "书名") -> Book {
        var book = Book()
        book.name = name
        return book
    }

    func testTheContentRulesAreApplied() throws {
        let book = makeBook()
        let chapter = BookChapter(url: "u", title: "第一章")
        let rule = ReplaceRule(pattern: "广告", replacement: "", isRegex: false)
        let processed = try ReplaceRuleEngine.processContent(
            book: book,
            chapter: chapter,
            content: "正文\n广告内容\n更多正文",
            titleRules: [],
            contentRules: [rule]
        )
        XCTAssertTrue(processed.contents.joined().contains("广告") == false)
        XCTAssertEqual(processed.effectiveReplaceRules.count, 1)
    }

    func testTheDuplicatedTitleIsRemoved() throws {
        let book = makeBook(name: "书名")
        let chapter = BookChapter(url: "u", title: "第一章")
        let processed = try ReplaceRuleEngine.processContent(
            book: book,
            chapter: chapter,
            content: "书名 第一章\n正文",
            includeTitle: false,
            titleRules: [],
            contentRules: []
        )
        XCTAssertTrue(processed.sameTitleRemoved)
        XCTAssertFalse(processed.contents.joined().contains("第一章"))
        XCTAssertTrue(processed.contents.joined().contains("正文"))
    }

    func testTheParagraphsAreIndented() throws {
        let book = makeBook()
        let chapter = BookChapter(url: "u", title: "第一章")
        let processed = try ReplaceRuleEngine.processContent(
            book: book,
            chapter: chapter,
            content: "第一段\n第二段",
            includeTitle: false,
            titleRules: [],
            contentRules: []
        )
        let body = processed.contents.joined(separator: "\n")
        XCTAssertTrue(body.contains("　　第二段"))
    }

    func testTheTitleIsPrependedWhenRequested() throws {
        let book = makeBook()
        let chapter = BookChapter(url: "u", title: "第一章")
        let processed = try ReplaceRuleEngine.processContent(
            book: book,
            chapter: chapter,
            content: "正文",
            includeTitle: true,
            titleRules: [],
            contentRules: []
        )
        XCTAssertTrue(processed.contents.joined().contains("第一章"))
    }

    // MARK: - JSON import

    func testTheModernJsonFormatIsParsed() throws {
        let json = """
        {"id": 12, "name": "规则", "pattern": "a", "replacement": "b", "isRegex": false, "scope": "书名", "enable": true}
        """
        let rule = try ReplaceRuleEngine.jsonToReplaceRule(json)
        XCTAssertEqual(rule.id, 12)
        XCTAssertEqual(rule.name, "规则")
        XCTAssertEqual(rule.pattern, "a")
        XCTAssertEqual(rule.replacement, "b")
        XCTAssertFalse(rule.isRegex)
        XCTAssertEqual(rule.scope, "书名")
        XCTAssertTrue(rule.isEnabled)
    }

    func testTheLegacyJsonFormatIsParsed() throws {
        let json = """
        {"id": 7, "regex": "x(y)", "replaceSummary": "旧规则", "replacement": "z", "isRegex": true, "useTo": "分组", "enable": false, "serialNumber": 3}
        """
        let rule = try ReplaceRuleEngine.jsonToReplaceRule(json)
        XCTAssertEqual(rule.id, 7)
        XCTAssertEqual(rule.name, "旧规则")
        XCTAssertEqual(rule.pattern, "x(y)")
        XCTAssertEqual(rule.replacement, "z")
        XCTAssertTrue(rule.isRegex)
        XCTAssertEqual(rule.scope, "分组")
        XCTAssertFalse(rule.isEnabled)
        XCTAssertEqual(rule.sortOrder, 3)
    }

    func testALegacyRuleWithoutAPatternThrows() {
        XCTAssertThrowsError(try ReplaceRuleEngine.jsonToReplaceRule(#"{"regex": ""}"#))
    }

    func testAnArrayOfRulesIsParsed() throws {
        let json = """
        [{"id": 1, "name": "a", "pattern": "x", "replacement": "y"},
         {"id": 2, "name": "b", "pattern": "z", "replacement": "w"}]
        """
        let rules = try ReplaceRuleEngine.jsonToReplaceRules(json)
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[1].name, "b")
    }
}

/// A script engine that simulates `result + '!'`.
private final class ScriptAppendBangEngine: RuleScriptEngine {
    func evaluate(_ script: String, bindings: [String: RuleValue]) throws -> RuleValue {
        let matched = bindings["result"]?.textValue ?? ""
        return .text(matched + "!")
    }
}
