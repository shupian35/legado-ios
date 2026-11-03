import XCTest
@testable import LegadoCore

/// Tests for the Swift port of `AnalyzeByJSoup`.
///
/// Upstream: app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt
final class CSSMatcherTests: XCTestCase {

    private let html = """
    <html><body>
    <div class="list">
      <div class="item"><a href="/a1">Book One</a></div>
      <div class="item"><a href="/a2">Book Two</a></div>
      <div class="item"><a href="/a3">Book Three</a></div>
      <div class="item"><a href="/a4">Book Four</a></div>
    </div>
    <p class="note">first<span>second</span></p>
    <script>var x = 1;</script>
    </body></html>
    """

    private func matcher() -> CSSMatcher { CSSMatcher() }

    private func content() -> RuleValue { .text(html) }

    // MARK: - Terminal rules

    func testCssSelectorWithTextTerminal() throws {
        let result = try matcher().stringList(content(), "@CSS:div.item@text")
        XCTAssertEqual(result, ["Book One", "Book Two", "Book Three", "Book Four"])
    }

    func testCssSelectorWithAttributeTerminal() throws {
        let result = try matcher().stringList(content(), "@CSS:a@href")
        XCTAssertEqual(result, ["/a1", "/a2", "/a3", "/a4"])
    }

    func testFirstStringReturnsOnlyTheFirstMatch() throws {
        let result = try matcher().firstString(content(), "@CSS:div.item@text")
        XCTAssertEqual(result, "Book One")
    }

    func testStringJoinsEveryMatchWithNewline() throws {
        let result = try matcher().string(content(), "@CSS:div.item@text")
        XCTAssertEqual(result, "Book One\nBook Two\nBook Three\nBook Four")
    }

    func testTextNodesTerminal() throws {
        // Upstream uses jsoup's `element.textNodes()`, which returns the *direct*
        // text children only — the `<span>` is not included.
        let result = try matcher().stringList(content(), "@CSS:p.note@textNodes")
        XCTAssertEqual(result, ["first"])
    }

    func testOwnTextTerminal() throws {
        let result = try matcher().stringList(content(), "@CSS:p.note@ownText")
        XCTAssertEqual(result, ["first"])
    }

    func testAllTerminalReturnsOuterHtml() throws {
        let result = try matcher().stringList(content(), "@CSS:div.item@all")
        XCTAssertEqual(result?.count, 1)
        XCTAssertTrue(result?.first?.contains("<div class=\"item\">") == true)
    }

    func testHtmlTerminalRemovesScripts() throws {
        let result = try matcher().stringList(content(), "@CSS:div.list@html")
        XCTAssertEqual(result?.count, 1)
        XCTAssertFalse(result?.first?.contains("<script") == true)
    }

    // MARK: - Legacy chain syntax

    func testLegacyChainWalksDownTheTree() throws {
        let result = try matcher().stringList(content(), "div.list@div.item@text")
        XCTAssertEqual(result, ["Book One", "Book Two", "Book Three", "Book Four"])
    }

    func testLegacyChainWithAttribute() throws {
        let result = try matcher().stringList(content(), "div.list@div.item@a@href")
        XCTAssertEqual(result, ["/a1", "/a2", "/a3", "/a4"])
    }

    // MARK: - Index syntax

    func testLegacyIndexSelectsOneElement() throws {
        let result = try matcher().stringList(content(), "div.list@div.item.1@text")
        XCTAssertEqual(result, ["Book Two"])
    }

    func testLegacyNegativeIndexSelectsTheLastElement() throws {
        let result = try matcher().stringList(content(), "div.list@div.item.-1@text")
        XCTAssertEqual(result, ["Book Four"])
    }

    func testLegacyExclusionIndexRemovesElements() throws {
        let result = try matcher().stringList(content(), "div.list@div.item!0@text")
        XCTAssertEqual(result, ["Book Two", "Book Three", "Book Four"])
    }

    func testBracketIndexSelectsOneElement() throws {
        let result = try matcher().stringList(content(), "div.list@div.item[2]@text")
        XCTAssertEqual(result, ["Book Three"])
    }

    func testBracketNegativeIndexSelectsTheLastElement() throws {
        let result = try matcher().stringList(content(), "div.list@div.item[-1]@text")
        XCTAssertEqual(result, ["Book Four"])
    }

    func testBracketRangeSelectsEveryElementOfTheRange() throws {
        let result = try matcher().stringList(content(), "div.list@div.item[0:2]@text")
        XCTAssertEqual(result, ["Book One", "Book Two", "Book Three"])
    }

    func testBracketRangeReversesTheList() throws {
        let result = try matcher().stringList(content(), "div.list@div.item[-1:0]@text")
        XCTAssertEqual(result, ["Book Four", "Book Three", "Book Two", "Book One"])
    }

    func testBracketExclusionRemovesElements() throws {
        let result = try matcher().stringList(content(), "div.list@div.item[!0]@text")
        XCTAssertEqual(result, ["Book Two", "Book Three", "Book Four"])
    }

    // MARK: - Combinators

    func testAndConcatenatesTheResults() throws {
        // The `@CSS:` prefix is stripped once, from the front of the whole rule,
        // so the later parts are plain CSS selectors.
        let result = try matcher().stringList(content(), "@CSS:div.item@text&&p.note@ownText")
        XCTAssertEqual(result, ["Book One", "Book Two", "Book Three", "Book Four", "first"])
    }

    func testOrFallsBackToTheNextRule() throws {
        let result = try matcher().stringList(content(), "@CSS:span.missing@text||div.item@text")
        XCTAssertEqual(result, ["Book One", "Book Two", "Book Three", "Book Four"])
    }

    func testPercentInterleavesTheResults() throws {
        // The scanner splits on the separator that appears first, so `%%` has to
        // be the only separator in the rule for the interleave to happen.
        let result = try matcher().stringList(content(), "@CSS:div.item@text%%p.note@ownText")
        XCTAssertEqual(result, ["Book One", "first", "Book Two", "Book Three", "Book Four"])
    }

    // MARK: - Integration with the rule engine

    func testAnalyzeRuleUsesTheCssMatcher() throws {
        let engine = AnalyzeRule(content: .text(html))
        let css = CSSMatcher()
        engine.cssMatcher = css
        let result = try engine.getString("@CSS:div.item@text")
        XCTAssertEqual(result, "Book One\nBook Two\nBook Three\nBook Four")
    }

    func testAnalyzeRuleResolvesRelativeUrls() throws {
        // Upstream resolves relative URLs against the *redirect* URL, which the
        // fetch layer sets; without it the relative URL is kept as-is. For a
        // URL rule only the *first* match is returned (`getString0`).
        let engine = AnalyzeRule(content: .text(html), baseUrl: "http://host/list/")
        let css = CSSMatcher()
        engine.cssMatcher = css
        let result = try engine.getString("@CSS:a@href", isUrl: true)
        XCTAssertEqual(result, "/a1")
    }
}
