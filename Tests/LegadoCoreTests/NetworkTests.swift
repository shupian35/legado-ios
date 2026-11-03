import XCTest
@testable import LegadoCore

final class NetworkUtilsTests: XCTestCase {

    func testAbsoluteURLKeepsAbsoluteUrls() {
        XCTAssertEqual(
            NetworkUtils.absoluteURL(base: "http://host/dir/", "http://other/x.html"),
            "http://other/x.html"
        )
    }

    func testAbsoluteURLResolvesRelativeToTheBaseDirectory() {
        XCTAssertEqual(
            NetworkUtils.absoluteURL(base: "http://host/dir/page.html", "a.html"),
            "http://host/dir/a.html"
        )
    }

    func testAbsoluteURLFoldsDotSegments() {
        XCTAssertEqual(
            NetworkUtils.absoluteURL(base: "http://host/dir/page.html", "../a.html"),
            "http://host/a.html"
        )
    }

    func testAbsoluteURLDropsJavascript() {
        XCTAssertEqual(NetworkUtils.absoluteURL(base: "http://host/", "javascript:void(0)"), "")
    }

    func testAbsoluteURLKeepsDataUrls() {
        XCTAssertEqual(
            NetworkUtils.absoluteURL(base: "http://host/", "data:text/plain,hi"),
            "data:text/plain,hi"
        )
    }

    func testAbsoluteURLWithoutBase() {
        XCTAssertEqual(NetworkUtils.absoluteURL(base: nil, " /a.html "), "/a.html")
    }

    func testBaseUrl() {
        XCTAssertEqual(NetworkUtils.baseUrl("http://host/dir/a.html"), "http://host")
        XCTAssertEqual(NetworkUtils.baseUrl("https://host"), "https://host")
        XCTAssertNil(NetworkUtils.baseUrl("ftp://host/a"))
        XCTAssertNil(NetworkUtils.baseUrl(nil))
    }

    func testSubDomain() {
        XCTAssertEqual(NetworkUtils.subDomain("https://www.example.com/a"), "example.com")
        XCTAssertEqual(NetworkUtils.subDomain("http://www.biquge.com.cn/a"), "biquge.com.cn")
        XCTAssertEqual(NetworkUtils.subDomain("http://1.2.3.4/a"), "1.2.3.4")
    }

    func testEncodedQuery() {
        XCTAssertTrue(NetworkUtils.encodedQuery("abc=123&x=y"))
        XCTAssertTrue(NetworkUtils.encodedQuery("a%20b"))
        XCTAssertFalse(NetworkUtils.encodedQuery("a b"))
    }

    func testEncodedForm() {
        XCTAssertTrue(NetworkUtils.encodedForm("a*b-c._d"))
        XCTAssertFalse(NetworkUtils.encodedForm("a b"))
    }
}

final class CookieStoreTests: XCTestCase {

    func testSetAndGetCookie() {
        let store = CookieStore()
        store.setCookie(url: "http://www.example.com/a", cookie: "a=1; b=2")
        XCTAssertEqual(store.cookie(url: "http://www.example.com/b"), "a=1; b=2")
    }

    func testReplaceCookieMerges() {
        let store = CookieStore()
        store.setCookie(url: "http://www.example.com/a", cookie: "a=1")
        store.replaceCookie(url: "http://www.example.com/a", cookie: "b=2")
        XCTAssertEqual(store.cookie(url: "http://www.example.com/a"), "a=1; b=2")
    }

    func testCookieToMapIgnoresBlankValues() {
        let store = CookieStore()
        let map = store.cookieToMap("a=1; b=; c=null; d")
        XCTAssertEqual(map["a"], "1")
        XCTAssertNil(map["b"])
        XCTAssertEqual(map["c"], "null")
        XCTAssertNil(map["d"])
    }

    func testMapToCookie() {
        let store = CookieStore()
        var map = CookieMap()
        map["a"] = "1"
        map["b"] = "2"
        XCTAssertEqual(store.mapToCookie(map), "a=1; b=2")
        XCTAssertNil(store.mapToCookie(CookieMap()))
    }

    func testSessionCookieIsMerged() {
        let store = CookieStore()
        store.setCookie(url: "http://www.example.com/a", cookie: "a=1")
        store.setSessionCookie(domain: "example.com", key: "s", value: "9")
        XCTAssertEqual(store.cookie(url: "http://www.example.com/a"), "a=1; s=9")
    }
}

final class ConcurrentRateLimiterTests: XCTestCase {

    func testNoRateAllowsEverything() throws {
        let limiter = ConcurrentRateLimiter(key: nil, concurrentRate: nil)
        XCTAssertNil(try limiter.fetchStart())
    }

    func testZeroRateAllowsEverything() throws {
        let limiter = ConcurrentRateLimiter(key: "src-zero", concurrentRate: "0")
        XCTAssertNil(try limiter.fetchStart())
    }

    func testFirstAccessIsAllowed() throws {
        let limiter = ConcurrentRateLimiter(key: "src-first", concurrentRate: "1000")
        XCTAssertNotNil(try limiter.fetchStart())
    }

    func testSecondAccessInsideTheWindowWaits() throws {
        let limiter = ConcurrentRateLimiter(key: "src-window", concurrentRate: "1000")
        _ = try limiter.fetchStart()
        XCTAssertThrowsError(try limiter.fetchStart()) { error in
            guard let error = error as? ConcurrentError else {
                return XCTFail("expected a ConcurrentError, got \(error)")
            }
            XCTAssertGreaterThan(error.waitTime, 0)
            XCTAssertTrue(error.message.contains("并发率"))
        }
    }

    func testCountPerWindowAllowsUpToTheCount() throws {
        // Upstream `ConcurrentRateLimiter.fetchStart` increments `frequency`
        // while `frequency <= count`, so "2/60000" lets three requests through
        // before the fourth one has to wait.
        let limiter = ConcurrentRateLimiter(key: "src-count", concurrentRate: "2/60000")
        XCTAssertNotNil(try limiter.fetchStart())
        XCTAssertNotNil(try limiter.fetchStart())
        XCTAssertNotNil(try limiter.fetchStart())
        XCTAssertThrowsError(try limiter.fetchStart())
    }
}

/// A script engine that returns a canned result.
final class CannedScriptEngine: RuleScriptEngine {
    var result: RuleValue
    private(set) var lastScript: String?
    private(set) var lastBindings: [String: RuleValue] = [:]

    init(result: RuleValue) {
        self.result = result
    }

    func evaluate(_ script: String, bindings: [String: RuleValue]) throws -> RuleValue {
        lastScript = script
        lastBindings = bindings
        return result
    }
}

final class AnalyzeUrlTests: XCTestCase {

    private func makeSource(concurrentRate: String? = nil) -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.com",
            bookSourceName: "example",
            concurrentRate: concurrentRate
        )
    }

    func testPlainUrlIsResolvedAgainstTheBase() {
        let analyze = AnalyzeUrl(url: "a.html", baseUrl: "https://example.com/dir/")
        XCTAssertEqual(analyze.url, "https://example.com/dir/a.html")
    }

    func testOptionBlockIsParsed() {
        let analyze = AnalyzeUrl(
            url: "https://example.com/a,{\"method\":\"POST\",\"body\":\"x=1\"}"
        )
        XCTAssertEqual(analyze.url, "https://example.com/a")
        XCTAssertTrue(analyze.isPost)
    }

    func testPagePlaceholderSelectsThePage() {
        let analyze = AnalyzeUrl(url: "https://example.com/<1,2,3>", page: 2)
        XCTAssertEqual(analyze.url, "https://example.com/2")
    }

    func testPagePlaceholderUsesTheLastEntryOutOfRange() {
        let analyze = AnalyzeUrl(url: "https://example.com/<1,2,3>", page: 9)
        XCTAssertEqual(analyze.url, "https://example.com/3")
    }

    func testScriptBlockIsEvaluated() {
        let engine = CannedScriptEngine(result: .text("https://example.com/from-js"))
        let analyze = AnalyzeUrl(
            url: "<js>return 'x'</js>",
            dependencies: AnalyzeUrlDependencies(scriptEngine: engine)
        )
        XCTAssertEqual(analyze.ruleUrl, "https://example.com/from-js")
    }

    func testHeaderMapIsTakenFromTheSource() {
        var source = makeSource()
        source.header = "{\"X-Test\":\"1\"}"
        let analyze = AnalyzeUrl(url: "https://example.com/", source: source)
        XCTAssertEqual(analyze.headerMap["X-Test"], "1")
        XCTAssertNotNil(analyze.headerMap["User-Agent"])
    }

    func testProxyHeaderIsExtracted() {
        var source = makeSource()
        source.header = "{\"proxy\":\"http://127.0.0.1:1080\"}"
        let analyze = AnalyzeUrl(url: "https://example.com/", source: source)
        XCTAssertNil(analyze.headerMap["proxy"])
    }

    func testBaseUrlIsTrimmedToTheSchemeAndHost() {
        let analyze = AnalyzeUrl(url: "https://example.com/dir/a.html")
        XCTAssertEqual(analyze.domain, "example.com")
    }
}
