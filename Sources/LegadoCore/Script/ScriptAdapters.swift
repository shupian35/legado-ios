//
//  ScriptAdapters.swift
//  LegadoCore
//
//  The concrete capabilities the rule scripts run with.
//
//  The upstream runs the scripts in Rhino and hands them the whole Android
//  runtime (`java.ajax` reaches OkHttp, `java.getFile` reaches the file
//  system, `java.put` reaches the source). The port keeps the same surface
//  but binds it to the services of the app: the HTTP client, the cookie jar,
//  the cache directory and the source that owns the script.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/help/JsExtensions.kt (the `java` facade)
//  app/src/main/java/io/legado/app/help/http/CookieStore.kt
//  app/src/main/java/io/legado/app/utils/FileUtil.kt
//

import Foundation

// MARK: - The network

/// The network capability of the rule scripts.
///
/// Upstream `java.ajax(url)` performs a blocking request with the cookie jar
/// of the app and returns the body; the port does the same, but the transport
/// is asynchronous, so the call is bridged with a semaphore.
public final class HttpScriptClient: ScriptNetworkClient, @unchecked Sendable {

    private let httpClient: HttpClient
    private let cookieStore: CookieStore?
    private let userAgent: String

    public init(
        httpClient: HttpClient,
        cookieStore: CookieStore? = nil,
        userAgent: String = AppSettings.defaultUserAgent
    ) {
        self.httpClient = httpClient
        self.cookieStore = cookieStore
        self.userAgent = userAgent
    }

    public func scriptGet(_ url: String, headers: [String: String]) throws -> String {
        try perform(HttpRequest(url: url, method: "GET", headers: requestHeaders(url: url, extra: headers)))
    }

    public func scriptPost(_ url: String, body: String?, headers: [String: String]) throws -> String {
        let request = HttpRequest(
            url: url,
            method: "POST",
            headers: requestHeaders(url: url, extra: headers),
            body: body?.data(using: .utf8)
        )
        return try perform(request)
    }

    private func requestHeaders(url: String, extra: [String: String]) -> [String: String] {
        var headers: [String: String] = [:]
        if let cookie = cookieStore?.cookie(url: url), !cookie.isEmpty {
            headers["Cookie"] = cookie
        }
        if !userAgent.isEmpty {
            headers["User-Agent"] = userAgent
        }
        for (name, value) in extra { headers[name] = value }
        return headers
    }

    private func perform(_ request: HttpRequest) throws -> String {
        let response = try blockingSend(request)
        if let cookie = response.headers["Set-Cookie"] ?? response.headers["set-cookie"] {
            cookieStore?.replaceCookie(url: request.url, cookie: cookie)
        }
        guard response.isSuccessful else {
            throw HttpError.status(code: response.code, message: response.message)
        }
        return response.body ?? ""
    }

    /// The script API is synchronous, the transport is not.
    ///
    /// The upstream blocks the script thread as well (`java.ajax` waits for
    /// the response), so the port waits on a semaphore.
    private func blockingSend(_ request: HttpRequest) throws -> HttpResponse {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ScriptResultBox<HttpResponse>()
        let client = httpClient
        Task.detached {
            do {
                box.set(.success(try await client.send(request)))
            } catch {
                box.set(.failure(error))
            }
            semaphore.signal()
        }
        semaphore.wait()
        return try box.result.get()
    }
}

/// A box that carries a result out of a detached task.
final class ScriptResultBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Result<Value, Error>?

    func set(_ result: Result<Value, Error>) {
        lock.lock()
        storage = result
        lock.unlock()
    }

    var result: Result<Value, Error> {
        lock.lock()
        defer { lock.unlock() }
        return storage ?? .failure(ScriptEngineError.networkFailure("请求没有返回"))
    }
}

// MARK: - The file system

/// The file capability of the rule scripts.
///
/// Upstream `java.getFile(path)` resolves the path against the cache
/// directory of the app and throws `SecurityException("非法路径")` when the
/// result escapes it (`JsExtensions.kt:566-579`). The port keeps the rule.
public final class SandboxFileSandbox: ScriptFileSandbox, @unchecked Sendable {

    /// The directory every relative path is resolved against.
    public let baseDirectory: String

    private let fileManager: FileManager

    public init(baseDirectory: String, fileManager: FileManager = .default) {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
    }

    public func resolvedPath(_ path: String) throws -> String {
        let base = URL(fileURLWithPath: baseDirectory).standardizedFileURL
        let target: URL
        if path.isEmpty {
            target = base
        } else if path.hasPrefix("/") {
            target = URL(fileURLWithPath: path).standardizedFileURL
        } else {
            target = base.appendingPathComponent(path).standardizedFileURL
        }
        let basePath = base.path.hasSuffix("/") ? base.path : base.path + "/"
        // The base directory itself is allowed — `java.getFile("")` lists it.
        guard target.path == base.path || target.path.hasPrefix(basePath) else {
            throw ScriptEngineError.fileAccessDenied("非法路径")
        }
        return target.path
    }

    public func readScriptFile(_ path: String) throws -> String {
        let resolved = try resolvedPath(path)
        guard let data = fileManager.contents(atPath: resolved) else {
            throw ScriptEngineError.fileAccessDenied("文件不存在")
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(decoding: data, as: UTF8.self)
    }

    public func writeScriptFile(_ path: String, content: String) throws {
        let resolved = try resolvedPath(path)
        let directory = (resolved as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try content.write(toFile: resolved, atomically: true, encoding: .utf8)
    }

    public func scriptFileExists(_ path: String) -> Bool {
        guard let resolved = try? resolvedPath(path) else { return false }
        return fileManager.fileExists(atPath: resolved)
    }

    public func listScriptDirectory(_ path: String) throws -> [String] {
        let resolved = try resolvedPath(path)
        guard let names = try? fileManager.contentsOfDirectory(atPath: resolved) else {
            throw ScriptEngineError.fileAccessDenied("目录不存在")
        }
        return names.sorted()
    }

    public func deleteScriptFile(_ path: String) throws {
        let resolved = try resolvedPath(path)
        try? fileManager.removeItem(atPath: resolved)
    }
}

// MARK: - The cookies

/// The cookie capability of the rule scripts.
///
/// Upstream `cookie.get(url)` / `cookie.setCookie(value, url)` reach the
/// global cookie manager of the app.
public final class CookieScriptStore: ScriptCookieStore, @unchecked Sendable {

    private let cookieStore: CookieStore

    public init(cookieStore: CookieStore) {
        self.cookieStore = cookieStore
    }

    public func cookie(for url: String) -> String? {
        let value = cookieStore.cookie(url: url)
        return value.isEmpty ? nil : value
    }

    public func setCookie(_ value: String, for url: String) {
        cookieStore.replaceCookie(url: url, cookie: value)
    }
}

// MARK: - The cache

/// The cache capability of the rule scripts.
///
/// Upstream `cache.put(key, value)` / `cache.get(key)` reach the
/// `CacheManager` of the app; the port keeps the values in memory for the
/// lifetime of the process.
public final class MemoryScriptCache: ScriptCacheStore, @unchecked Sendable {

    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func cacheValue(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    public func setCacheValue(_ value: String, for key: String) {
        lock.lock()
        storage[key] = value
        lock.unlock()
    }
}

// MARK: - The source

/// The source capability of the rule scripts.
///
/// Upstream binds the source object itself as `java`
/// (`BaseSource.evalJS` → `bindings["java"] = this`), so `java.put(key,
/// value)` writes the variables of the source that is being evaluated and
/// `java.putLoginHeader(header)` stores the login header of that source.
public final class SourceScriptBridge: ScriptSourceBridge, @unchecked Sendable {

    /// The variables of the source (upstream `BookSource.variable`).
    private let variables: RuleDataBox?
    /// The login service (upstream `BaseSource.getLoginHeader()`).
    private let login: SourceLoginService?
    /// The key of the source that owns the script.
    private let key: String

    public init(variables: RuleDataBox?, login: SourceLoginService?, key: String) {
        self.variables = variables
        self.login = login
        self.key = key
    }

    public func put(_ key: String, value: String) -> String {
        variables?.putVariable(key, value)
        return value
    }

    public func get(_ key: String) -> String {
        variables?.getVariable(key) ?? ""
    }

    public func putLoginHeader(_ header: String) -> String {
        try? login?.putLoginHeader(header, for: key)
        return header
    }

    public func getLoginHeader() -> String {
        (try? login?.loginHeader(for: key)) ?? ""
    }

    public func removeLoginHeader() -> String {
        try? login?.removeLoginHeader(for: key)
        return ""
    }

    public func putLoginInfo(_ info: String) -> Bool {
        (try? login?.putLoginInfo(json: info, for: key)) ?? false
    }

    public func getLoginInfo() -> String {
        guard let info = try? login?.loginInfo(for: key) else { return "" }
        var members: [String: JSONValue] = [:]
        for (name, value) in info { members[name] = .string(value) }
        return JSONValue.object(members).jsonString
    }

    public func removeLoginInfo() -> String {
        try? login?.removeLoginInfo(for: key)
        return ""
    }

    public func setVariable(_ variable: String) -> String {
        variables?.setVariables(json: variable)
        return variable
    }

    public func getVariable() -> String {
        variables?.json ?? ""
    }
}

// MARK: - The context of a script

/// The source a script belongs to.
///
/// The upstream binds the source object as `java`; the port passes the key and
/// the variable box of the source down to the engine, which builds the
/// `java` facade from it.
public struct ScriptSourceContext {
    /// The key of the source (upstream `BookSource.getKey()`).
    public var key: String
    /// The name of the source (upstream `BookSource.getTag()`).
    public var name: String
    /// The variables of the source.
    public var variables: RuleDataBox?

    public init(key: String, name: String = "", variables: RuleDataBox? = nil) {
        self.key = key
        self.name = name
        self.variables = variables
    }
}
