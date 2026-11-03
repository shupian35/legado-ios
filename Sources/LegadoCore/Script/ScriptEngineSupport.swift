//
//  ScriptEngineSupport.swift
//  LegadoCore
//
//  Port of `app/src/main/java/io/legado/app/help/JsExtensions.kt` (the `java`
//  facade exposed to rule scripts) — platform independent parts only.
//
//  Upstream: the rules run in Mozilla Rhino (see `modules/rhino`). On iOS the
//  equivalent engine is JavaScriptCore, which is only available on Apple
//  platforms, so the concrete engine lives behind `#if canImport(JavaScriptCore)`
//  and the Linux build gets a stub that reports the missing capability.
//

import Foundation

/// Errors raised by the script engine and by the `java` facade.
public enum ScriptEngineError: Error, Equatable {
    /// The platform has no JavaScript engine (Linux CI builds).
    case unsupportedPlatform(String)
    /// The script raised an exception.
    case scriptFailed(String)
    /// The script tried to reach a file outside the sandbox.
    case fileAccessDenied(String)
    /// A network call made from a script failed.
    case networkFailure(String)
    /// The script used a capability that was not granted to it.
    ///
    /// The upstream engine uses a class deny-list (`RhinoClassShutter`); the
    /// port uses a capability allow-list, so a script only reaches the parts
    /// of the `java` facade it was granted.
    case capabilityDenied(String)
    /// The script called a method that is not implemented yet.
    case notImplemented(String)
    /// The source verification failed — upstream
    /// `NoStackTraceException("验证结果为空")`.
    case verificationFailed(String)

    /// The message of the error — the text the upstream shows.
    public var message: String {
        switch self {
        case .unsupportedPlatform(let text): return text
        case .scriptFailed(let text): return text
        case .fileAccessDenied(let text): return text
        case .networkFailure(let text): return text
        case .capabilityDenied(let text): return text
        case .notImplemented(let text): return text
        case .verificationFailed(let text): return text
        }
    }
}

/// The capabilities a rule script may use.
///
/// The upstream Rhino engine guards the script with a class deny-list
/// (`modules/rhino/src/main/java/com/script/rhino/RhinoClassShutter.kt`):
/// everything that is not on the list stays reachable, which is why the
/// upstream scripts can reach `Packages.java.*`. The port replaces that with
/// an explicit allow-list: a script only gets the capabilities the engine
/// environment grants it.
public struct ScriptCapabilities: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// `java.ajax`, `java.get`, `java.post` — the network.
    public static let network = ScriptCapabilities(rawValue: 1 << 0)
    /// `java.getFile`, `java.readTxtFile`, `java.listFile` — reading inside
    /// the sandbox.
    public static let fileRead = ScriptCapabilities(rawValue: 1 << 1)
    /// `java.deleteFile` and the other write operations — writing inside the
    /// sandbox.
    public static let fileWrite = ScriptCapabilities(rawValue: 1 << 2)
    /// The `cookie` binding.
    public static let cookies = ScriptCapabilities(rawValue: 1 << 3)
    /// The `cache` binding.
    public static let cache = ScriptCapabilities(rawValue: 1 << 4)
    /// The source data (`java.put`, `java.get`, the login header and info).
    public static let sourceData = ScriptCapabilities(rawValue: 1 << 5)

    /// The default set.
    ///
    /// It grants what the upstream scripts use today: the network, the files
    /// inside the sandbox, the cookies, the cache and the source data.
    public static let `default`: ScriptCapabilities = [
        .network, .fileRead, .fileWrite, .cookies, .cache, .sourceData
    ]

    /// Nothing at all.
    public static let none: ScriptCapabilities = []
}

/// The HTTP client the `java` facade uses from inside a rule script.
public protocol ScriptNetworkClient: AnyObject {
    /// Performs a GET request and returns the response body.
    func scriptGet(_ url: String, headers: [String: String]) throws -> String
    /// Performs a POST request and returns the response body.
    func scriptPost(_ url: String, body: String?, headers: [String: String]) throws -> String
}

/// The file system the `java` facade uses from inside a rule script.
///
/// Upstream confines every file operation to the app cache directory
/// (`JsExtensions.kt:566-579`): `getFile` resolves the path and throws
/// `SecurityException("非法路径")` when the canonical path escapes the
/// sandbox. The port keeps the same rule.
public protocol ScriptFileSandbox: AnyObject {
    /// The directory every relative path is resolved against.
    var baseDirectory: String { get }
    /// Resolves a path inside the sandbox.
    ///
    /// Upstream `JsExtensions.getFile` throws `SecurityException("非法路径")`
    /// when the canonical path escapes the cache directory; the port keeps
    /// that check inside this method.
    func resolvedPath(_ path: String) throws -> String
    func readScriptFile(_ path: String) throws -> String
    func writeScriptFile(_ path: String, content: String) throws
    func scriptFileExists(_ path: String) -> Bool
    func listScriptDirectory(_ path: String) throws -> [String]
    func deleteScriptFile(_ path: String) throws
}

/// A cookie jar exposed to rule scripts as `cookie`.
public protocol ScriptCookieStore: AnyObject {
    func cookie(for url: String) -> String?
    func setCookie(_ value: String, for url: String)
}

/// A key/value cache exposed to rule scripts as `cache`.
public protocol ScriptCacheStore: AnyObject {
    func cacheValue(for key: String) -> String?
    func setCacheValue(_ value: String, for key: String)
}

/// The source specific methods that the upstream `BaseSource` exposes to the
/// scripts — in the upstream the source object *is* the `java` binding
/// (`BaseSource.evalJS` binds `bindings["java"] = this`), so a login script
/// can call `java.putLoginHeader(...)`, `java.put(key, value)` and friends.
public protocol ScriptSourceBridge: AnyObject {
    /// Upstream `BaseSource.put(key, value)`.
    func put(_ key: String, value: String) -> String
    /// Upstream `BaseSource.get(key)`.
    func get(_ key: String) -> String
    /// Upstream `BaseSource.putLoginHeader(header)`.
    func putLoginHeader(_ header: String) -> String
    /// Upstream `BaseSource.getLoginHeader()`.
    func getLoginHeader() -> String
    /// Upstream `BaseSource.removeLoginHeader()`.
    func removeLoginHeader() -> String
    /// Upstream `BaseSource.putLoginInfo(info)`.
    func putLoginInfo(_ info: String) -> Bool
    /// Upstream `BaseSource.getLoginInfo()`.
    func getLoginInfo() -> String
    /// Upstream `BaseSource.removeLoginInfo()`.
    func removeLoginInfo() -> String
    /// Upstream `BaseSource.setVariable(variable)`.
    func setVariable(_ variable: String) -> String
    /// Upstream `BaseSource.getVariable()`.
    func getVariable() -> String
}

/// The dependencies a script engine needs.
public final class ScriptEnvironment {
    public var network: ScriptNetworkClient?
    public var files: ScriptFileSandbox?
    public var cookies: ScriptCookieStore?
    public var cache: ScriptCacheStore?
    /// The source that owns the running script (upstream `BaseSource.evalJS`).
    public var source: ScriptSourceBridge?
    /// The login service — the `java.putLoginHeader` family of the upstream
    /// stores its data with the source (upstream `BaseSource`).
    public var login: SourceLoginService?
    /// The verification — upstream `java.getVerificationCode` and
    /// `java.startBrowserAwait` ask the user to solve a captcha.
    public var verification: ScriptVerificationHandling?
    /// The key of the source that is being evaluated — the verification
    /// dialog shows the name of the source (upstream `sourceOrigin`).
    public var sourceKey: String?
    /// The name of the source that is being evaluated (upstream `sourceName`).
    public var sourceName: String = ""
    /// The headers sent with `java.ajax` by default.
    public var defaultHeaders: [String: String]
    /// The capabilities the script may use.
    ///
    /// The upstream engine guards the script with a class deny-list; the port
    /// grants the capabilities explicitly (see `ScriptCapabilities`).
    public var capabilities: ScriptCapabilities

    public init(
        network: ScriptNetworkClient? = nil,
        files: ScriptFileSandbox? = nil,
        cookies: ScriptCookieStore? = nil,
        cache: ScriptCacheStore? = nil,
        source: ScriptSourceBridge? = nil,
        login: SourceLoginService? = nil,
        verification: ScriptVerificationHandling? = nil,
        sourceKey: String? = nil,
        sourceName: String = "",
        defaultHeaders: [String: String] = [:],
        capabilities: ScriptCapabilities = .default
    ) {
        self.network = network
        self.files = files
        self.cookies = cookies
        self.cache = cache
        self.source = source
        self.login = login
        self.verification = verification
        self.sourceKey = sourceKey
        self.sourceName = sourceName
        self.defaultHeaders = defaultHeaders
        self.capabilities = capabilities
    }

    /// Throws when the capability was not granted.
    public func require(_ capability: ScriptCapabilities, name: String) throws {
        guard capabilities.contains(capability) else {
            throw ScriptEngineError.capabilityDenied(name)
        }
    }
}

/// A script engine that is not available on this platform.
///
/// The upstream engine is Rhino, which runs everywhere; on iOS the engine is
/// JavaScriptCore, which only exists on Apple platforms. The Linux CI build
/// therefore compiles this stub instead — the rule engine itself never needs a
/// script engine unless a rule actually uses `{{…}}` JavaScript.
public final class UnavailableScriptEngine: RuleScriptEngine {
    private let reason: String

    public init(reason: String = "JavaScriptCore is only available on Apple platforms") {
        self.reason = reason
    }

    public func evaluate(_ script: String, bindings: [String: RuleValue]) throws -> RuleValue {
        throw ScriptEngineError.unsupportedPlatform(reason)
    }
}
