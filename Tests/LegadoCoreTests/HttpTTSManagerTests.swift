//
//  HttpTTSManagerTests.swift
//  LegadoCoreTests
//
//  The management of the HTTP text-to-speech engines.
//
//  Upstream source of truth:
//  app/src/main/java/io/legado/app/data/entities/HttpTTS.kt:46-80
//  app/src/main/java/io/legado/app/ui/book/read/config/SpeakEngineDialog.kt
//  app/src/main/java/io/legado/app/data/entities/BaseSource.kt:138-181
//

import XCTest
@testable import LegadoCore

final class HttpTTSManagerTests: XCTestCase {

    // MARK: - The key

    func testTheKeyOfAnEngine() {
        // Upstream `HttpTTS.getKey()`.
        XCTAssertEqual(HttpTTSManager.key(for: 12), "httpTts:12")
    }

    // MARK: - The import

    func testASingleEngineIsImported() throws {
        let json = """
        {"id":5,"name":"测试","url":"http://tts.local/{{speakText}}","contentType":"audio/.*"}
        """
        let engines = try HttpTTSManager.parse(json)
        XCTAssertEqual(engines.count, 1)
        XCTAssertEqual(engines[0].id, 5)
        XCTAssertEqual(engines[0].name, "测试")
        XCTAssertEqual(engines[0].url, "http://tts.local/{{speakText}}")
        XCTAssertEqual(engines[0].contentType, "audio/.*")
    }

    func testAnArrayOfEnginesIsImported() throws {
        let json = """
        [{"id":1,"name":"一","url":"http://a"},{"id":2,"name":"二","url":"http://b"}]
        """
        let engines = try HttpTTSManager.parse(json)
        XCTAssertEqual(engines.count, 2)
        XCTAssertEqual(engines.map(\.name), ["一", "二"])
    }

    func testBrokenJsonIsRejected() {
        XCTAssertThrowsError(try HttpTTSManager.parse("not json")) { error in
            XCTAssertEqual(error as? HttpTTSImportError, .invalidJSON)
        }
    }

    func testAnEngineWithoutANameIsRejected() {
        XCTAssertThrowsError(try HttpTTSManager.parse("{\"url\":\"http://a\"}")) { error in
            XCTAssertEqual(error as? HttpTTSImportError, .missingName)
        }
    }

    func testAnEngineWithoutAnAddressIsRejected() {
        XCTAssertThrowsError(try HttpTTSManager.parse("{\"name\":\"a\"}")) { error in
            XCTAssertEqual(error as? HttpTTSImportError, .missingURL)
        }
    }

    /// Upstream `HttpTTS.fromJsonDoc`: a list is stored as a JSON text.
    func testTheLoginUiListIsStoredAsJson() throws {
        let json = """
        {"name":"a","url":"http://a","loginUi":[{"title":"账号","hint":"请输入","type":"editText"}]}
        """
        let engines = try HttpTTSManager.parse(json)
        let loginUi = try XCTUnwrap(engines[0].loginUi)
        XCTAssertTrue(loginUi.contains("请输入"))
        // The stored value is a JSON array, not the plain title.
        let value = try JSONValue.parse(loginUi)
        guard case .array(let rows) = value else {
            return XCTFail("the login UI is not an array")
        }
        XCTAssertEqual(rows.count, 1)
    }

    // MARK: - The export

    func testTheExportIsReadBack() throws {
        let engine = HttpTTS(
            id: 3,
            name: "导出",
            url: "http://tts.local",
            contentType: "audio/mpeg",
            concurrentRate: "2",
            loginUrl: "http://login",
            header: "{\"token\":\"abc\"}"
        )
        let json = HttpTTSManager.exportJSON([engine])
        let parsed = try HttpTTSManager.parse(json)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].id, 3)
        XCTAssertEqual(parsed[0].name, "导出")
        XCTAssertEqual(parsed[0].contentType, "audio/mpeg")
        XCTAssertEqual(parsed[0].concurrentRate, "2")
        XCTAssertEqual(parsed[0].loginUrl, "http://login")
        XCTAssertEqual(parsed[0].header, "{\"token\":\"abc\"}")
    }

    // MARK: - The headers

    func testTheHeaderMapIsParsed() {
        var engine = HttpTTS(id: 1, name: "a", url: "http://a")
        engine.header = "{\"token\":\"abc\",\"X-Test\":\"1\"}"
        let map = engine.headerMap()
        XCTAssertEqual(map["token"], "abc")
        XCTAssertEqual(map["X-Test"], "1")
    }

    func testTheLoginHeaderIsMerged() {
        var engine = HttpTTS(id: 1, name: "a", url: "http://a")
        engine.header = "{\"token\":\"abc\"}"
        let map = engine.headerMap(
            hasLoginHeader: true,
            loginHeaderMap: ["Cookie": "session=1"]
        )
        XCTAssertEqual(map["token"], "abc")
        XCTAssertEqual(map["Cookie"], "session=1")
    }

    // MARK: - The login

    func testAnEngineWithALoginUrlNeedsTheLogin() throws {
        let store = try makeStore()
        let service = SourceLoginService(store: store, cookieStore: CookieStore())
        var engine = HttpTTS(id: 1, name: "a", url: "http://a")
        engine.loginUrl = "http://login"
        XCTAssertTrue(HttpTTSManager.needsLogin(engine, loginService: service))
        try service.putLoginInfo(["user": "me"], for: HttpTTSManager.key(for: 1))
        XCTAssertFalse(HttpTTSManager.needsLogin(engine, loginService: service))
    }

    func testAnEngineWithoutALoginUrlNeverNeedsTheLogin() throws {
        let store = try makeStore()
        let service = SourceLoginService(store: store, cookieStore: CookieStore())
        let engine = HttpTTS(id: 1, name: "a", url: "http://a")
        XCTAssertFalse(HttpTTSManager.needsLogin(engine, loginService: service))
    }

    // MARK: - The store

    func testTheEngineIsDeleted() throws {
        let store = try makeStore()
        let engine = HttpTTS(id: 7, name: "a", url: "http://a")
        try store.insert(engine)
        XCTAssertEqual(try store.allHttpTTS().count, 1)
        try store.deleteHttpTTS(engine)
        XCTAssertEqual(try store.allHttpTTS().count, 0)
    }

    func testTheEngineIsReadBack() throws {
        let store = try makeStore()
        try store.insert(HttpTTS(id: 7, name: "a", url: "http://a"))
        let engine = try XCTUnwrap(store.httpTTS(id: 7))
        XCTAssertEqual(engine.name, "a")
        XCTAssertNil(try store.httpTTS(id: 8))
    }

    // MARK: - The helper

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        return store
    }
}
