import XCTest

@testable import LegadoCore

/// The tests of the source debugger — the port of `model/Debug.kt`.
final class DebugTests: XCTestCase {

    // MARK: - The helpers

    private struct LogLine {
        let state: Int
        let message: String
    }

    private final class Collector: DebugLogSink {
        var lines: [LogLine] = []
        func printLog(state: Int, message: String) {
            lines.append(LogLine(state: state, message: message))
        }
    }

    private func makeDependencies(_ body: @escaping @Sendable (HttpRequest) -> String) -> AnalyzeUrlDependencies {
        let client = StubHttpClient { request in
            HttpResponse(url: request.url, body: body(request))
        }
        return AnalyzeUrlDependencies(httpClient: client)
    }

    private func makeRecordingDependencies(
        _ body: @escaping @Sendable (HttpRequest) -> String
    ) -> (AnalyzeUrlDependencies, StubHttpClient) {
        let client = StubHttpClient { request in
            HttpResponse(url: request.url, body: body(request))
        }
        return (AnalyzeUrlDependencies(httpClient: client), client)
    }

    private func makeSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.com",
            bookSourceName: "示例书源",
            enabled: true,
            searchUrl: "https://example.com/search?key={{key}}",
            ruleSearch: "{\"bookList\":\"div.item\",\"name\":\"a.name@text\",\"author\":\"span.author@text\",\"bookUrl\":\"a@href\",\"intro\":\"p.intro@text\"}",
            ruleBookInfo: "{\"name\":\"div.name@text\",\"author\":\"div.author@text\",\"intro\":\"div.intro@text\",\"coverUrl\":\"img.cover@src\",\"tocUrl\":\"a.toc@href\"}",
            ruleToc: "{\"chapterList\":\"div.chapter\",\"chapterName\":\"a.title@text\",\"chapterUrl\":\"a@href\",\"chapterNext\":\"a.next@href\"}",
            ruleContent: "{\"content\":\"div.content@text\",\"nextContentUrl\":\"a.next@href\"}"
        )
    }

    // MARK: - The log format

    func testTheElapsedTimeIsFormattedLikeUpstream() {
        var now = Date(timeIntervalSince1970: 0)
        let debugger = SourceDebugger(dateProvider: { now })
        now = Date(timeIntervalSince1970: 65.432)
        XCTAssertEqual(debugger.elapsedText(), "[01:05.432]")
    }

    func testTheLogLineIsPrefixedWithTheElapsedTime() {
        var now = Date(timeIntervalSince1970: 0)
        let collector = Collector()
        let debugger = SourceDebugger(sink: collector, dateProvider: { now })
        now = Date(timeIntervalSince1970: 1.5)
        debugger.log("开始")
        XCTAssertEqual(collector.lines.count, 1)
        XCTAssertEqual(collector.lines[0].message, "[00:01.500] 开始")
        XCTAssertEqual(collector.lines[0].state, 1)
    }

    func testTheLogLineCanHideTheTime() {
        let collector = Collector()
        let debugger = SourceDebugger(sink: collector)
        debugger.log("完成", showTime: false)
        XCTAssertEqual(collector.lines[0].message, "完成")
    }

    // MARK: - The book source debug

    func testTheSearchKeyRunsTheWholeChain() async {
        let body: @Sendable (HttpRequest) -> String = { request in
            if request.url.contains("/search") {
                return """
                <div class="item"><a class="name" href="/book/1">测试书</a><span class="author">作者</span><p class="intro">简介</p></div>
                """
            }
            if request.url.contains("/toc") {
                return """
                <div class="chapter"><a class="title" href="/book/1/1">第一章</a></div>
                <div class="chapter"><a class="title" href="/book/1/2">第二章</a></div>
                """
            }
            if request.url.contains("/1/1") {
                return "<div class=\"content\">正文内容</div>"
            }
            if request.url.contains("/book/1") {
                return """
                <div class="name">测试书</div><div class="author">作者</div><a class="toc" href="/book/1/toc">目录</a>
                """
            }
            return "<div class=\"content\">正文内容</div>"
        }
        let collector = Collector()
        let debugger = SourceDebugger(sink: collector)
        let (dependencies, client) = makeRecordingDependencies(body)
        let state = await debugger.debugBookSource(
            makeSource(),
            key: "关键字",
            dependencies: dependencies
        )
        XCTAssertEqual(state, 1000)
        let messages = collector.lines.map { $0.message }
        if state != 1000 {
            print("DEBUG LINES: \(messages)")
            print("REQUESTS: \(client.requests.map { $0.url })")
        }
        XCTAssertTrue(messages.contains { $0.contains("⇒开始搜索关键字:关键字") })
        XCTAssertTrue(messages.contains { $0.contains("︾开始解析搜索页") })
        XCTAssertTrue(messages.contains { $0.contains("︽搜索页解析完成") })
        XCTAssertTrue(messages.contains { $0.contains("︾开始解析详情页") })
        XCTAssertTrue(messages.contains { $0.contains("︾开始解析目录页") })
        XCTAssertTrue(messages.contains { $0.contains("︾开始解析正文页") })
        XCTAssertTrue(messages.contains { $0.contains("︽正文页解析完成") })
        XCTAssertEqual(collector.lines.last?.state, 1000)
    }

    func testAnAbsoluteUrlKeyParsesTheDetailPage() async {
        let body: @Sendable (HttpRequest) -> String = { request in
            if request.url.contains("/book/9") {
                return """
                <div class="name">详情书</div><a class="toc" href="/book/9/toc">目录</a>
                """
            }
            if request.url.contains("/toc") {
                return """
                <div class="chapter"><a class="title" href="/book/9/1">第一章</a></div>
                """
            }
            return "<div class=\"content\">正文</div>"
        }
        let collector = Collector()
        let debugger = SourceDebugger(sink: collector)
        _ = await debugger.debugBookSource(
            makeSource(),
            key: "https://example.com/book/9",
            dependencies: makeDependencies(body)
        )
        let messages = collector.lines.map { $0.message }
        XCTAssertTrue(messages.contains { $0.contains("⇒开始访问详情页:https://example.com/book/9") })
        XCTAssertFalse(messages.contains { $0.contains("开始搜索关键字") })
    }

    func testTheDoublePlusKeyParsesTheTableOfContents() async {
        let body: @Sendable (HttpRequest) -> String = { request in
            if request.url.contains("/toc") {
                return "<div class=\"chapter\"><a class=\"title\" href=\"/c/1\">第一章</a></div>"
            }
            return "<div class=\"content\">正文</div>"
        }
        let collector = Collector()
        let debugger = SourceDebugger(sink: collector)
        _ = await debugger.debugBookSource(
            makeSource(),
            key: "++https://example.com/toc",
            dependencies: makeDependencies(body)
        )
        let messages = collector.lines.map { $0.message }
        XCTAssertTrue(messages.contains { $0.contains("⇒开始访目录页:https://example.com/toc") })
        XCTAssertTrue(messages.contains { $0.contains("︾开始解析目录页") })
    }

    func testTheDoubleMinusKeyParsesTheContent() async {
        let body: @Sendable (HttpRequest) -> String = { _ in
            "<div class=\"content\">正文</div>"
        }
        let collector = Collector()
        let debugger = SourceDebugger(sink: collector)
        _ = await debugger.debugBookSource(
            makeSource(),
            key: "--https://example.com/chapter/1",
            dependencies: makeDependencies(body)
        )
        let messages = collector.lines.map { $0.message }
        XCTAssertTrue(messages.contains { $0.contains("⇒开始访正文页:https://example.com/chapter/1") })
        XCTAssertTrue(messages.contains { $0.contains("︾开始解析正文页") })
    }

    func testAFailingRequestEndsTheDebugWithTheErrorState() async {
        let collector = Collector()
        let debugger = SourceDebugger(sink: collector)
        let state = await debugger.debugBookSource(
            makeSource(),
            key: "关键字",
            dependencies: makeDependencies { _ in "" }
        )
        XCTAssertEqual(state, -1)
        XCTAssertEqual(collector.lines.last?.state, -1)
    }

    // MARK: - The raw HTML of the four steps

    /// Upstream `Debug.log(sourceUrl, body, state = 10/20/30/40)` — the
    /// debugger hands the raw HTML of every page to the log with the state of
    /// the step, so that the native debug screen can show it in the
    /// "原始HTML" dialogs.
    func testTheRawHtmlOfEveryStepIsLoggedWithItsState() async {
        let body: @Sendable (HttpRequest) -> String = { request in
            if request.url.contains("/search") {
                return """
                <div class="item"><a class="name" href="/book/1">测试书</a><span class="author">作者</span></div>
                """
            }
            if request.url.contains("/toc") {
                return """
                <div class="chapter"><a class="title" href="/book/1/1">第一章</a></div>
                """
            }
            if request.url.contains("/1/1") {
                return "<div class=\"content\">正文页</div>"
            }
            if request.url.contains("/book/1") {
                return """
                <div class="name">详情页</div><a class="toc" href="/book/1/toc">目录</a>
                """
            }
            return "<div class=\"content\">正文页</div>"
        }
        let collector = Collector()
        let debugger = SourceDebugger(sink: collector)
        _ = await debugger.debugBookSource(
            makeSource(),
            key: "关键字",
            dependencies: makeDependencies(body)
        )
        func html(state: Int) -> String? {
            collector.lines.first(where: { $0.state == state })?.message
        }
        XCTAssertTrue(html(state: 10)?.contains("<div class=\"item\">") == true)
        XCTAssertTrue(html(state: 20)?.contains("详情页") == true)
        XCTAssertTrue(html(state: 30)?.contains("<div class=\"chapter\">") == true)
        XCTAssertTrue(html(state: 40)?.contains("正文页") == true)
    }

    /// The upstream's `BookSourceDebugModel` intercepts the four raw HTML
    /// states — they never reach the log list.
    func testTheRawHtmlStatesAreNotPrinted() {
        XCTAssertEqual(debugNotPrintedStates, [10, 20, 30, 40])
    }
}
