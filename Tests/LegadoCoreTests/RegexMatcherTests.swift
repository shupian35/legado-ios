import XCTest
@testable import LegadoCore

/// Tests for the port of `AnalyzeByRegex`.
final class RegexMatcherTests: XCTestCase {

    private let matcher = RegexMatcher()

    func testElementReturnsWholeMatchAndGroups() throws {
        let value = RuleValue.text("name: Alice")
        let result = try matcher.element(value, "(name): (\\w+)")?.listValue?.map(\.textValue)
        XCTAssertEqual(result, ["name: Alice", "name", "Alice"])
    }

    func testElementReturnsNilWhenThereIsNoMatch() throws {
        let value = RuleValue.text("nothing here")
        XCTAssertNil(try matcher.element(value, "(zzz)"))
    }

    func testElementWithStagedRulesFeedsTheNextStage() throws {
        // With a single stage upstream returns the groups of the *first* match.
        let value = RuleValue.text("<a>1</a><a>2</a>")
        let result = try matcher.element(value, "<a>(\\d+)</a>")?.listValue?.map(\.textValue)
        XCTAssertEqual(result, ["<a>1</a>", "1"])
    }

    func testElementWithTwoStages() throws {
        // Every stage but the last concatenates all of its matches.
        let value = RuleValue.text("<x>1</x><x>2</x>")
        let result = try matcher.element(value, "<x>(\\d)</x>&&(\\d)")?.listValue?.map(\.textValue)
        XCTAssertEqual(result, ["1", "1"])
    }

    func testElementsReturnsOneGroupListPerMatch() throws {
        let value = RuleValue.text("a1 a2 a3")
        let elements = try matcher.elements(value, "a(\\d)")
        XCTAssertEqual(elements.count, 3)
        XCTAssertEqual(elements[0].listValue?.map(\.textValue), ["a1", "1"])
        XCTAssertEqual(elements[2].listValue?.map(\.textValue), ["a3", "3"])
    }

    func testElementsIsEmptyWhenThereIsNoMatch() throws {
        let value = RuleValue.text("nothing")
        XCTAssertTrue(try matcher.elements(value, "z(\\d)").isEmpty)
    }

    func testElementsWithTwoStages() throws {
        let value = RuleValue.text("<x>1</x><x>2</x>")
        let elements = try matcher.elements(value, "<x>(\\d)</x>&&(\\d)")
        XCTAssertEqual(elements.count, 2)
        XCTAssertEqual(elements[0].listValue?.map(\.textValue), ["1", "1"])
        XCTAssertEqual(elements[1].listValue?.map(\.textValue), ["2", "2"])
    }

    func testInvalidPatternThrows() throws {
        let value = RuleValue.text("text")
        XCTAssertThrowsError(try matcher.element(value, "([unclosed"))
    }

    func testAnalyzeRuleUsesTheRegexMatcherForElementMode() throws {
        let engine = AnalyzeRule(content: .text("name: Alice"))
        engine.regexMatcher = RegexMatcher()
        let element = try engine.getElement(":name: (\\w+)")
        XCTAssertEqual(element?.listValue?.map(\.textValue), ["name: Alice", "Alice"])
    }

    func testAnalyzeRuleUsesTheRegexMatcherForElementsMode() throws {
        let engine = AnalyzeRule(content: .text("a1 a2"))
        engine.regexMatcher = RegexMatcher()
        let elements = try engine.getElements(":a(\\d)")
        XCTAssertEqual(elements.count, 2)
        XCTAssertEqual(elements[0].listValue?.map(\.textValue), ["a1", "1"])
    }
}
