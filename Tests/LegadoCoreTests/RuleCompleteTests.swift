//
//  RuleCompleteTests.swift
//  LegadoCoreTests
//
//  The rule auto-completion — upstream `help/RuleComplete.kt`.
//

import XCTest
@testable import LegadoCore

final class RuleCompleteTests: XCTestCase {

    func testTheTextRuleIsAppended() {
        XCTAssertEqual(RuleComplete.autoComplete(rules: "class.name"), "class.name@text")
    }

    func testTheLinkRuleIsAppended() {
        XCTAssertEqual(RuleComplete.autoComplete(rules: "class.name", type: .link), "class.name@href")
    }

    func testTheImageRuleIsAppended() {
        XCTAssertEqual(RuleComplete.autoComplete(rules: "class.name", type: .image), "class.name@src")
    }

    func testEverySeparatorGetsItsOwnRule() {
        // The upstream completes every segment that does not say what to take:
        // "class.name&&class.year" → "class.name@text&&class.year@text".
        XCTAssertEqual(
            RuleComplete.autoComplete(rules: "class.name&&class.year"),
            "class.name@text&&class.year@text"
        )
        XCTAssertEqual(
            RuleComplete.autoComplete(rules: "a%%b||c"),
            "a@text%%b@text||c@text"
        )
        // A segment that already takes the text is left alone.
        XCTAssertEqual(
            RuleComplete.autoComplete(rules: "div.a@text&&div.b"),
            "div.a@text&&div.b@text"
        )
    }

    func testARuleThatAlreadyTakesTheTextIsLeftAlone() {
        XCTAssertEqual(RuleComplete.autoComplete(rules: "class.name@text"), "class.name@text")
        XCTAssertEqual(RuleComplete.autoComplete(rules: "class.name@href"), "class.name@href")
        XCTAssertEqual(RuleComplete.autoComplete(rules: "class.name@src"), "class.name@src")
    }

    func testTheSuffixMayBeFollowedByEmptyParentheses() {
        XCTAssertEqual(RuleComplete.autoComplete(rules: "class.name@text()"), "class.name@text()")
    }

    func testTheXPathRulesUseTheirOwnSuffixes() {
        XCTAssertEqual(RuleComplete.autoComplete(rules: "//div"), "//div//text()")
        XCTAssertEqual(RuleComplete.autoComplete(rules: "//div", type: .link), "//div//@href")
        XCTAssertEqual(RuleComplete.autoComplete(rules: "@XPath://div"), "@XPath://div//text()")
    }

    func testTheComplexRulesAreNeverCompleted() {
        XCTAssertEqual(RuleComplete.autoComplete(rules: "{{js}}"), "{{js}}")
        XCTAssertEqual(RuleComplete.autoComplete(rules: "@js:result"), "@js:result")
        XCTAssertEqual(RuleComplete.autoComplete(rules: "<js>result</js>"), "<js>result</js>")
        XCTAssertEqual(RuleComplete.autoComplete(rules: "@Json:$.data"), "@Json:$.data")
        XCTAssertEqual(RuleComplete.autoComplete(rules: ":text"), ":text")
        XCTAssertEqual(RuleComplete.autoComplete(rules: "##text"), "##text")
    }

    func testThePreRuleBlocksTheCompletion() {
        XCTAssertEqual(RuleComplete.autoComplete(rules: "class.name", preRule: "{{js}}"), "class.name")
    }

    func testTheTailRuleIsKept() {
        XCTAssertEqual(RuleComplete.autoComplete(rules: "class.name##.author"), "class.name@text##.author")
        XCTAssertEqual(RuleComplete.autoComplete(rules: "class.name##a##b"), "class.name@text##a##b")
    }

    func testTheImageRuleTakesTheAltText() {
        XCTAssertEqual(RuleComplete.applyImageFix("@alt", to: "img.name@text"), "img.name@alt")
        XCTAssertEqual(RuleComplete.autoComplete(rules: "img"), "img@alt")
        XCTAssertEqual(RuleComplete.autoComplete(rules: "img.name"), "img.name@alt")
    }

    func testAnImageThatTakesTheSourceIsLeftAlone() {
        XCTAssertEqual(RuleComplete.autoComplete(rules: "img@src"), "img@src")
    }

    func testTheEmptyRuleIsReturnedAsItIs() {
        XCTAssertEqual(RuleComplete.autoComplete(rules: ""), "")
        XCTAssertNil(RuleComplete.autoComplete(rules: nil))
    }

    func testTheTailIsSplitOff() {
        let (cleaned, tail) = RuleComplete.splitTail("a##b##c")
        XCTAssertEqual(cleaned, "a")
        XCTAssertEqual(tail, "##b##c")
        let (cleaned2, tail2) = RuleComplete.splitTail("a")
        XCTAssertEqual(cleaned2, "a")
        XCTAssertEqual(tail2, "")
    }

    func testTheCompletionIsNeededWhenTheSuffixIsMissing() {
        XCTAssertTrue(RuleComplete.needsCompletion("class.name"))
        XCTAssertFalse(RuleComplete.needsCompletion("class.name@text"))
        XCTAssertFalse(RuleComplete.needsCompletion("text"))
        XCTAssertTrue(RuleComplete.needsCompletion("a.text"))
    }

    func testTheSubRulesOfARuleGroupAreCompleted() throws {
        let rule = """
        {"bookList":"div.book","name":"div.name","author":"div.author","coverUrl":"img@src","bookUrl":"a.href"}
        """
        let result = try XCTUnwrap(RuleAutoCompleter.complete(ruleJSON: rule, kind: .search))
        let object = try XCTUnwrap(try JSONValue.parse(result).objectValue)
        // The list rule is the pre-rule — it is not completed.
        XCTAssertEqual(object["bookList"]?.stringValue, "div.book")
        XCTAssertEqual(object["name"]?.stringValue, "div.name@text")
        XCTAssertEqual(object["author"]?.stringValue, "div.author@text")
        // The image rule already says what to take.
        XCTAssertEqual(object["coverUrl"]?.stringValue, "img@src")
        // The link rule gets the link suffix.
        XCTAssertEqual(object["bookUrl"]?.stringValue, "a.href@href")
    }

    func testTheTocRuleGroupIsCompleted() throws {
        let rule = """
        {"chapterList":"div.chapter","chapterName":"div.name","chapterUrl":"a.href"}
        """
        let result = try XCTUnwrap(RuleAutoCompleter.complete(ruleJSON: rule, kind: .toc))
        let object = try XCTUnwrap(try JSONValue.parse(result).objectValue)
        XCTAssertEqual(object["chapterName"]?.stringValue, "div.name@text")
        XCTAssertEqual(object["chapterUrl"]?.stringValue, "a.href@href")
    }

    func testAnInvalidRuleIsReturnedAsItIs() {
        XCTAssertEqual(RuleAutoCompleter.complete(ruleJSON: "not json", kind: .search), "not json")
        XCTAssertEqual(RuleAutoCompleter.complete(ruleJSON: "", kind: .search), "")
    }
}
