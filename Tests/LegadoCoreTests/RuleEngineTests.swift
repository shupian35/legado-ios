//
//  RuleEngineTests.swift
//  LegadoCore
//
//  Behavioural tests for the Swift port of the Legado rule engine.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt
//  app/src/main/java/io/legado/app/model/analyzeRule/RuleAnalyzer.kt
//  app/src/main/java/io/legado/app/constant/AppPattern.kt
//

import XCTest
@testable import LegadoCore

// MARK: - Test doubles

/// A matcher that returns canned results, so the orchestrator can be tested
/// without a real CSS / XPath / JSONPath implementation.
final class StubMatcher: RuleMatcher {
    var stringResult: String?
    var listResult: [String]?
    var elementResult: RuleValue?
    var elementsResult: [RuleValue] = []
    var lastRule: String?
    var callCount = 0

    func string(_ content: RuleValue, _ rule: String) throws -> String? {
        lastRule = rule
        callCount += 1
        return stringResult
    }

    func stringList(_ content: RuleValue, _ rule: String) throws -> [String]? {
        lastRule = rule
        callCount += 1
        return listResult
    }

    func element(_ content: RuleValue, _ rule: String) throws -> RuleValue? {
        lastRule = rule
        callCount += 1
        return elementResult
    }

    func elements(_ content: RuleValue, _ rule: String) throws -> [RuleValue] {
        lastRule = rule
        callCount += 1
        return elementsResult
    }

    /// Upstream `AnalyzeByJSoup.getString0` returns the first match only.
    func firstString(_ content: RuleValue, _ rule: String) throws -> String? {
        lastRule = rule
        callCount += 1
        return listResult?.first ?? stringResult
    }
}

/// A variable holder used for `@put:` / `@get:` round-trips.
final class StubHolder: RuleVariableHolder {
    var values: [String: String] = [:]

    func putVariable(_ key: String, _ value: String) { values[key] = value }
    func getVariable(_ key: String) -> String? { values[key] }
}

/// A JavaScript runtime stub.
final class StubScriptEngine: RuleScriptEngine {
    var lastScript: String?
    var result: RuleValue = .text("")

    func evaluate(_ script: String, bindings: [String: RuleValue]) throws -> RuleValue {
        lastScript = script
        return result
    }
}

// MARK: - Marker resolution

final class SourceRuleMarkerTests: XCTestCase {

    func testDefaultMarkerIsCSS() {
        let rule = SourceRule(ruleStr: "div.title")
        XCTAssertEqual(rule.mode, .css)
        XCTAssertEqual(rule.rule, "div.title")
    }

    func testDoubleAtDropsTwoCharacters() {
        let rule = SourceRule(ruleStr: "@@div.title")
        XCTAssertEqual(rule.mode, .css)
        XCTAssertEqual(rule.rule, "div.title")
    }

    func testCssMarkerKeepsTheSelector() {
        // Upstream keeps the "@CSS:" prefix in the rule text — the CSS
        // matcher strips it later (AnalyzeByJSoup.kt:516).
        let rule = SourceRule(ruleStr: "@CSS:div.title")
        XCTAssertEqual(rule.mode, .css)
        XCTAssertEqual(rule.rule, "@CSS:div.title")
    }

    func testXPathMarker() {
        let rule = SourceRule(ruleStr: "@XPath://div/text()")
        XCTAssertEqual(rule.mode, .xpath)
        XCTAssertEqual(rule.rule, "//div/text()")
    }

    func testJsonMarker() {
        let rule = SourceRule(ruleStr: "@Json:$.data[*].name")
        XCTAssertEqual(rule.mode, .json)
        XCTAssertEqual(rule.rule, "$.data[*].name")
    }

    func testJsonIsDetectedAutomatically() {
        XCTAssertEqual(SourceRule(ruleStr: "$.data").mode, .json)
        XCTAssertEqual(SourceRule(ruleStr: "$[0].name").mode, .json)
    }

    func testLeadingSlashIsXPath() {
        let rule = SourceRule(ruleStr: "/html/body")
        XCTAssertEqual(rule.mode, .xpath)
        XCTAssertEqual(rule.rule, "/html/body")
    }

    func testJSONContentForcesJsonMode() {
        let rule = SourceRule(ruleStr: "data.name", isJSON: true)
        XCTAssertEqual(rule.mode, .json)
    }

    func testJSModeShortCircuits() {
        let rule = SourceRule(ruleStr: "1 + 1", mode: .js)
        XCTAssertEqual(rule.mode, .js)
        XCTAssertEqual(rule.rule, "1 + 1")
    }
}

// MARK: - @put: / @get: / $n / ##

final class SourceRuleCompositionTests: XCTestCase {

    func testPutRuleIsExtracted() {
        let rule = SourceRule(ruleStr: "@put:{\"key\":\"value\"}div")
        XCTAssertEqual(rule.putMap["key"], "value")
        XCTAssertFalse(rule.rule.contains("@put:"))
    }

    func testPutRuleAcceptsLenientJSON() {
        // Gson's lenient reader accepts single-quoted strings and unquoted
        // names.
        let rule = SourceRule(ruleStr: "@put:{'key':'value'}div")
        XCTAssertEqual(rule.putMap["key"], "value")
    }

    func testPutRuleRejectsATrailingComma() {
        // Gson's lenient reader still rejects a trailing comma in an object.
        let rule = SourceRule(ruleStr: "@put:{'key':'value',}div")
        XCTAssertNil(rule.putMap["key"])
    }

    func testGetRuleIsRecognised() {
        let rule = SourceRule(ruleStr: "@get:{token}")
        XCTAssertEqual(rule.paramSize, 1)
        XCTAssertEqual(rule.ruleType.first, -2)
        XCTAssertEqual(rule.ruleParam.first, "token")
    }

    func testInlineJSIsRecognised() {
        let rule = SourceRule(ruleStr: "{{java.get(1)}}")
        XCTAssertEqual(rule.paramSize, 1)
        XCTAssertEqual(rule.ruleType.first, -1)
        XCTAssertEqual(rule.ruleParam.first, "java.get(1)")
    }

    func testJSAtTheStartSwitchesToRegexMode() {
        // Upstream: when the first evaluated fragment starts at position 0 the
        // step becomes a regex step, i.e. the JS output *is* the answer.
        let rule = SourceRule(ruleStr: "{{1+1}}")
        XCTAssertEqual(rule.mode, .regex)
    }

    func testGroupReferenceSwitchesToRegexMode() {
        let rule = SourceRule(ruleStr: "$1")
        XCTAssertEqual(rule.mode, .regex)
        XCTAssertEqual(rule.ruleType, [1])
        XCTAssertEqual(rule.ruleParam, ["$1"])
    }

    func testLiteralAndGroupReferenceAreKeptInOrder() {
        let rule = SourceRule(ruleStr: "li$1")
        XCTAssertEqual(rule.ruleType, [0, 1])
        XCTAssertEqual(rule.ruleParam, ["li", "$1"])
    }
}

// MARK: - splitSourceRule

final class SplitSourceRuleTests: XCTestCase {

    func testLiteralOnly() {
        let engine = AnalyzeRule(content: .text("<html></html>"))
        let rules = engine.splitSourceRule("div.title")
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].rule, "div.title")
        XCTAssertEqual(rules[0].mode, .css)
    }

    func testLiteralAndJSChunk() {
        let engine = AnalyzeRule(content: .text("<html></html>"))
        let rules = engine.splitSourceRule("div<js>alert(1)</js>")
        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[0].rule, "div")
        XCTAssertEqual(rules[0].mode, .css)
        XCTAssertEqual(rules[1].rule, "alert(1)")
        XCTAssertEqual(rules[1].mode, .js)
    }

    func testAtJsChunk() {
        let engine = AnalyzeRule(content: .text("<html></html>"))
        let rules = engine.splitSourceRule("@js:result")
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].mode, .js)
        XCTAssertEqual(rules[0].rule, "result")
    }

    func testAllInOneWithLeadingColonIsRegex() {
        let engine = AnalyzeRule(content: .text("<html></html>"))
        let rules = engine.splitSourceRule(":(\\d+)", allInOne: true)
        XCTAssertTrue(engine.isRegex)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].mode, .regex)
        XCTAssertEqual(rules[0].rule, "(\\d+)")
    }

    func testEmptyRuleProducesNoSteps() {
        let engine = AnalyzeRule(content: .text("<html></html>"))
        XCTAssertTrue(engine.splitSourceRule("").isEmpty)
        XCTAssertTrue(engine.splitSourceRule(nil).isEmpty)
    }
}

// MARK: - AnalyzeRule orchestration

final class AnalyzeRuleTests: XCTestCase {

    private func makeEngine(
        content: RuleContent = .text("<html><body><p>hello</p></body></html>")
    ) -> (AnalyzeRule, StubMatcher, StubMatcher, StubMatcher, StubMatcher, StubScriptEngine, StubHolder) {
        let css = StubMatcher()
        let xpath = StubMatcher()
        let json = StubMatcher()
        let regex = StubMatcher()
        let script = StubScriptEngine()
        let holder = StubHolder()
        let engine = AnalyzeRule(content: content)
        engine.cssMatcher = css
        engine.xpathMatcher = xpath
        engine.jsonMatcher = json
        engine.regexMatcher = regex
        engine.scriptEngine = script
        engine.source = holder
        return (engine, css, xpath, json, regex, script, holder)
    }

    func testGetStringUsesTheCSSMatcher() throws {
        let (engine, css, _, _, _, _, _) = makeEngine()
        css.stringResult = "hello"
        let value = try engine.getString("@@p")
        XCTAssertEqual(value, "hello")
        XCTAssertEqual(css.lastRule, "p")
    }

    func testGetStringListUsesTheCSSMatcher() throws {
        let (engine, css, _, _, _, _, _) = makeEngine()
        css.listResult = ["a", "b"]
        let values = try engine.getStringList("@@li")
        XCTAssertEqual(values, ["a", "b"])
    }

    func testGetStringJoinsLinesIntoAList() throws {
        // Upstream splits a *string* result on newlines — that happens for the
        // JavaScript strategy, which is the one that returns raw text.
        let (engine, _, _, _, _, script, _) = makeEngine()
        script.result = .text("a\nb")
        let values = try engine.getStringList("@js:result")
        XCTAssertEqual(values, ["a", "b"])
    }

    func testGetStringResolvesRelativeURLs() throws {
        let (engine, css, _, _, _, _, _) = makeEngine()
        css.listResult = ["a.html", "http://other/b.html", "a.html"]
        engine.redirectUrl = URL(string: "http://host/dir/index.html")
        let values = try engine.getStringList("@@a", isUrl: true)
        XCTAssertEqual(values, ["http://host/dir/a.html", "http://other/b.html"])
    }

    func testGetStringInURLModeUsesTheFirstMatchOnly() throws {
        let (engine, css, _, _, _, _, _) = makeEngine()
        css.listResult = ["first", "second"]
        css.stringResult = "first"
        let value = try engine.getString("@@a", isUrl: true)
        XCTAssertEqual(value, "first")
    }

    func testGroupReferenceResolvesFromThePreviousListResult() throws {
        // `$1` is replaced by the second element of the previous step's list
        // and the step becomes a regex step, so the composed text *is* the
        // answer (upstream `else -> rule`).
        let (engine, css, _, _, _, script, _) = makeEngine()
        css.listResult = ["first", "second"]
        script.result = .list([.text("x"), .text("y")])
        let value = try engine.getString("@@li<js>ignored</js>$1")
        XCTAssertEqual(value, "y")
    }

    func testRegexModeIsNotUsedForAPlainColonSelector() throws {
        // The `:` marker only means "regex" in the all-in-one mode used by
        // getElement / getElements; for getString it is a CSS pseudo-class.
        let (engine, css, _, _, _, _, _) = makeEngine()
        css.stringResult = "matched"
        let value = try engine.getString(":first")
        XCTAssertEqual(value, "matched")
        XCTAssertEqual(css.lastRule, ":first")
    }

    func testGetElementAndGetElements() throws {
        let (engine, css, _, _, _, _, _) = makeEngine()
        css.elementResult = .text("one")
        css.elementsResult = [.text("one"), .text("two")]
        let element = try engine.getElement("@@p")
        XCTAssertEqual(element, .text("one"))
        let elements = try engine.getElements("@@p")
        XCTAssertEqual(elements, [.text("one"), .text("two")])
    }

    func testJSONRouteUsesTheJSONMatcher() throws {
        let (engine, _, _, json, _, _, _) = makeEngine(content: .json(try JSONValue(text: "{\"a\":1}")))
        json.stringResult = "1"
        let value = try engine.getString("@Json:$.a")
        XCTAssertEqual(value, "1")
        XCTAssertEqual(json.lastRule, "$.a")
    }

    func testXPathRouteUsesTheXPathMatcher() throws {
        let (engine, _, xpath, _, _, _, _) = makeEngine()
        xpath.stringResult = "text"
        let value = try engine.getString("@XPath://div/text()")
        XCTAssertEqual(value, "text")
    }

    func testJSRuleIsEvaluatedByTheScriptEngine() throws {
        let (engine, _, _, _, _, script, _) = makeEngine()
        script.result = .text("2")
        let value = try engine.getString("{{1+1}}")
        XCTAssertEqual(value, "2")
        XCTAssertEqual(script.lastScript, "1+1")
    }

    func testPutAndGetVariables() {
        let (engine, _, _, _, _, _, holder) = makeEngine()
        engine.put("token", "abc")
        XCTAssertEqual(holder.getVariable("token"), "abc")
        XCTAssertEqual(engine.get("token"), "abc")
        XCTAssertEqual(engine.get("missing"), "")
    }

    func testBookNameAndTitleVariables() {
        let (engine, _, _, _, _, _, _) = makeEngine()
        engine.bookName = "My Book"
        engine.chapterTitle = "Chapter 1"
        XCTAssertEqual(engine.get("bookName"), "My Book")
        XCTAssertEqual(engine.get("title"), "Chapter 1")
    }

    func testSetContentThrowsWhenTheContentIsNil() {
        let engine = AnalyzeRule(content: .text("x"))
        XCTAssertThrowsError(try engine.setContent(nil)) { error in
            XCTAssertEqual(error as? RuleEngineError, .contentIsNull)
        }
    }

    func testSetBaseUrlOnlyOverwritesWithANonNilValue() {
        let engine = AnalyzeRule(content: .text("x"), baseUrl: "http://a/")
        engine.setBaseUrl(nil)
        XCTAssertEqual(engine.baseUrl, "http://a/")
        engine.setBaseUrl("http://b/")
        XCTAssertEqual(engine.baseUrl, "http://b/")
    }
}

// MARK: - ## replacement

final class ReplaceRegexTests: XCTestCase {

    func testReplacementIsAppliedToTheResult() throws {
        let engine = AnalyzeRule(content: .text("<html></html>"))
        let css = StubMatcher()
        engine.cssMatcher = css
        css.stringResult = "hello world"
        // `##` splits rule / regex / replacement.  The replacement cannot have
        // trailing whitespace — the literal chunk is trimmed before the split.
        let value = try engine.getString("@@p##\\s+##_")
        XCTAssertEqual(value, "hello_world")
    }

    func testReplaceFirstKeepsOnlyTheMatchedText() throws {
        // Upstream: `matcher.group(0).replaceFirst(regex, replacement)` — the
        // replacement is applied to the *matched* text, so the rest of the
        // string is dropped.
        let engine = AnalyzeRule(content: .text("<html></html>"))
        let css = StubMatcher()
        engine.cssMatcher = css
        css.stringResult = "aaa"
        // Four `##` separated parts → the last one switches `replaceFirst` on.
        let value = try engine.getString("@@p##a##b##")
        XCTAssertEqual(value, "b")
    }
}

// MARK: - JSON

final class JSONValueTests: XCTestCase {

    func testBooleansAreNotNumbers() throws {
        let value = try JSONValue(text: "{\"flag\":true,\"count\":1}")
        XCTAssertEqual(value, .object(["flag": .bool(true), "count": .number(1)]))
    }

    func testNestedStructures() throws {
        let value = try JSONValue(text: "[1,{\"a\":\"b\"},null]")
        XCTAssertEqual(value, .array([.number(1), .object(["a": .string("b")]), .null]))
    }

    func testEscapes() throws {
        let value = try JSONValue(text: "{\"a\":\"line\\nbreak\\u0041\"}")
        XCTAssertEqual(value, .object(["a": .string("line\nbreakA")]))
    }

    func testTrailingDataIsRejected() {
        XCTAssertThrowsError(try JSONValue(text: "{} {}"))
    }

    func testIsJSONText() {
        XCTAssertTrue(JSONValue.isJSONText(" {\"a\":1} "))
        XCTAssertTrue(JSONValue.isJSONText("[1]"))
        XCTAssertFalse(JSONValue.isJSONText("<html></html>"))
    }
}

// MARK: - HTML entities

final class RuleEntitiesTests: XCTestCase {

    func testNamedEntities() {
        XCTAssertEqual(RuleEntities.unescapeHTML4("a&amp;b"), "a&b")
        XCTAssertEqual(RuleEntities.unescapeHTML4("&lt;tag&gt;"), "<tag>")
        XCTAssertEqual(RuleEntities.unescapeHTML4("&quot;q&quot;"), "\"q\"")
    }

    func testNumericEntities() {
        XCTAssertEqual(RuleEntities.unescapeHTML4("&#65;"), "A")
        XCTAssertEqual(RuleEntities.unescapeHTML4("&#x41;"), "A")
    }
}

// MARK: - RuleAnalyzer

final class RuleAnalyzerTests: XCTestCase {

    func testSplitOnSingleSeparator() throws {
        let analyzer = RuleAnalyzer("a&&b&&c")
        let parts = try analyzer.splitRule("&&")
        XCTAssertEqual(parts, ["a", "b", "c"])
    }

    func testSplitOnMultipleSeparators() throws {
        // Upstream splits on the separator that is found *first* only — the
        // others are just used to locate the first boundary.  `elementsType`
        // then tells the caller which combinator was used.
        let analyzer = RuleAnalyzer("a||b&&c")
        let parts = try analyzer.splitRule("&&", "||")
        XCTAssertEqual(parts, ["a", "b&&c"])
        XCTAssertEqual(analyzer.elementsType, "||")
    }

    func testSplitKeepsBalancedFilterGroups() throws {
        let analyzer = RuleAnalyzer("div[class~=x]&&span")
        let parts = try analyzer.splitRule("&&")
        XCTAssertEqual(parts, ["div[class~=x]", "span"])
    }

    func testInnerRuleExpandsTheMarker() throws {
        let analyzer = RuleAnalyzer("prefix{{inner}}suffix")
        let result = analyzer.innerRule(inner: "{{", startStep: 2, endStep: 2) { _ in "X" }
        XCTAssertEqual(result, "prefixXsuffix")
    }
}
