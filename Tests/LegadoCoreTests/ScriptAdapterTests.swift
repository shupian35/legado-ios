//
//  ScriptAdapterTests.swift
//  LegadoCoreTests
//
//  The capabilities the rule scripts run with — the network, the file
//  sandbox, the cookies, the cache and the source data.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/help/JsExtensions.kt
//

import XCTest
@testable import LegadoCore

final class ScriptAdapterTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("script-sandbox-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    // MARK: - The file sandbox

    func testTheSandboxResolvesARelativePathInsideTheDirectory() throws {
        let sandbox = SandboxFileSandbox(baseDirectory: directory.path)
        let resolved = try sandbox.resolvedPath("data.txt")
        XCTAssertTrue(resolved.hasPrefix(directory.standardizedFileURL.path))
        XCTAssertTrue(resolved.hasSuffix("data.txt"))
    }

    func testTheSandboxRejectsAPathThatEscapesTheDirectory() {
        let sandbox = SandboxFileSandbox(baseDirectory: directory.path)
        XCTAssertThrowsError(try sandbox.resolvedPath("../secret.txt")) { error in
            guard case ScriptEngineError.fileAccessDenied(_) = error else {
                return XCTFail("expected a fileAccessDenied error, got \(error)")
            }
        }
    }

    func testTheSandboxRejectsAnAbsolutePathOutsideTheDirectory() {
        let sandbox = SandboxFileSandbox(baseDirectory: directory.path)
        XCTAssertThrowsError(try sandbox.resolvedPath("/etc/passwd"))
    }

    func testTheSandboxWritesReadsAndListsFiles() throws {
        let sandbox = SandboxFileSandbox(baseDirectory: directory.path)
        try sandbox.writeScriptFile("note.txt", content: "你好")
        XCTAssertTrue(sandbox.scriptFileExists("note.txt"))
        XCTAssertEqual(try sandbox.readScriptFile("note.txt"), "你好")
        XCTAssertEqual(try sandbox.listScriptDirectory(""), ["note.txt"])
        try sandbox.deleteScriptFile("note.txt")
        XCTAssertFalse(sandbox.scriptFileExists("note.txt"))
    }

    func testTheSandboxRefusesToReadOutsideTheDirectory() {
        let sandbox = SandboxFileSandbox(baseDirectory: directory.path)
        XCTAssertThrowsError(try sandbox.readScriptFile("../secret.txt"))
    }

    // MARK: - The cookies

    func testTheCookieStoreReachesTheJar() throws {
        let jar = CookieStore()
        let adapter = CookieScriptStore(cookieStore: jar)
        adapter.setCookie("token=1", for: "https://example.com")
        XCTAssertEqual(adapter.cookie(for: "https://example.com"), "token=1")
    }

    func testTheCookieStoreReportsNoCookieWhenTheJarIsEmpty() {
        let adapter = CookieScriptStore(cookieStore: CookieStore())
        XCTAssertNil(adapter.cookie(for: "https://example.com"))
    }

    // MARK: - The cache

    func testTheCacheStoresAndReadsTheValues() {
        let cache = MemoryScriptCache()
        cache.setCacheValue("value", for: "key")
        XCTAssertEqual(cache.cacheValue(for: "key"), "value")
        XCTAssertNil(cache.cacheValue(for: "other"))
    }

    // MARK: - The network

    func testTheScriptClientSendsTheUserAgentAndTheCookies() throws {
        let jar = CookieStore()
        jar.replaceCookie(url: "https://example.com", cookie: "token=1")
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: "ok")
        }
        let client = HttpScriptClient(
            httpClient: stub,
            cookieStore: jar,
            userAgent: "Legado/1.0"
        )
        let body = try client.scriptGet("https://example.com", headers: [:])
        XCTAssertEqual(body, "ok")
        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.headers["User-Agent"], "Legado/1.0")
        XCTAssertEqual(request.headers["Cookie"], "token=1")
        XCTAssertEqual(request.method, "GET")
    }

    func testTheScriptClientSendsTheBodyOfAPost() throws {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: request.body.flatMap { String(data: $0, encoding: .utf8) } ?? "")
        }
        let client = HttpScriptClient(httpClient: stub)
        let body = try client.scriptPost("https://example.com", body: "name=阅读", headers: ["X-Test": "1"])
        XCTAssertEqual(body, "name=阅读")
        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["X-Test"], "1")
    }

    func testTheScriptClientReportsAFailedRequest() {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: "denied", code: 403)
        }
        let client = HttpScriptClient(httpClient: stub)
        XCTAssertThrowsError(try client.scriptGet("https://example.com", headers: [:])) { error in
            guard case HttpError.status(let code, _) = error else {
                return XCTFail("expected a status error, got \(error)")
            }
            XCTAssertEqual(code, 403)
        }
    }

    // MARK: - The source data

    func testTheSourceBridgeReadsAndWritesTheVariables() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        let login = SourceLoginService(store: store, cookieStore: CookieStore())
        let source = BookSource(
            bookSourceUrl: "https://example.com",
            bookSourceName: "测试书源",
            bookSourceGroup: "",
            bookSourceType: 0,
            enabled: true
        )
        let box = source.variableBox
        let bridge = SourceScriptBridge(variables: box, login: login, key: source.key)
        XCTAssertEqual(bridge.put("token", value: "abc"), "abc")
        XCTAssertEqual(bridge.get("token"), "abc")
        // The variables are written through to the source store.
        XCTAssertTrue(
            BookSourceVariables.sourceVariables(source.key)?.contains("token") == true
        )
    }

    func testTheSourceBridgeStoresTheLoginHeader() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        let login = SourceLoginService(store: store, cookieStore: CookieStore())
        let bridge = SourceScriptBridge(variables: nil, login: login, key: "source-1")
        bridge.putLoginHeader("{\"Cookie\":\"token=1\"}")
        XCTAssertEqual(bridge.getLoginHeader(), "{\"Cookie\":\"token=1\"}")
        bridge.removeLoginHeader()
        XCTAssertEqual(bridge.getLoginHeader(), "")
    }

    func testTheSourceBridgeStoresTheLoginInfo() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        let login = SourceLoginService(store: store, cookieStore: CookieStore())
        let bridge = SourceScriptBridge(variables: nil, login: login, key: "source-2")
        XCTAssertTrue(bridge.putLoginInfo("{\"user\":\"阅读\"}"))
        XCTAssertTrue(bridge.getLoginInfo().contains("阅读"))
        bridge.removeLoginInfo()
        XCTAssertEqual(bridge.getLoginInfo(), "")
    }

    func testTheSourceBridgeReplacesTheVariables() {
        let box = RuleDataBox(variables: ["a": "1"], sourceKey: "k")
        let bridge = SourceScriptBridge(variables: box, login: nil, key: "k")
        bridge.setVariable("{\"b\":\"2\"}")
        XCTAssertEqual(bridge.getVariable(), "{\"b\":\"2\"}")
        XCTAssertEqual(box.getVariable("b"), "2")
    }

    // MARK: - The rule data box

    func testTheRuleDataBoxCarriesTheSourceKey() {
        let box = RuleDataBox(json: "{\"a\":\"1\"}", sourceKey: "the-key")
        XCTAssertEqual(box.sourceKey, "the-key")
        XCTAssertEqual(box.getVariable("a"), "1")
    }

    func testTheSourceVariableBoxCarriesTheKey() {
        let source = BookSource(
            bookSourceUrl: "https://example.com",
            bookSourceName: "测试书源",
            bookSourceGroup: "",
            bookSourceType: 0,
            enabled: true
        )
        XCTAssertEqual(source.variableBox.sourceKey, source.key)
    }
}
