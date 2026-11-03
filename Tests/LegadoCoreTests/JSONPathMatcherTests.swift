import XCTest
@testable import LegadoCore

/// Tests for the port of `AnalyzeByJSonPath` and the JSONPath engine.
final class JSONPathMatcherTests: XCTestCase {

    private let json = """
    {
      "code": 200,
      "data": {
        "name": "Alice",
        "author": "Bob",
        "list": [
          { "title": "第一本", "type": "book", "words": 100 },
          { "title": "第二本", "type": "comic", "words": 200 },
          { "title": "第三本", "type": "book", "words": 300 }
        ]
      }
    }
    """

    private let matcher = JSONPathMatcher()

    private func content() throws -> RuleValue {
        .text(json)
    }

    // MARK: - The JSONPath engine

    func testReadsAChildValue() throws {
        let root = try JSONValue.parse(json)
        XCTAssertEqual(JSONPath.read("$.data.name", in: root)?.textValue, "Alice")
        XCTAssertEqual(JSONPath.read("$.code", in: root)?.textValue, "200")
    }

    func testReadsAnArrayElement() throws {
        let root = try JSONValue.parse(json)
        XCTAssertEqual(JSONPath.read("$.data.list[0].title", in: root)?.textValue, "第一本")
        XCTAssertEqual(JSONPath.read("$.data.list[2].title", in: root)?.textValue, "第三本")
    }

    func testReadsANegativeIndex() throws {
        let root = try JSONValue.parse(json)
        XCTAssertEqual(JSONPath.read("$.data.list[-1].title", in: root)?.textValue, "第三本")
    }

    func testReadsASlice() throws {
        let root = try JSONValue.parse(json)
        let titles = JSONPath.select("$.data.list[0:1].title", in: root).map(\.textValue)
        XCTAssertEqual(titles, ["第一本", "第二本"])
    }

    func testReadsWithAWildcard() throws {
        let root = try JSONValue.parse(json)
        let titles = JSONPath.select("$.data.list[*].title", in: root).map(\.textValue)
        XCTAssertEqual(titles, ["第一本", "第二本", "第三本"])
    }

    func testRecursiveDescent() throws {
        let root = try JSONValue.parse(json)
        let titles = JSONPath.select("$..title", in: root).map(\.textValue)
        XCTAssertEqual(titles, ["第一本", "第二本", "第三本"])
    }

    func testFilterByEquality() throws {
        let root = try JSONValue.parse(json)
        let titles = JSONPath.select("$.data.list[?(@.type == 'book')].title", in: root).map(\.textValue)
        XCTAssertEqual(titles, ["第一本", "第三本"])
    }

    func testFilterByComparison() throws {
        let root = try JSONValue.parse(json)
        let titles = JSONPath.select("$.data.list[?(@.words > 150)].title", in: root).map(\.textValue)
        XCTAssertEqual(titles, ["第二本", "第三本"])
    }

    func testFilterByExistence() throws {
        let root = try JSONValue.parse(json)
        let titles = JSONPath.select("$.data.list[?(@.words)].title", in: root).map(\.textValue)
        XCTAssertEqual(titles, ["第一本", "第二本", "第三本"])
    }

    func testUnionOfNames() throws {
        let root = try JSONValue.parse(json)
        let values = JSONPath.select("$.data['name','author']", in: root).map(\.textValue)
        XCTAssertEqual(values, ["Alice", "Bob"])
    }

    func testMissingPathReturnsNil() throws {
        let root = try JSONValue.parse(json)
        XCTAssertNil(JSONPath.read("$.data.missing", in: root))
    }

    // MARK: - The matcher

    func testStringReadsAScalar() throws {
        XCTAssertEqual(try matcher.string(try content(), "$.data.name"), "Alice")
    }

    func testStringOfAnEmptyRuleIsNil() throws {
        XCTAssertNil(try matcher.string(try content(), ""))
    }

    func testStringOfAMissingPathIsEmpty() throws {
        XCTAssertEqual(try matcher.string(try content(), "$.data.missing"), "")
    }

    func testStringJoinsAnArrayWithNewLines() throws {
        let result = try matcher.string(try content(), "$.data.list[*].title")
        XCTAssertEqual(result, "第一本\n第二本\n第三本")
    }

    func testStringListReturnsOneEntryPerArrayItem() throws {
        let result = try matcher.stringList(try content(), "$.data.list[*].title")
        XCTAssertEqual(result, ["第一本", "第二本", "第三本"])
    }

    func testAndCombinatorJoinsBothResults() throws {
        let result = try matcher.string(try content(), "$.data.name&&$.data.author")
        XCTAssertEqual(result, "Alice\nBob")
    }

    func testOrCombinatorStopsAtTheFirstResult() throws {
        let result = try matcher.string(try content(), "$.data.missing||$.data.name")
        XCTAssertEqual(result, "Alice")
    }

    func testEmbeddedRuleForm() throws {
        // Upstream replaces `{$.rule}` inside a rule with the resolved value.
        let result = try matcher.string(try content(), "{$.data.name}")
        XCTAssertEqual(result, "Alice")
    }

    func testElementReturnsTheRawObject() throws {
        let element = try matcher.element(try content(), "$.data.list[0]")
        XCTAssertNotNil(element)
        XCTAssertEqual(element?.member("title")?.textValue, "第一本")
        XCTAssertEqual(element?.member("words")?.textValue, "100")
    }

    func testElementsReturnsTheRawObjects() throws {
        let elements = try matcher.elements(try content(), "$.data.list[*]")
        XCTAssertEqual(elements.count, 3)
    }

    func testAnalyzeRuleUsesTheJSONPathMatcher() throws {
        let engine = AnalyzeRule(content: .text(json))
        engine.jsonMatcher = JSONPathMatcher()
        XCTAssertEqual(try engine.getString("$.data.name"), "Alice")
        XCTAssertEqual(try engine.getStringList("$.data.list[*].title"), ["第一本", "第二本", "第三本"])
    }
}
