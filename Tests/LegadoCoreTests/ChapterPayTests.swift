import XCTest
@testable import LegadoCore

/// A script engine that answers with a fixed result and records what it got.
private final class PayScriptEngine: RuleScriptEngine {
    var result: RuleValue = .text("")
    var lastScript: String?
    var lastBindings: [String: RuleValue] = [:]

    func evaluate(_ script: String, bindings: [String: RuleValue]) throws -> RuleValue {
        lastScript = script
        lastBindings = bindings
        return result
    }
}

/// The chapter purchase — upstream `ReadBookActivity.payAction()`.
final class ChapterPayTests: XCTestCase {

    private func makeSource(payAction: String?) -> BookSource {
        var source = BookSource(bookSourceUrl: "https://example.com")
        if let payAction {
            let escaped = payAction
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            source.ruleContent = "{\"payAction\":\"\(escaped)\"}"
        }
        return source
    }

    private func makeBook() -> Book {
        Book(
            bookUrl: "https://example.com/book/1",
            tocUrl: "https://example.com/book/1",
            origin: "https://example.com",
            originName: "测试书源",
            name: "测试书",
            author: "作者"
        )
    }

    private func makeChapter() -> BookChapter {
        BookChapter(
            url: "https://example.com/book/1/2",
            title: "第二章",
            index: 1
        )
    }

    func testAnAbsoluteUrlOpensTheWebView() throws {
        let engine = PayScriptEngine()
        engine.result = .text("https://example.com/pay")
        let result = try ChapterPay.pay(
            source: makeSource(payAction: "pay()"),
            book: makeBook(),
            chapter: makeChapter(),
            dependencies: AnalyzeUrlDependencies(scriptEngine: engine)
        )
        XCTAssertEqual(result, .openURL("https://example.com/pay"))
    }

    func testTrueRefreshesTheTableOfContents() throws {
        let engine = PayScriptEngine()
        engine.result = .text("true")
        let result = try ChapterPay.pay(
            source: makeSource(payAction: "pay()"),
            book: makeBook(),
            chapter: makeChapter(),
            dependencies: AnalyzeUrlDependencies(scriptEngine: engine)
        )
        XCTAssertEqual(result, .refreshTableOfContents)
    }

    func testAnyOtherResultIsIgnored() throws {
        let engine = PayScriptEngine()
        engine.result = .text("false")
        let result = try ChapterPay.pay(
            source: makeSource(payAction: "pay()"),
            book: makeBook(),
            chapter: makeChapter(),
            dependencies: AnalyzeUrlDependencies(scriptEngine: engine)
        )
        XCTAssertEqual(result, .ignored("false"))
    }

    func testASourceWithoutTheScriptThrows() {
        XCTAssertThrowsError(try ChapterPay.pay(
            source: makeSource(payAction: nil),
            book: makeBook(),
            chapter: makeChapter()
        )) { error in
            XCTAssertEqual(error as? ChapterPayError, .noPayAction)
        }
    }

    func testAnEmptyScriptThrows() {
        XCTAssertThrowsError(try ChapterPay.pay(
            source: makeSource(payAction: "   "),
            book: makeBook(),
            chapter: makeChapter()
        )) { error in
            XCTAssertEqual(error as? ChapterPayError, .noPayAction)
        }
    }

    /// The script runs with the chapter as the context — the base URL is the
    /// URL of the chapter, the chapter and the book are bound.
    func testTheScriptContext() throws {
        let engine = PayScriptEngine()
        engine.result = .text("true")
        let chapter = makeChapter()
        _ = try ChapterPay.pay(
            source: makeSource(payAction: "pay()"),
            book: makeBook(),
            chapter: chapter,
            dependencies: AnalyzeUrlDependencies(scriptEngine: engine)
        )
        XCTAssertEqual(engine.lastScript, "pay()")
        XCTAssertEqual(engine.lastBindings["baseUrl"], .text(chapter.url))
        XCTAssertEqual(engine.lastBindings["title"], .text(chapter.title))
        let book = engine.lastBindings["book"]
        guard case .scriptObject(let members)? = book else {
            return XCTFail("the book is not bound")
        }
        XCTAssertEqual(members["name"], .text("测试书"))
        let boundChapter = engine.lastBindings["chapter"]
        guard case .scriptObject(let chapterMembers)? = boundChapter else {
            return XCTFail("the chapter is not bound")
        }
        XCTAssertEqual(chapterMembers["url"], .text(chapter.url))
        XCTAssertEqual(chapterMembers["title"], .text(chapter.title))
    }
}
