//
//  SourceLogin.swift
//  LegadoCore
//
//  Port of the login support of
//  `app/src/main/java/io/legado/app/data/entities/BaseSource.kt` (the login
//  script, the login UI rows and the cached login information) and of
//  `app/src/main/java/io/legado/app/ui/login/SourceLoginDialog.kt` (the
//  dialog that collects the login data and runs the login script).
//
//  Upstream stores the login information AES encrypted with the device id as
//  the key (`BaseSource.putLoginInfo`); the port keeps the plain JSON in the
//  cache table because the device id does not exist on iOS — see the parity
//  matrix, "Deliberate deviations".
//

import Foundation

/// The sources that support the login flow — upstream `BaseSource`.
public protocol LoginCapable: AnalyzeSource {
    /// The login script — upstream `BaseSource.loginUrl`.
    var loginUrl: String? { get }
    /// The login UI — upstream `BaseSource.loginUi` (a JSON array of rows).
    var loginUi: String? { get }
    /// The script that checks whether the session is still valid.
    var loginCheckJs: String? { get }
}

extension BookSource: LoginCapable {}
extension RssSource: LoginCapable {}

/// The errors of the login flow.
public enum SourceLoginError: Error, Equatable {
    /// The login UI JSON is broken.
    case invalidLoginUi(String)
    /// The script engine is not available on this platform.
    case noScriptEngine
    /// The login script does not implement a `login` function.
    case loginNotImplemented
    /// The source has no login script.
    case noLoginScript
}

/// The login service — upstream `BaseSource` + `SourceLoginDialog`.
public final class SourceLoginService: ScriptSourceBridge, @unchecked Sendable {

    /// The store that holds the cached login information.
    private let store: LegadoStore
    /// The cookie jar the login header is copied into.
    private let cookieStore: CookieStore
    /// The script engine that runs the login script.
    ///
    /// It is settable, because the engine is built from the services of the
    /// app and the login service is one of them — the app sets it once the
    /// engine exists.
    public var scriptEngine: RuleScriptEngine?

    public init(store: LegadoStore, cookieStore: CookieStore, scriptEngine: RuleScriptEngine? = nil) {
        self.store = store
        self.cookieStore = cookieStore
        self.scriptEngine = scriptEngine
    }

    // MARK: - The login UI

    /// The parsed login UI rows — upstream `BaseSource.loginUi()`.
    public func loginUi(for source: LoginCapable) -> [RowUi] {
        Self.parseLoginUi(source.loginUi)
    }

    /// Parses the login UI JSON — upstream `GSON.fromJsonArray<RowUi>`.
    public static func parseLoginUi(_ json: String?) -> [RowUi] {
        guard let json, !json.isEmpty else { return [] }
        guard let data = json.data(using: .utf8) else { return [] }
        if let rows = try? JSONDecoder().decode([RowUi].self, from: data) { return rows }
        // A single row object is accepted as well.
        if let row = try? JSONDecoder().decode(RowUi.self, from: data) { return [row] }
        return []
    }

    /// The login script — upstream `BaseSource.getLoginJs()`.
    ///
    /// The upstream strips the `@js:` prefix and the `<js>…</js>` wrapper.
    public static func loginScript(from loginUrl: String?) -> String? {
        guard let loginUrl, !loginUrl.isEmpty else { return nil }
        if loginUrl.hasPrefix("@js:") {
            return String(loginUrl.dropFirst(4))
        }
        if loginUrl.hasPrefix("<js>"), let end = loginUrl.lastIndex(of: "<") {
            return String(loginUrl[loginUrl.index(loginUrl.startIndex, offsetBy: 4)..<end])
        }
        return loginUrl
    }

    // MARK: - The login information

    /// The stored login information — upstream `BaseSource.getLoginInfoMap()`.
    public func loginInfo(for key: String) throws -> [String: String]? {
        guard let cached = try store.cache("userInfo_\(key)", now: 0), !cached.isEmpty else { return nil }
        guard let value = try? JSONValue.parse(cached) else { return nil }
        guard case let .object(members) = value else { return nil }
        var result: [String: String] = [:]
        for (name, member) in members { result[name] = member.textValue ?? "" }
        return result
    }

    /// Stores the login information — upstream `BaseSource.putLoginInfo(info)`.
    @discardableResult
    public func putLoginInfo(_ info: [String: String], for key: String) throws -> Bool {
        var members: [String: JSONValue] = [:]
        for (name, value) in info { members[name] = .string(value) }
        try store.putCache("userInfo_\(key)", value: JSONValue.object(members).jsonString, deadline: 0)
        return true
    }

    /// Stores the login information from its JSON text.
    @discardableResult
    public func putLoginInfo(json: String, for key: String) throws -> Bool {
        guard let value = try? JSONValue.parse(json) else { return false }
        guard case let .object(members) = value else { return false }
        var info: [String: String] = [:]
        for (name, member) in members { info[name] = member.textValue ?? "" }
        return try putLoginInfo(info, for: key)
    }

    /// Removes the login information — upstream `BaseSource.removeLoginInfo()`.
    public func removeLoginInfo(for key: String) throws {
        try store.putCache("userInfo_\(key)", value: nil, deadline: 0)
    }

    // MARK: - The login header

    /// The stored login header — upstream `BaseSource.getLoginHeader()`.
    public func loginHeader(for key: String) throws -> String? {
        guard let cached = try store.cache("loginHeader_\(key)", now: 0), !cached.isEmpty else { return nil }
        return cached
    }

    /// The stored login header as a map — upstream `getLoginHeaderMap()`.
    public func loginHeaderMap(for key: String) throws -> [String: String]? {
        guard let cached = try loginHeader(for: key) else { return nil }
        guard let value = try? JSONValue.parse(cached), case let .object(members) = value else { return nil }
        var result: [String: String] = [:]
        for (name, member) in members { result[name] = member.textValue ?? "" }
        return result
    }

    /// Stores the login header — upstream `BaseSource.putLoginHeader(header)`.
    ///
    /// The cookie of the header is copied into the cookie jar, exactly like
    /// the upstream `CookieStore.replaceCookie`.
    public func putLoginHeader(_ header: String, for key: String) throws {
        if let value = try? JSONValue.parse(header), case let .object(members) = value {
            let cookie = members["Cookie"]?.textValue ?? members["cookie"]?.textValue
            if let cookie { cookieStore.replaceCookie(url: key, cookie: cookie) }
        }
        try store.putCache("loginHeader_\(key)", value: header, deadline: 0)
    }

    /// Removes the login header — upstream `BaseSource.removeLoginHeader()`.
    public func removeLoginHeader(for key: String) throws {
        try store.putCache("loginHeader_\(key)", value: nil, deadline: 0)
        cookieStore.removeCookie(url: key)
    }

    // MARK: - The login script

    /// Runs the login script — upstream `BaseSource.login()`.
    ///
    /// The upstream script calls the `login` function of the login script and
    /// throws `Function login not implements!!!` when it is missing.
    @discardableResult
    public func login(source: LoginCapable, loginData: [String: String]) throws -> RuleValue {
        guard let engine = scriptEngine else { throw SourceLoginError.noScriptEngine }
        guard let loginScript = Self.loginScript(from: source.loginUrl), !loginScript.isEmpty else {
            throw SourceLoginError.noLoginScript
        }
        let script = """
        \(loginScript)
        if(typeof login=='function'){
            login.apply(this);
        } else {
            throw('Function login not implements!!!')
        }
        """
        var members: [String: RuleValue] = [:]
        for (name, value) in loginData { members[name] = .text(value) }
        let bindings: [String: RuleValue] = [
            "baseUrl": .text(source.key),
            "source": .scriptObject(members),
            "result": .scriptObject(members)
        ]
        return try engine.evaluate(script, bindings: bindings)
    }

    /// Runs the "login check" script against a response.
    ///
    /// Upstream `WebBook` runs `loginCheckJs` against the response of every
    /// request; the script may replace the response or throw to signal that
    /// the login is required.
    public func checkLogin(source: LoginCapable, response: RuleValue) throws -> RuleValue {
        guard let checkJs = source.loginCheckJs, !checkJs.isEmpty else { return response }
        guard let engine = scriptEngine else { throw SourceLoginError.noScriptEngine }
        return try engine.evaluate(checkJs, bindings: ["result": response])
    }

    // MARK: - The button actions

    /// Runs the action of a login UI button.
    ///
    /// Upstream `SourceLoginDialog.handleButtonClick`: an absolute URL is
    /// opened in the browser, anything else is JavaScript that runs after the
    /// login script with the `result` binding holding the login data.
    public enum ButtonAction: Equatable {
        case openURL(String)
        case script(String)
    }

    /// The action of a login UI button.
    public static func buttonAction(_ row: RowUi) -> ButtonAction? {
        guard let action = row.action, !action.isEmpty else { return nil }
        if action.hasPrefix("http://") || action.hasPrefix("https://") {
            return .openURL(action)
        }
        return .script(action)
    }

    /// Runs the JavaScript action of a login UI button.
    @discardableResult
    public func runButtonScript(source: LoginCapable, script: String, loginData: [String: String]) throws -> RuleValue {
        guard let engine = scriptEngine else { throw SourceLoginError.noScriptEngine }
        var members: [String: RuleValue] = [:]
        for (name, value) in loginData { members[name] = .text(value) }
        let loginScript = Self.loginScript(from: source.loginUrl) ?? ""
        let bindings: [String: RuleValue] = [
            "baseUrl": .text(source.key),
            "source": .scriptObject(members),
            "result": .scriptObject(members)
        ]
        return try engine.evaluate("\(loginScript)\n\(script)", bindings: bindings)
    }

    // MARK: - ScriptSourceBridge

    public func put(_ key: String, value: String) -> String {
        try? store.putCache("v_\(currentKey)_\(key)", value: value, deadline: 0)
        return value
    }

    public func get(_ key: String) -> String {
        (try? store.cache("v_\(currentKey)_\(key)", now: 0)) ?? ""
    }

    public func putLoginHeader(_ header: String) -> String {
        try? putLoginHeader(header, for: currentKey)
        return header
    }

    public func getLoginHeader() -> String {
        (try? loginHeader(for: currentKey)) ?? ""
    }

    public func removeLoginHeader() -> String {
        try? removeLoginHeader(for: currentKey)
        return ""
    }

    public func putLoginInfo(_ info: String) -> Bool {
        (try? putLoginInfo(json: info, for: currentKey)) ?? false
    }

    public func getLoginInfo() -> String {
        (try? loginInfo(for: currentKey)).map { info in
            var members: [String: JSONValue] = [:]
            for (name, value) in info { members[name] = .string(value) }
            return JSONValue.object(members).jsonString
        } ?? ""
    }

    public func removeLoginInfo() -> String {
        try? removeLoginInfo(for: currentKey)
        return ""
    }

    public func setVariable(_ variable: String) -> String {
        try? store.putCache("sourceVariable_\(currentKey)", value: variable, deadline: 0)
        return variable
    }

    public func getVariable() -> String {
        (try? store.cache("sourceVariable_\(currentKey)", now: 0)) ?? ""
    }

    /// The key of the source that owns the running script.
    ///
    /// Upstream binds the source object itself, so the script always talks
    /// to the source that is being evaluated.
    public var currentKey: String = ""
}
