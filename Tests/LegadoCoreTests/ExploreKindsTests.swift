//
//  ExploreKindsTests.swift
//  LegadoCoreTests
//
//  The tests of the explore categories — upstream
//  `help/source/BookSourceExtensions.kt` (`exploreKinds()`).
//
//  The script form of the rule is the one the collection of the common
//  sources uses (`<js>…</js>` and `@js:`), and it has to be evaluated before
//  the categories are parsed: without the evaluation the text of the script
//  was split on `::` and the reader saw categories named "<js>".
//

import XCTest
@testable import LegadoCore

final class ExploreKindsTests: XCTestCase {

    /// A script engine that answers with a canned rule and records the calls.
    private final class KindsEngine: RuleScriptEngine {
        let answer: String
        private(set) var scripts: [String] = []
        private(set) var contexts: [ScriptSourceContext?] = []

        init(answer: String) {
            self.answer = answer
        }

        func evaluate(_ script: String, bindings: [String: RuleValue]) throws -> RuleValue {
            scripts.append(script)
            contexts.append(nil)
            return .text(answer)
        }

        func evaluate(
            _ script: String,
            bindings: [String: RuleValue],
            source: ScriptSourceContext?
        ) throws -> RuleValue {
            scripts.append(script)
            contexts.append(source)
            return .text(answer)
        }
    }

    private func makeSource() -> BookSource {
        BookSource(bookSourceUrl: "https://a.com", bookSourceName: "A")
    }

    override func setUp() {
        super.setUp()
        ExploreKinds.clearCache()
    }

    /// A JSON array of the categories is offered as it is.
    func testJsonArrayRuleIsParsed() {
        let kinds = ExploreKinds.parse(#"[{"title":"玄幻","url":"https://a.com/x"}]"#)
        XCTAssertEqual(kinds.map(\.title), ["玄幻"])
        XCTAssertEqual(kinds.first?.url, "https://a.com/x")
    }

    /// The plain list form keeps the upstream separator.
    func testPlainListRuleIsParsed() {
        let kinds = ExploreKinds.parse("玄幻::https://a.com/x&&都市::https://a.com/y")
        XCTAssertEqual(kinds.map(\.title), ["玄幻", "都市"])
        XCTAssertEqual(kinds.map(\.url), ["https://a.com/x", "https://a.com/y"])
    }

    /// The `<js>` form is evaluated with the source — the rule the script
    /// returns is the one that is parsed.
    func testScriptRuleIsEvaluatedWithTheSource() {
        let engine = KindsEngine(answer: #"[{"title":"连载","url":"/lianzai"}]"#)
        let source = makeSource()
        let kinds = ExploreKinds.parse(
            "<js>\nJSON.stringify([[\"连载\",\"lianzai\"]].map(x => ({title: x[0], url: \"/\" + x[1]})))\n</js>",
            engine: engine,
            source: source
        )
        XCTAssertEqual(kinds.map(\.title), ["连载"])
        XCTAssertEqual(kinds.first?.url, "/lianzai")
        // The wrapper is stripped and the source is bound.
        XCTAssertEqual(engine.scripts.count, 1)
        XCTAssertEqual(
            engine.scripts.first,
            "\nJSON.stringify([[\"连载\",\"lianzai\"]].map(x => ({title: x[0], url: \"/\" + x[1]})))\n"
        )
        XCTAssertEqual(engine.contexts.count, 1)
        XCTAssertEqual(engine.contexts[0]?.bookSource?.bookSourceUrl, "https://a.com")
        XCTAssertEqual(engine.contexts[0]?.key, "https://a.com")
    }

    /// The `@js:` form strips the four character marker — upstream
    /// `substring(4)`.
    func testAtJsRuleIsEvaluated() {
        let engine = KindsEngine(answer: "玄幻::https://a.com/x")
        let kinds = ExploreKinds.parse("@js:\n[['玄幻']]", engine: engine, source: makeSource())
        XCTAssertEqual(kinds.map(\.title), ["玄幻"])
        XCTAssertEqual(engine.scripts.first, "\n[['玄幻']]")
    }

    /// Without an engine the script form offers no categories — it must not
    /// be split into the text of the script.
    func testTheScriptFormWithoutAnEngineHasNoCategories() {
        let kinds = ExploreKinds.parse("<js>result = 'x'</js>", engine: nil, source: makeSource())
        XCTAssertTrue(kinds.isEmpty)
    }

    /// The empty answer of a call without an engine must not be cached: the
    /// next call that has the engine evaluates the script.
    func testTheAnswerWithoutAnEngineDoesNotPoisonTheCache() {
        let engine = KindsEngine(answer: #"[{"title":"玄幻","url":"https://a.com/x"}]"#)
        let source = makeSource()
        XCTAssertTrue(ExploreKinds.parse("@js:rule", engine: nil, source: source).isEmpty)
        XCTAssertEqual(ExploreKinds.parse("@js:rule", engine: engine, source: source).count, 1)
    }

    /// A script that fails offers no categories either.
    func testAFailingScriptHasNoCategories() {
        final class FailingEngine: RuleScriptEngine {
            func evaluate(_ script: String, bindings: [String: RuleValue]) throws -> RuleValue {
                throw ScriptEngineError.scriptFailed("boom")
            }
        }
        let kinds = ExploreKinds.parse("@js:x", engine: FailingEngine(), source: makeSource())
        XCTAssertTrue(kinds.isEmpty)
    }

    /// The categories of the script are cached — upstream `exploreKindsMap` —
    /// and a refresh drops them, so the next call evaluates again.
    func testTheScriptCategoriesAreCachedAndTheCacheCanBeCleared() {
        let engine = KindsEngine(answer: #"[{"title":"玄幻","url":"https://a.com/x"}]"#)
        let source = makeSource()
        _ = ExploreKinds.parse("@js:rule", engine: engine, source: source)
        _ = ExploreKinds.parse("@js:rule", engine: engine, source: source)
        XCTAssertEqual(engine.scripts.count, 1)
        ExploreKinds.clearCache()
        _ = ExploreKinds.parse("@js:rule", engine: engine, source: source)
        XCTAssertEqual(engine.scripts.count, 2)
    }

    /// Editing the rule invalidates the cache entry — the key holds the rule.
    func testAChangedRuleIsEvaluatedAgain() {
        let engine = KindsEngine(answer: #"[{"title":"玄幻","url":"https://a.com/x"}]"#)
        let source = makeSource()
        _ = ExploreKinds.parse("@js:one", engine: engine, source: source)
        _ = ExploreKinds.parse("@js:two", engine: engine, source: source)
        XCTAssertEqual(engine.scripts.count, 2)
    }
}
