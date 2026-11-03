import XCTest
@testable import LegadoCore

/// Port of the XPath behaviour of upstream `AnalyzeByXPath`.
final class XPathMatcherTests: XCTestCase {

    private let matcher = XPathMatcher()

    private let html = "<html><body>"
        + "<div id=\"content\" class=\"box main\">"
        + "<h1>Book Title</h1>"
        + "<p class=\"intro\">First paragraph</p>"
        + "<p class=\"intro\">Second paragraph</p>"
        + "<ul>"
        + "<li><a href=\"/chapter/1\">Chapter One</a></li>"
        + "<li><a href=\"/chapter/2\">Chapter Two</a></li>"
        + "<li><a href=\"/chapter/3\">Chapter Three</a></li>"
        + "</ul>"
        + "<table><tr><td>Cell A</td><td>Cell B</td></tr></table>"
        + "</div></body></html>"

    private func content() -> RuleValue { .text(html) }

    func testSelectsTextOfAnElement() throws {
        let result = try matcher.string(content(), "//h1/text()")
        XCTAssertEqual(result, "Book Title")
    }

    func testSelectsAnAttribute() throws {
        let result = try matcher.string(content(), "//div[@id='content']/@class")
        XCTAssertEqual(result, "box main")
    }

    func testSelectsByPosition() throws {
        let result = try matcher.stringList(content(), "//p/text()")
        XCTAssertEqual(result, ["First paragraph", "Second paragraph"])
    }

    func testSelectsTheNthMatch() throws {
        let result = try matcher.string(content(), "//a[2]/text()")
        XCTAssertEqual(result, "Chapter Two")
    }

    func testSelectsTheLastMatch() throws {
        let result = try matcher.string(content(), "//a[last()]/text()")
        XCTAssertEqual(result, "Chapter Three")
    }

    func testPredicateWithPositionFunction() throws {
        let result = try matcher.string(content(), "//p[position()=2]/text()")
        XCTAssertEqual(result, "Second paragraph")
    }

    func testPredicateWithContains() throws {
        let result = try matcher.string(content(), "//div[contains(@class,'main')]/h1/text()")
        XCTAssertEqual(result, "Book Title")
    }

    func testDescendantTextOfAContainer() throws {
        let result = try matcher.stringList(content(), "//ul//text()")
        XCTAssertEqual(result, ["Chapter One", "Chapter Two", "Chapter Three"])
    }

    func testTableCellIsWrapped() throws {
        // Upstream wraps a bare cell in a table so that //td keeps working.
        let result = try matcher.string(.text("<td>Cell A</td>"), "//td/text()")
        XCTAssertEqual(result, "Cell A")
    }

    func testCountFunction() throws {
        let result = try matcher.string(content(), "count(//a)")
        XCTAssertEqual(result, "3")
    }

    func testStringFunction() throws {
        let result = try matcher.string(content(), "string(//h1)")
        XCTAssertEqual(result, "Book Title")
    }

    func testStartsWithFunction() throws {
        let result = try matcher.stringList(content(), "//a[starts-with(@href,'/chapter/1')]/text()")
        XCTAssertEqual(result, ["Chapter One"])
    }

    func testAbsolutePath() throws {
        let result = try matcher.string(content(), "/html/body/div/h1/text()")
        XCTAssertEqual(result, "Book Title")
    }

    func testAndCombinator() throws {
        // Upstream's "&&" CONCATENATES the per-part results.
        let result = try matcher.stringList(content(), "//p[@class='intro']&&//p[1]/text()")
        XCTAssertEqual(result, ["First paragraph", "Second paragraph", "First paragraph"])
    }

    func testOrCombinator() throws {
        let result = try matcher.stringList(content(), "//h9/text()||//h1/text()")
        XCTAssertEqual(result, ["Book Title"])
    }

    func testInterleaveCombinator() throws {
        let result = try matcher.stringList(content(), "//h1/text()%%//p/text()")
        XCTAssertEqual(result, ["Book Title", "First paragraph"])
    }

    func testElementReturnsTheNode() throws {
        let element = try matcher.element(content(), "//h1")
        XCTAssertEqual(element?.nodeText, "Book Title")
        XCTAssertEqual(element?.nodeTag, "h1")
    }

    func testElementsReturnsEveryNode() throws {
        let elements = try matcher.elements(content(), "//a")
        XCTAssertEqual(elements.count, 3)
        XCTAssertEqual(elements[0].nodeText, "Chapter One")
    }

    func testMissingPathReturnsNil() throws {
        XCTAssertNil(try matcher.string(content(), "//nope/text()"))
    }

    func testAnalyzeRuleResolvesAnXPathRule() throws {
        let analyzeRule = AnalyzeRule(content: .text(html))
        let result = try analyzeRule.getString("//h1/text()")
        XCTAssertEqual(result, "Book Title")
    }
}
