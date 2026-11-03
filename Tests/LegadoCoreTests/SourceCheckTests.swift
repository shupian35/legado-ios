//
//  SourceCheckTests.swift
//  LegadoCoreTests
//
//  Tests for the source verification (校验) — the port of
//  `io.legado.app.service.CheckSourceService`.
//

import XCTest
@testable import LegadoCore

final class SourceCheckTests: XCTestCase {

    // MARK: - Fixtures

    /// A stub transport that answers from a table of URL fragments.
    private final class StubClient: HttpClient, @unchecked Sendable {
        private let answers: [(match: String, body: String, code: Int)]
        private(set) var requested: [String] = []

        init(_ answers: [(match: String, body: String, code: Int)]) {
            self.answers = answers
        }

        func send(_ request: HttpRequest) async throws -> HttpResponse {
            requested.append(request.url)
            for answer in answers where request.url.contains(answer.match) {
                if answer.code != 200 {
                    throw HttpError.status(code: answer.code, message: "HTTP \(answer.code)")
                }
                return HttpResponse(url: request.url, body: answer.body, code: 200, message: "OK")
            }
            return HttpResponse(url: request.url, body: "", code: 200, message: "OK")
        }
    }

    private let searchHTML = """
    <div class="book">
      <h3><a href="/book/1">测试书</a></h3>
      <span class="author">作者</span>
    </div>
    """

    private let infoHTML = """
    <h1>测试书</h1>
    <span class="author">作者</span>
    <p class="intro">简介</p>
    <a class="toc" href="/book/1/toc">目录</a>
    """

    private let tocHTML = """
    <div class="chapter"><a href="/book/1/1">第一章</a></div>
    <div class="chapter"><a href="/book/1/2">第二章</a></div>
    """

    private let contentHTML = "<div class=\"content\">正文内容</div>"

    private func makeSource(
        searchUrl: String? = "https://example.com/search?q={{key}}",
        exploreUrl: String? = nil,
        ruleSearch: String? = #"{"bookList":"div.book","name":"h3 a@text","author":"span.author@text","bookUrl":"h3 a@href"}"#,
        ruleBookInfo: String? = #"{"name":"h1@text","author":"span.author@text","intro":"p.intro@text","tocUrl":"a.toc@href"}"#,
        ruleToc: String? = #"{"chapterList":"div.chapter","chapterName":"a@text","chapterUrl":"a@href"}"#,
        ruleContent: String? = #"{"content":"div.content@html"}"#
    ) -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.com",
            bookSourceName: "Test",
            exploreUrl: exploreUrl,
            searchUrl: searchUrl,
            ruleSearch: ruleSearch,
            ruleBookInfo: ruleBookInfo,
            ruleToc: ruleToc,
            ruleContent: ruleContent
        )
    }

    private func dependencies(_ client: HttpClient) -> AnalyzeUrlDependencies {
        AnalyzeUrlDependencies(httpClient: client)
    }

    /// A stub that answers the whole chain: the search page, the detail page,
    /// the chapter list and the chapter content.
    private func fullStub() -> StubClient {
        StubClient([
            ("/book/1/1", contentHTML, 200),
            ("/book/1/toc", tocHTML, 200),
            ("/book/1", infoHTML, 200),
            ("search", searchHTML, 200)
        ])
    }

    // MARK: - The keyword

    func testTheKeywordComesFromTheSearchRule() {
        let source = makeSource(
            ruleSearch: #"{"checkKeyWord":"斗破","bookList":"div.book"}"#
        )
        XCTAssertEqual(SourceChecker.checkKeyword(source), "斗破")
        XCTAssertEqual(SourceChecker.checkKeyword(makeSource()), "我的")
    }

    func testTheExploreCategoriesAreParsed() {
        // The upstream reads the `exploreUrl` field: either a JSON array of
        // `ExploreKind` objects or a list of "分类::网址" pairs.
        let plain = makeSource(exploreUrl: "玄幻::https://example.com/xuanhuan&&都市::https://example.com/dushi")
        let categories = SourceChecker.exploreCategories(plain)
        XCTAssertEqual(categories.map { $0.name }, ["玄幻", "都市"])
        XCTAssertEqual(categories.map { $0.url }, ["https://example.com/xuanhuan", "https://example.com/dushi"])

        let json = makeSource(exploreUrl: #"[{"title":"玄幻","url":"https://example.com/xuanhuan"}]"#)
        XCTAssertEqual(SourceChecker.exploreCategories(json).map { $0.name }, ["玄幻"])
    }

    func testTheExploreCategoriesAreSplitOnTheLines() {
        let source = makeSource(exploreUrl: "玄幻::https://example.com/x\n都市::https://example.com/d")
        XCTAssertEqual(SourceChecker.exploreCategories(source).map { $0.name }, ["玄幻", "都市"])
    }

    // MARK: - The failures

    func testTheEmptySearchUrlIsOnlyAMarker() async {
        // The upstream adds the group "搜索链接规则为空", but that group is
        // NOT an invalid group (it does not contain "失效"), so the check
        // itself still succeeds.
        let source = makeSource(searchUrl: nil)
        let result = await SourceChecker.check(
            source: source,
            options: SourceCheckOptions(checkDiscovery: false),
            dependencies: dependencies(StubClient([]))
        )
        XCTAssertTrue(result.isSuccess, result.message)
        XCTAssertEqual(result.message, "校验成功")
        XCTAssertTrue(result.source.hasGroup(SourceChecker.Group.emptySearchUrl))
        XCTAssertTrue(result.invalidGroups.isEmpty)
    }

    func testTheSearchFailureIsReported() async {
        let client = StubClient([("search", "<html><body>没有结果</body></html>", 200)])
        let result = await SourceChecker.check(
            source: makeSource(),
            options: SourceCheckOptions(checkDiscovery: false),
            dependencies: dependencies(client)
        )
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(result.invalidGroups.contains(SourceChecker.Group.searchFailed))
        XCTAssertEqual(result.message, "校验失败:\(SourceChecker.Group.searchFailed)")
    }

    func testTheEmptyExploreRuleIsOnlyAMarker() async {
        let client = fullStub()
        let result = await SourceChecker.check(
            source: makeSource(exploreUrl: "&&"),
            options: SourceCheckOptions(),
            dependencies: dependencies(client)
        )
        XCTAssertTrue(result.source.hasGroup(SourceChecker.Group.emptyExploreUrl))
    }

    func testTheErrorCommentIsAddedAndRemoved() async {
        let client = StubClient([("search", "<html>没有结果</html>", 200)])
        let result = await SourceChecker.check(
            source: makeSource(),
            options: SourceCheckOptions(checkDiscovery: false),
            dependencies: dependencies(client)
        )
        let comment = result.source.bookSourceComment ?? ""
        XCTAssertTrue(comment.hasPrefix("// Error: "))
        var cleaned = result.source
        cleaned.removeErrorComment()
        XCTAssertFalse((cleaned.bookSourceComment ?? "").hasPrefix("// Error: "))
    }

    func testTheContentFailureIsReported() async {
        let client = StubClient([
            ("/book/1/toc", tocHTML, 200),
            ("/book/1", infoHTML, 200),
            ("search", searchHTML, 200)
        ])
        let result = await SourceChecker.check(
            source: makeSource(),
            options: SourceCheckOptions(checkDiscovery: false),
            dependencies: dependencies(client)
        )
        XCTAssertFalse(result.isSuccess)
        XCTAssertTrue(
            result.invalidGroups.contains(SourceChecker.Group.contentFailed("搜索")),
            result.invalidGroups.joined(separator: ",")
        )
    }

    // MARK: - The success

    func testASuccessfulSourceIsReported() async {
        let client = StubClient([
            ("/book/1/1", contentHTML, 200),
            ("/book/1/toc", tocHTML, 200),
            ("/book/1", infoHTML, 200),
            ("search", searchHTML, 200)
        ])
        let result = await SourceChecker.check(
            source: makeSource(),
            options: SourceCheckOptions(checkDiscovery: false),
            dependencies: dependencies(client)
        )
        XCTAssertTrue(result.isSuccess, result.message)
        print("REQUESTS: \(client.requested)")
        XCTAssertEqual(result.message, "校验成功")
        XCTAssertTrue(result.invalidGroups.isEmpty)
        XCTAssertGreaterThanOrEqual(result.respondTime, 0)
    }

    func testTheCheckedSourceKeepsItsIdentity() async {
        let client = StubClient([
            ("/book/1/1", contentHTML, 200),
            ("/book/1/toc", tocHTML, 200),
            ("/book/1", infoHTML, 200),
            ("search", searchHTML, 200)
        ])
        let result = await SourceChecker.check(
            source: makeSource(),
            options: SourceCheckOptions(checkDiscovery: false),
            dependencies: dependencies(client)
        )
        XCTAssertEqual(result.sourceUrl, "https://example.com")
        XCTAssertEqual(result.source.bookSourceName, "Test")
    }

    func testTheSearchPageIsRequestedWithTheKeyword() async {
        let client = StubClient([("search", searchHTML, 200)])
        _ = await SourceChecker.check(
            source: makeSource(),
            options: SourceCheckOptions(
                checkDiscovery: false,
                checkInfo: false,
                checkCategory: false,
                checkContent: false
            ),
            dependencies: dependencies(client)
        )
        XCTAssertTrue(client.requested.contains { $0.contains("search") })
    }
}
