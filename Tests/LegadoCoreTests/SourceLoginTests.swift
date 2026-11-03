//
//  SourceLoginTests.swift
//  LegadoCoreTests
//
//  The login of a book source — upstream `data/entities/BaseSource.kt` and
//  `ui/login/SourceLoginDialog.kt`.
//

import XCTest
@testable import LegadoCore

final class SourceLoginTests: XCTestCase {

    private var store: LegadoStore!
    private var cookieStore: CookieStore!
    private var service: SourceLoginService!

    override func setUp() {
        super.setUp()
        store = LegadoStore(tables: MemoryTableStore())
        try? store.createSchema()
        cookieStore = CookieStore()
        service = SourceLoginService(store: store, cookieStore: cookieStore, scriptEngine: nil)
    }

    override func tearDown() {
        store = nil
        cookieStore = nil
        service = nil
        super.tearDown()
    }

    private func makeSource(
        url: String = "https://example.com",
        name: String = "测试书源",
        loginUrl: String? = nil,
        loginUi: String? = nil
    ) -> BookSource {
        BookSource(
            bookSourceUrl: url,
            bookSourceName: name,
            bookSourceGroup: "",
            bookSourceType: 0,
            enabled: true,
            loginUrl: loginUrl,
            loginUi: loginUi
        )
    }

    // MARK: - The login UI

    func testTheLoginUiIsParsedFromTheJsonArray() throws {
        let ui = """
        [
          {"name": "账号", "type": "text"},
          {"name": "密码", "type": "password"},
          {"name": "登录", "type": "button", "action": "https://example.com/login"}
        ]
        """
        let rows = try SourceLoginService.parseLoginUi(ui)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].name, "账号")
        XCTAssertEqual(rows[0].type, RowUi.Kind.text)
        XCTAssertEqual(rows[1].type, RowUi.Kind.password)
        XCTAssertEqual(rows[2].type, RowUi.Kind.button)
        XCTAssertEqual(rows[2].action, "https://example.com/login")
    }

    func testASingleLoginUiObjectIsAccepted() throws {
        let rows = try SourceLoginService.parseLoginUi("{\"name\": \"账号\", \"type\": \"text\"}")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "账号")
    }

    func testAnEmptyLoginUiIsEmpty() throws {
        XCTAssertTrue(try SourceLoginService.parseLoginUi("").isEmpty)
        XCTAssertTrue(try SourceLoginService.parseLoginUi(nil).isEmpty)
    }

    func testABrokenLoginUiYieldsNoRows() {
        // Upstream `GSON.fromJsonArray` returns null for a broken JSON and the
        // dialog shows an empty form, so the port stays lenient.
        XCTAssertTrue(SourceLoginService.parseLoginUi("{not json}").isEmpty)
    }

    func testTheLoginUiOfASourceIsRead() {
        let source = makeSource(loginUi: "[{\"name\": \"账号\", \"type\": \"text\"}]")
        XCTAssertEqual(service.loginUi(for: source).count, 1)
    }

    // MARK: - The login script

    func testTheLoginScriptStripsTheMarkers() {
        XCTAssertEqual(SourceLoginService.loginScript(from: "@js:java.putLoginHeader('{}')"), "java.putLoginHeader('{}')")
        XCTAssertEqual(SourceLoginService.loginScript(from: "<js>java.putLoginHeader('{}')</js>"), "java.putLoginHeader('{}')")
        XCTAssertEqual(SourceLoginService.loginScript(from: "java.putLoginHeader('{}')"), "java.putLoginHeader('{}')")
    }

    // MARK: - The login information

    func testTheLoginInfoIsStoredAndRead() throws {
        let source = makeSource()
        try service.putLoginInfo(["user": "me", "pass": "secret"], for: source.key)
        let info = try service.loginInfo(for: source.key)
        XCTAssertEqual(info?["user"], "me")
        XCTAssertEqual(info?["pass"], "secret")
    }

    func testTheLoginInfoCanBeRemoved() throws {
        let source = makeSource()
        try service.putLoginInfo(["user": "me"], for: source.key)
        try service.removeLoginInfo(for: source.key)
        XCTAssertNil(try service.loginInfo(for: source.key))
    }

    func testAnEmptyLoginInfoIsStoredAsAnEmptyMap() throws {
        let source = makeSource()
        try service.putLoginInfo(["user": "me"], for: source.key)
        try service.putLoginInfo([String: String](), for: source.key)
        let info = try service.loginInfo(for: source.key)
        XCTAssertEqual(info?.isEmpty, true)
    }

    // MARK: - The login header

    func testTheLoginHeaderIsStoredAndRead() throws {
        let source = makeSource()
        try service.putLoginHeader("{\"token\": \"abc\"}", for: source.key)
        let header = try service.loginHeaderMap(for: source.key)
        XCTAssertEqual(header?["token"], "abc")
    }

    func testTheLoginHeaderCanBeRemoved() throws {
        let source = makeSource()
        try service.putLoginHeader("{\"token\": \"abc\"}", for: source.key)
        try service.removeLoginHeader(for: source.key)
        XCTAssertNil(try service.loginHeader(for: source.key))
    }

    // MARK: - The button actions

    func testAnAbsoluteUrlIsAnOpenAction() {
        let row = RowUi(name: "登录", type: RowUi.Kind.button, action: "https://example.com/login")
        guard case .openURL(let url)? = SourceLoginService.buttonAction(row) else {
            return XCTFail("expected an open action")
        }
        XCTAssertEqual(url, "https://example.com/login")
    }

    func testAScriptIsAScriptAction() {
        let row = RowUi(name: "登录", type: RowUi.Kind.button, action: "java.putLoginHeader('{}')")
        guard case .script(let script)? = SourceLoginService.buttonAction(row) else {
            return XCTFail("expected a script action")
        }
        XCTAssertEqual(script, "java.putLoginHeader('{}')")
    }

    func testAnEmptyActionIsNothing() {
        XCTAssertNil(SourceLoginService.buttonAction(RowUi(name: "登录", type: RowUi.Kind.button, action: nil)))
    }

    // MARK: - The script bridge

    func testTheSourceBridgeStoresTheVariables() {
        service.currentKey = "https://example.com"
        service.put("name", value: "value")
        XCTAssertEqual(service.get("name"), "value")
        service.setVariable("var")
        XCTAssertEqual(service.getVariable(), "var")
    }

    func testTheSourceBridgeStoresTheLoginInfoAndHeader() throws {
        service.currentKey = "https://example.com"
        XCTAssertTrue(service.putLoginInfo("{\"user\": \"me\"}"))
        let info = try JSONValue.parse(service.getLoginInfo())
        XCTAssertEqual(info["user"]?.textValue, "me")
        service.putLoginHeader("{\"token\": \"abc\"}")
        let header = try JSONValue.parse(service.getLoginHeader())
        XCTAssertEqual(header["token"]?.textValue, "abc")
        service.removeLoginHeader()
        XCTAssertEqual(service.getLoginHeader(), "")
        service.removeLoginInfo()
        XCTAssertEqual(service.getLoginInfo(), "")
    }
}
