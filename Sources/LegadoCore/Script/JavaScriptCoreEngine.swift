//
//  JavaScriptCoreEngine.swift
//  LegadoCore
//
//  Port of the Rhino based script engine in `modules/rhino` plus the `java`
//  facade in `app/src/main/java/io/legado/app/help/JsExtensions.kt`.
//
//  JavaScriptCore only exists on Apple platforms, so the whole file is guarded.
//  On Linux the package still compiles and the rule engine works for every
//  rule that does not use `{{…}}` JavaScript.
//

#if canImport(JavaScriptCore)

import Foundation
import JavaScriptCore

// MARK: - Exported helper objects

/// The `java.headerMap` object — upstream `java.headerMap.put('xxx','yyy')`.
@objc public protocol LegadoHeaderMapExport: JSExport {
    func put(_ key: String, value: String)
    func get(_ key: String) -> String
    func clear()
}

/// The `java.headerMap` implementation.
@objc public final class LegadoHeaderMap: NSObject, LegadoHeaderMapExport {
    private var storage: [String: String] = [:]

    public init() { super.init() }

    public func put(_ key: String, value: String) { storage[key] = value }
    public func get(_ key: String) -> String { storage[key] ?? "" }
    public func clear() { storage.removeAll() }
    public var all: [String: String] { storage }
}

/// The `cookie` object exposed to rule scripts.
@objc public protocol LegadoCookieExport: JSExport {
    func getCookie(_ url: String) -> String
    func setCookie(_ value: String, for url: String)
}

/// The `cookie` implementation, backed by a `ScriptCookieStore`.
@objc public final class LegadoCookieObject: NSObject, LegadoCookieExport {
    private let store: ScriptCookieStore?

    public init(store: ScriptCookieStore?) {
        self.store = store
        super.init()
    }

    public func getCookie(_ url: String) -> String { store?.cookie(for: url) ?? "" }
    public func setCookie(_ value: String, for url: String) { store?.setCookie(value, for: url) }
}

/// The `cache` object exposed to rule scripts.
@objc public protocol LegadoCacheExport: JSExport {
    func get(_ key: String) -> String
    func put(_ value: String, for key: String)
}

/// The `cache` implementation, backed by a `ScriptCacheStore`.
@objc public final class LegadoCacheObject: NSObject, LegadoCacheExport {
    private let store: ScriptCacheStore?

    public init(store: ScriptCacheStore?) {
        self.store = store
        super.init()
    }

    public func get(_ key: String) -> String { store?.cacheValue(for: key) ?? "" }
    public func put(_ value: String, for key: String) { store?.setCacheValue(value, for: key) }
}

/// The `java` facade — upstream `JsExtensions.kt`.
@objc public protocol LegadoJavaExport: JSExport {
    func ajax(_ url: String) -> String
    func get(_ url: String, headers: [String: String]) -> String
    func post(_ url: String, body: String, headers: [String: String]) -> String
    func getFile(_ path: String) -> String
    func readFile(_ path: String) -> String
    func readTxtFile(_ path: String) -> String
    func writeFile(_ path: String, content: String) -> String
    func deleteFile(_ path: String) -> String
    func exists(_ path: String) -> Bool
    func listFiles(_ path: String) -> [String]
    func base64Encode(_ text: String) -> String
    func base64Decode(_ text: String) -> String
    func hexEncode(_ text: String) -> String
    func hexDecode(_ text: String) -> String
    func md5(_ text: String) -> String
    func urlEncode(_ text: String) -> String
    func urlDecode(_ text: String) -> String
    // The source methods — upstream the source object is the `java` binding.
    func put(_ key: String, value: String) -> String
    func get(_ key: String) -> String
    func putLoginHeader(_ header: String) -> String
    func getLoginHeader() -> String
    func removeLoginHeader() -> String
    func putLoginInfo(_ info: String) -> Bool
    func getLoginInfo() -> String
    func removeLoginInfo() -> String
    func setVariable(_ variable: String) -> String
    func getVariable() -> String
    // The source verification — upstream `JsExtensions.kt`.
    func getVerificationCode(_ imageURL: String) -> String
    func startBrowserAwait(_ url: String, title: String) -> String
    // The external links — upstream `java.openUrl(url, mimeType)`.
    func openUrl(_ url: String)
    func openUrl(_ url: String, mimeType: String?)
}

/// The `java` facade implementation.
@objc public final class LegadoJavaFacade: NSObject, LegadoJavaExport {
    private let environment: ScriptEnvironment
    /// Upstream `java.url` — writable, so a script can rewrite the request URL.
    @objc public var url: String = ""
    /// Upstream `java.headerMap`.
    @objc public let headerMap = LegadoHeaderMap()

    public init(environment: ScriptEnvironment) {
        self.environment = environment
        super.init()
    }

    // MARK: - Network

    public func ajax(_ url: String) -> String {
        perform { client in
            try client.scriptGet(url, headers: self.requestHeaders())
        }
    }

    public func get(_ url: String, headers: [String: String]) -> String {
        perform { client in
            var merged = self.requestHeaders()
            for (key, value) in headers { merged[key] = value }
            return try client.scriptGet(url, headers: merged)
        }
    }

    public func post(_ url: String, body: String, headers: [String: String]) -> String {
        perform { client in
            var merged = self.requestHeaders()
            for (key, value) in headers { merged[key] = value }
            return try client.scriptPost(url, body: body, headers: merged)
        }
    }

    private func requestHeaders() -> [String: String] {
        var headers = environment.defaultHeaders
        for (key, value) in headerMap.all { headers[key] = value }
        return headers
    }

    private func perform(_ body: (ScriptNetworkClient) throws -> String) -> String {
        guard environment.capabilities.contains(.network) else {
            raise(ScriptEngineError.capabilityDenied("network"))
        }
        guard let client = environment.network else {
            raise(ScriptEngineError.notImplemented("java.ajax requires a network client"))
        }
        do {
            return try body(client)
        } catch {
            raise(error)
        }
    }

    // MARK: - Files

    public func getFile(_ path: String) -> String {
        guard environment.capabilities.contains(.fileRead) else {
            raise(ScriptEngineError.capabilityDenied("fileRead"))
        }
        guard let files = environment.files else {
            raise(ScriptEngineError.notImplemented("java.getFile requires a file sandbox"))
        }
        do {
            let resolved = try files.resolvedPath(path)
            return resolved
        } catch {
            raise(error)
        }
    }

    public func readFile(_ path: String) -> String {
        guard environment.capabilities.contains(.fileRead) else {
            raise(ScriptEngineError.capabilityDenied("fileRead"))
        }
        guard let files = environment.files else {
            raise(ScriptEngineError.notImplemented("java.readFile requires a file sandbox"))
        }
        do {
            return try files.readScriptFile(path)
        } catch {
            raise(error)
        }
    }

    public func readTxtFile(_ path: String) -> String { readFile(path) }

    public func writeFile(_ path: String, content: String) -> String {
        guard environment.capabilities.contains(.fileWrite) else {
            raise(ScriptEngineError.capabilityDenied("fileWrite"))
        }
        guard let files = environment.files else {
            raise(ScriptEngineError.notImplemented("java.writeFile requires a file sandbox"))
        }
        do {
            try files.writeScriptFile(path, content: content)
            return ""
        } catch {
            raise(error)
        }
    }

    public func deleteFile(_ path: String) -> String {
        guard environment.capabilities.contains(.fileWrite) else {
            raise(ScriptEngineError.capabilityDenied("fileWrite"))
        }
        guard let files = environment.files else {
            raise(ScriptEngineError.notImplemented("java.deleteFile requires a file sandbox"))
        }
        do {
            try files.deleteScriptFile(path)
            return ""
        } catch {
            raise(error)
        }
    }

    public func exists(_ path: String) -> Bool {
        environment.files?.scriptFileExists(path) ?? false
    }

    public func listFiles(_ path: String) -> [String] {
        guard let files = environment.files else { return [] }
        do {
            return try files.listScriptDirectory(path)
        } catch {
            raise(error)
            return []
        }
    }

    // MARK: - Encoding helpers

    public func base64Encode(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
    }

    public func base64Decode(_ text: String) -> String {
        guard let data = Data(base64Encoded: text) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    public func hexEncode(_ text: String) -> String {
        text.utf8.map { String(format: "%02x", $0) }.joined()
    }

    public func hexDecode(_ text: String) -> String {
        var bytes: [UInt8] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
            if let byte = UInt8(text[index..<next], radix: 16) { bytes.append(byte) }
            index = next
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    public func md5(_ text: String) -> String {
        ScriptDigest.md5Hex(Data(text.utf8))
    }

    public func urlEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    public func urlDecode(_ text: String) -> String {
        text.removingPercentEncoding ?? text
    }

    // MARK: - Source methods

    public func put(_ key: String, value: String) -> String {
        guard environment.capabilities.contains(.sourceData) else {
            raise(ScriptEngineError.capabilityDenied("sourceData"))
        }
        environment.source?.put(key, value: value) ?? value
    }

    public func get(_ key: String) -> String {
        guard environment.capabilities.contains(.sourceData) else {
            raise(ScriptEngineError.capabilityDenied("sourceData"))
        }
        environment.source?.get(key) ?? ""
    }

    public func putLoginHeader(_ header: String) -> String {
        guard environment.capabilities.contains(.sourceData) else {
            raise(ScriptEngineError.capabilityDenied("sourceData"))
        }
        environment.source?.putLoginHeader(header) ?? ""
    }

    public func getLoginHeader() -> String {
        guard environment.capabilities.contains(.sourceData) else {
            raise(ScriptEngineError.capabilityDenied("sourceData"))
        }
        environment.source?.getLoginHeader() ?? ""
    }

    public func removeLoginHeader() -> String {
        guard environment.capabilities.contains(.sourceData) else {
            raise(ScriptEngineError.capabilityDenied("sourceData"))
        }
        environment.source?.removeLoginHeader() ?? ""
    }

    public func putLoginInfo(_ info: String) -> Bool {
        guard environment.capabilities.contains(.sourceData) else {
            raise(ScriptEngineError.capabilityDenied("sourceData"))
        }
        environment.source?.putLoginInfo(info) ?? false
    }

    public func getLoginInfo() -> String {
        environment.source?.getLoginInfo() ?? ""
    }

    public func removeLoginInfo() -> String {
        environment.source?.removeLoginInfo() ?? ""
    }

    public func setVariable(_ variable: String) -> String {
        environment.source?.setVariable(variable) ?? ""
    }

    public func getVariable() -> String {
        environment.source?.getVariable() ?? ""
    }

    // MARK: - The source verification

    /// Upstream `java.getVerificationCode(imageUrl)` — shows the captcha of the
    /// source and waits for the user to type the code.
    public func getVerificationCode(_ imageURL: String) -> String {
        guard let verification = environment.verification else {
            raise(ScriptEngineError.notImplemented("java.getVerificationCode requires a verification handler"))
            return ""
        }
        do {
            return try verification.verificationCode(
                imageURL: imageURL,
                sourceKey: environment.sourceKey ?? "",
                sourceName: environment.sourceName
            )
        } catch {
            raise(error)
            return ""
        }
    }

    /// Upstream `java.startBrowserAwait(url, title)` — shows the page in the
    /// built-in browser and waits for the user to finish the check.
    ///
    /// The upstream returns the whole response object; the port returns the
    /// text of the page, which is what the scripts use.
    public func startBrowserAwait(_ url: String, title: String) -> String {
        guard let verification = environment.verification else {
            raise(ScriptEngineError.notImplemented("java.startBrowserAwait requires a verification handler"))
            return ""
        }
        do {
            return try verification.browserResult(
                url: url,
                sourceKey: environment.sourceKey ?? "",
                sourceName: environment.sourceName
            )
        } catch {
            raise(error)
            return ""
        }
    }

    private func raise(_ error: Error) {
        let reason = (error as? ScriptEngineError).map { String(describing: $0) } ?? error.localizedDescription
        NSException(name: NSExceptionName("LegadoScriptError"), reason: reason, userInfo: nil).raise()
    }

    // MARK: - The external links

    /// Upstream `java.openUrl(url, mimeType)` — the script does not open the
    /// link itself: the confirmation dialog of
    /// `OpenUrlConfirmActivity` asks the user first.
    public func openUrl(_ url: String, mimeType: String?) {
        guard let handler = environment.openURL else {
            raise(ScriptEngineError.notImplemented("java.openUrl requires an open url handler"))
            return
        }
        do {
            _ = try handler.confirmOpenURL(
                url: url,
                mimeType: mimeType,
                sourceKey: environment.sourceKey ?? "",
                sourceName: environment.sourceName
            )
        } catch {
            raise(error)
        }
    }

    /// Upstream `java.openUrl(url)` — the overload without the type.
    public func openUrl(_ url: String) {
        openUrl(url, mimeType: nil)
    }
}

// MARK: - The engine

/// A `RuleScriptEngine` backed by JavaScriptCore.
public final class JavaScriptCoreEngine: RuleScriptEngine {
    private let context: JSContext
    private let environment: ScriptEnvironment
    private let javaFacade: LegadoJavaFacade
    /// Upstream compiles every script once and reuses the compiled form.
    private var compiledScripts: [String: JSValue] = [:]

    public init(environment: ScriptEnvironment = ScriptEnvironment()) {
        self.environment = environment
        let context = JSContext()!
        self.context = context
        self.javaFacade = LegadoJavaFacade(environment: environment)
        context.exceptionHandler = { ctx, exception in
            ctx.exception = exception
        }
        context.setObject(javaFacade, forKeyedSubscript: "java" as NSString)
        // The capability model: a binding the script was not granted is not
        // exposed at all, so the script cannot even reach it.
        if environment.capabilities.contains(.cookies) {
            context.setObject(LegadoCookieObject(store: environment.cookies), forKeyedSubscript: "cookie" as NSString)
        }
        if environment.capabilities.contains(.cache) {
            context.setObject(LegadoCacheObject(store: environment.cache), forKeyedSubscript: "cache" as NSString)
        }
    }

    /// The underlying JavaScript context, so a host can install extra globals.
    public var jsContext: JSContext { context }

    public func evaluate(_ script: String, bindings: [String: RuleValue]) throws -> RuleValue {
        try evaluate(script, bindings: bindings, source: nil)
    }

    public func evaluate(
        _ script: String,
        bindings: [String: RuleValue],
        source: ScriptSourceContext?
    ) throws -> RuleValue {
        // Upstream binds the source object as `java`, so the script always
        // talks to the source that is being evaluated.
        if let source {
            environment.source = SourceScriptBridge(
                variables: source.variables,
                login: environment.login,
                key: source.key
            )
            environment.sourceKey = source.key
            environment.sourceName = source.name
        }
        for (key, value) in bindings {
            context.setObject(Self.toJS(value, in: context), forKeyedSubscript: key as NSString)
        }
        let result: JSValue?
        if let compiled = compiledScripts[script] {
            result = context.invokeObject(compiled, withArguments: [])
        } else {
            result = context.evaluateScript(script)
            if let result { compiledScripts[script] = result }
        }
        if let exception = context.exception {
            context.exception = nil
            throw ScriptEngineError.scriptFailed(Self.describe(exception))
        }
        return Self.fromJS(result)
    }

    private static func describe(_ exception: JSValue) -> String {
        if let message = exception.toString() { return message }
        return "JavaScript exception"
    }

    // MARK: - Conversion

    static func toJS(_ value: RuleValue, in context: JSContext) -> Any {
        switch value {
        case .null:
            return JSValue(nullInContext: context)
        case .text(let text):
            return text
        case .number(let number):
            return number
        case .list(let items):
            return items.map { toJS($0, in: context) }
        case .object(let members), .scriptObject(let members):
            var result: [String: Any] = [:]
            for (key, member) in members { result[key] = toJS(member, in: context) }
            return result
        case .json(let json):
            return toJS(json, in: context)
        case .node:
            return JSValue(undefinedInContext: context)
        }
    }

    static func toJS(_ value: JSONValue, in context: JSContext) -> Any {
        switch value {
        case .null:
            return JSValue(nullInContext: context)
        case .bool(let flag):
            return flag
        case .number(let number):
            return number
        case .string(let text):
            return text
        case .array(let items):
            return items.map { toJS($0, in: context) }
        case .object(let members):
            var result: [String: Any] = [:]
            for (key, member) in members { result[key] = toJS(member, in: context) }
            return result
        }
    }

    static func fromJS(_ value: JSValue?) -> RuleValue {
        guard let value else { return .null }
        if value.isUndefined || value.isNull { return .null }
        if value.isBoolean { return .text(value.toBool() ? "true" : "false") }
        if value.isNumber { return .number(value.toDouble()) }
        if value.isString { return .text(value.toString() ?? "") }
        if value.isArray {
            let items = value.toArray()?.map { fromJS($0) } ?? []
            return .list(items)
        }
        if value.isObject {
            var members: [String: RuleValue] = [:]
            for key in value.objectForKeys() ?? [] {
                members[key] = fromJS(value.objectForKey(key))
            }
            // Upstream returns a Rhino `NativeObject` here.
            return .scriptObject(members)
        }
        return .null
    }
}

/// The former name of the engine — kept so the older call sites still build.
public typealias JavaScriptCoreScriptEngine = JavaScriptCoreEngine

#endif
