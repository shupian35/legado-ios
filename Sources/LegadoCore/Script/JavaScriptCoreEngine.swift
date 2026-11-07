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

    public override init() { super.init() }

    public func put(_ key: String, value: String) { storage[key] = value }
    public func get(_ key: String) -> String { storage[key] ?? "" }
    public func clear() { storage.removeAll() }
    public var all: [String: String] { storage }
}

/// The `cookie` object exposed to rule scripts — upstream `CookieStore`.
@objc public protocol LegadoCookieExport: JSExport {
    func getCookie(_ url: String) -> String
    func setCookie(_ value: String, for url: String)
    /// Upstream `CookieStore.getKey(url, key)` — the sources read the session
    /// id of a site with `cookie.getKey("fanqienovel.com", "sessionid")`.
    func getKey(_ url: String, key: String) -> String
    func removeCookie(_ url: String)
    func replaceCookie(_ value: String, for url: String)
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
    public func getKey(_ url: String, key: String) -> String { store?.cookieKey(for: url, key: key) ?? "" }
    public func removeCookie(_ url: String) { store?.removeCookie(for: url) }
    public func replaceCookie(_ value: String, for url: String) { store?.replaceCookie(value, for: url) }
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

/// The `source` object exposed to rule scripts.
///
/// Upstream `BaseSource.evalJS` binds the source itself, so a rule script can
/// read `source.bookSourceUrl`, call `source.getKey()` and reach the login
/// data of the source with `source.getLoginInfoMap()`.
@objc public protocol LegadoSourceExport: JSExport {
    var key: String { get }
    var bookSourceUrl: String { get }
    var bookSourceName: String { get }
    var bookSourceGroup: String { get }
    var bookSourceComment: String { get }
    var variableComment: String { get }
    var loginUrl: String { get }
    var header: String { get }
    var variable: String { get }
    var lastUpdateTime: Double { get }
    func getKey() -> String
    func getTag() -> String
    func getVariable() -> String
    func setVariable(_ variable: String) -> String
    func get(_ key: String) -> String
    func put(_ key: String, value: String) -> String
    func getLoginHeader() -> String
    func getLoginHeaderMap() -> [String: String]
    func putLoginHeader(_ header: String) -> String
    func removeLoginHeader() -> String
    func getLoginInfo() -> String
    func getLoginInfoMap() -> [String: String]
    func putLoginInfo(_ info: String) -> Bool
    func removeLoginInfo() -> String
    func refreshExplore()
    func refreshJSLib()
}

/// The `source` implementation — a book source plus its login/variable store.
@objc public final class LegadoSourceObject: NSObject, LegadoSourceExport {
    private let source: BookSource
    private let bridge: ScriptSourceBridge?
    /// Forgets the evaluated `jsLib` of the source — upstream `refreshJSLib`.
    private let onRefreshJSLib: (() -> Void)?

    public init(
        source: BookSource,
        bridge: ScriptSourceBridge?,
        onRefreshJSLib: (() -> Void)? = nil
    ) {
        self.source = source
        self.bridge = bridge
        self.onRefreshJSLib = onRefreshJSLib
        super.init()
    }

    public var key: String { source.key }
    public var bookSourceUrl: String { source.bookSourceUrl }
    public var bookSourceName: String { source.bookSourceName }
    public var bookSourceGroup: String { source.bookSourceGroup ?? "" }
    public var bookSourceComment: String { source.bookSourceComment ?? "" }
    public var variableComment: String { source.variableComment ?? "" }
    public var loginUrl: String { source.loginUrl ?? "" }
    public var header: String { source.header ?? "" }
    public var variable: String { BookSourceVariables.sourceVariables(source.key) ?? "" }
    public var lastUpdateTime: Double { Double(source.lastUpdateTime) }

    public func getKey() -> String { source.key }
    public func getTag() -> String { source.bookSourceName }
    public func getVariable() -> String { bridge?.getVariable() ?? "" }
    public func setVariable(_ variable: String) -> String { bridge?.setVariable(variable) ?? variable }
    public func get(_ key: String) -> String { bridge?.get(key) ?? "" }
    public func put(_ key: String, value: String) -> String { bridge?.put(key, value: value) ?? value }
    public func getLoginHeader() -> String { bridge?.getLoginHeader() ?? "" }
    public func putLoginHeader(_ header: String) -> String { bridge?.putLoginHeader(header) ?? header }
    public func removeLoginHeader() -> String { bridge?.removeLoginHeader() ?? "" }
    public func getLoginInfo() -> String { bridge?.getLoginInfo() ?? "" }
    public func putLoginInfo(_ info: String) -> Bool { bridge?.putLoginInfo(info) ?? false }
    public func removeLoginInfo() -> String { bridge?.removeLoginInfo() ?? "" }

    /// The login data as an object — upstream `BaseSource.getLoginInfoMap()`.
    public func getLoginInfoMap() -> [String: String] {
        Self.map(from: bridge?.getLoginInfo() ?? "")
    }

    /// The login header as an object — upstream
    /// `BaseSource.getLoginHeaderMap()`.
    public func getLoginHeaderMap() -> [String: String] {
        Self.map(from: bridge?.getLoginHeader() ?? "")
    }

    /// Upstream `refreshExplore()` on the sources of the yck collection —
    /// drops the cached categories of the source.
    public func refreshExplore() {
        ExploreKinds.clearCache()
    }

    /// Upstream `refreshJSLib()` — the library is evaluated again.
    public func refreshJSLib() {
        onRefreshJSLib?()
    }

    private static func map(from json: String) -> [String: String] {
        guard !json.isEmpty,
              let value = try? JSONValue.parse(json),
              case .object(let members) = value else { return [:] }
        var result: [String: String] = [:]
        for (key, member) in members { result[key] = member.textValue }
        return result
    }
}

/// The `java` facade — upstream `JsExtensions.kt`.
@objc public protocol LegadoJavaExport: JSExport {
    func ajax(_ url: String) -> String
    /// Without headers the upstream `java` is the source itself and
    /// `java.get(key)` reads one of its variables.
    func get(_ url: String, headers: [String: String]?) -> String
    func post(_ url: String, body: String, headers: [String: String]?) -> String
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
    func hexEncodeToString(_ text: String) -> String
    func hexDecodeToString(_ text: String) -> String
    func md5(_ text: String) -> String
    func urlEncode(_ text: String) -> String
    func urlDecode(_ text: String) -> String
    // The file downloads — upstream `JsExtensions.downloadFile` and
    // `JsExtensions.cacheFile`.
    func downloadFile(_ url: String) -> String
    func cacheFile(_ url: String, saveTime: Int) -> String
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
    // The helpers the rules of the common sources call — upstream
    // `JsExtensions.kt`.
    func log(_ message: String) -> String
    func toast(_ message: String)
    func longToast(_ message: String)
    func md5Encode(_ text: String) -> String
    /// Upstream `JsExtensions.getString(rule)` — one field of the page.
    func getString(_ rule: String) -> String
    /// Upstream `JsExtensions.getStringList(rule)`.
    func getStringList(_ rule: String) -> [String]
    func timeFormat(_ time: Double) -> String
    func timeFormatUTC(_ time: Double, format: String, sh: Int) -> String
    func encodeURI(_ text: String) -> String
    func t2s(_ text: String) -> String
    func s2t(_ text: String) -> String
    func randomUUID() -> String
    func getUserAgent() -> String
    func getWebViewUA() -> String
    func getCookie(_ tag: String, key: String?) -> String
    func removeCookie(_ tag: String)
    func toNumChapter(_ text: String) -> String
}

/// The `java` facade implementation.
@objc public final class LegadoJavaFacade: NSObject, LegadoJavaExport {
    private let environment: ScriptEnvironment
    /// Upstream `java.url` — writable, so a script can rewrite the request URL.
    @objc public var url: String = ""
    /// Upstream `java.headerMap`.
    @objc public let headerMap = LegadoHeaderMap()
    /// The files `java.cacheFile` downloaded — upstream the `CacheManager`
    /// (the key is the `md5Encode16` of the address).
    private let fileCache = ScriptFileCache()
    /// The first error a facade method hit during the current evaluation.
    ///
    /// JavaScriptCore cannot bridge a Swift error into a JS exception, and the
    /// documented alternative — raising an `NSException` — is not caught by
    /// every JavaScriptCore build: on macOS the exception escapes
    /// `evaluateScript` and terminates the process. The methods therefore
    /// record the error and return a default; `JavaScriptCoreEngine.evaluate`
    /// throws it once the script returns.
    private var pendingError: ScriptEngineError?

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

    public func get(_ url: String, headers: [String: String]?) -> String {
        // The upstream `java` object is the source itself, so `java.get(key)`
        // without the headers reads one of its variables; the network form
        // always passes the headers.
        guard let headers else {
            return environment.source?.get(url) ?? ""
        }
        return perform { client in
            var merged = self.requestHeaders()
            for (key, value) in headers { merged[key] = value }
            return try client.scriptGet(url, headers: merged)
        }
    }

    public func post(_ url: String, body: String, headers: [String: String]?) -> String {
        perform { client in
            var merged = self.requestHeaders()
            if let headers {
                for (key, value) in headers { merged[key] = value }
            }
            return try client.scriptPost(url, body: body, headers: merged)
        }
    }

    /// Upstream `JsExtensions.getString(rule)` — the script asks the running
    /// rule engine for one field of the page (`java.getString("$.author")`).
    public func getString(_ rule: String) -> String {
        environment.ruleEvaluator?(rule) ?? ""
    }

    /// Upstream `JsExtensions.getStringList(rule)`.
    public func getStringList(_ rule: String) -> [String] {
        environment.ruleListEvaluator?(rule) ?? []
    }

    private func requestHeaders() -> [String: String] {
        var headers = environment.defaultHeaders
        for (key, value) in headerMap.all { headers[key] = value }
        return headers
    }

    private func perform(_ body: (ScriptNetworkClient) throws -> String) -> String {
        guard environment.capabilities.contains(.network) else {
            return fail(ScriptEngineError.capabilityDenied("network"))
        }
        guard let client = environment.network else {
            return fail(ScriptEngineError.notImplemented("java.ajax requires a network client"))
        }
        do {
            return try body(client)
        } catch {
            return fail(error)
        }
    }

    // MARK: - Files

    public func getFile(_ path: String) -> String {
        guard environment.capabilities.contains(.fileRead) else {
            return fail(ScriptEngineError.capabilityDenied("fileRead"))
        }
        guard let files = environment.files else {
            return fail(ScriptEngineError.notImplemented("java.getFile requires a file sandbox"))
        }
        do {
            let resolved = try files.resolvedPath(path)
            return resolved
        } catch {
            return fail(error)
        }
    }

    public func readFile(_ path: String) -> String {
        guard environment.capabilities.contains(.fileRead) else {
            return fail(ScriptEngineError.capabilityDenied("fileRead"))
        }
        guard let files = environment.files else {
            return fail(ScriptEngineError.notImplemented("java.readFile requires a file sandbox"))
        }
        do {
            return try files.readScriptFile(path)
        } catch {
            return fail(error)
        }
    }

    public func readTxtFile(_ path: String) -> String { readFile(path) }

    public func writeFile(_ path: String, content: String) -> String {
        guard environment.capabilities.contains(.fileWrite) else {
            return fail(ScriptEngineError.capabilityDenied("fileWrite"))
        }
        guard let files = environment.files else {
            return fail(ScriptEngineError.notImplemented("java.writeFile requires a file sandbox"))
        }
        do {
            try files.writeScriptFile(path, content: content)
            return ""
        } catch {
            return fail(error)
        }
    }

    public func deleteFile(_ path: String) -> String {
        guard environment.capabilities.contains(.fileWrite) else {
            return fail(ScriptEngineError.capabilityDenied("fileWrite"))
        }
        guard let files = environment.files else {
            return fail(ScriptEngineError.notImplemented("java.deleteFile requires a file sandbox"))
        }
        do {
            try files.deleteScriptFile(path)
            return ""
        } catch {
            return fail(error)
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
            fail(error)
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

    // The names of the upstream `HexUtil` helpers.
    public func hexEncodeToString(_ text: String) -> String {
        hexEncode(text)
    }

    public func hexDecodeToString(_ text: String) -> String {
        hexDecode(text)
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

    /// Upstream `MD5Utils.md5Encode` — the same digest as `java.md5`.
    public func md5Encode(_ text: String) -> String {
        ScriptDigest.md5Hex(Data(text.utf8))
    }

    /// Upstream `JsExtensions.encodeURI` — `URLEncoder.encode(str, "UTF-8")`.
    ///
    /// The form encoding of Java: a space becomes `+`, and only the unreserved
    /// characters survive.
    public func encodeURI(_ text: String) -> String {
        var output = ""
        for byte in text.utf8 {
            let character = Character(UnicodeScalar(byte))
            if character.isLetter || character.isNumber || "-_.*~".contains(character) {
                output.append(character)
            } else if character == " " {
                output.append("+")
            } else {
                output += String(format: "%%%02X", byte)
            }
        }
        return output
    }

    /// Upstream `JsExtensions.t2s` — traditional to simplified Chinese.
    public func t2s(_ text: String) -> String {
        ChineseConverter.toSimplified(text)
    }

    /// Upstream `JsExtensions.s2t` — simplified to traditional Chinese.
    public func s2t(_ text: String) -> String {
        ChineseConverter.toTraditional(text)
    }

    /// Upstream `JsExtensions.randomUUID`.
    public func randomUUID() -> String {
        UUID().uuidString.lowercased()
    }

    /// Upstream `JsExtensions.getUserAgent` — the user agent of the app.
    public func getUserAgent() -> String {
        environment.defaultHeaders.first { $0.key.lowercased() == "user-agent" }?.value
            ?? SourceSupport.defaultUserAgent
    }

    /// Upstream `JsExtensions.getWebViewUA` — the port has no separate web
    /// view engine, so the app user agent is the closest answer.
    public func getWebViewUA() -> String {
        getUserAgent()
    }

    // The date format of the upstream `JsExtensions.timeFormat`.
    private static let plainTimeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }()

    /// Upstream `JsExtensions.timeFormat(time)` — milliseconds.
    public func timeFormat(_ time: Double) -> String {
        Self.plainTimeFormat.string(from: Date(timeIntervalSince1970: time / 1000))
    }

    /// Upstream `JsExtensions.timeFormatUTC(time, format, sh)`.
    public func timeFormatUTC(_ time: Double, format: String, sh: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.timeZone = TimeZone(secondsFromGMT: sh * 3600)
        return formatter.string(from: Date(timeIntervalSince1970: time / 1000))
    }

    /// Upstream `JsExtensions.getCookie(tag, key)` — the whole cookie when no
    /// key is given.
    public func getCookie(_ tag: String, key: String?) -> String {
        guard let store = environment.cookies else { return "" }
        if let key, !key.isEmpty { return store.cookieKey(for: tag, key: key) }
        return store.cookie(for: tag) ?? ""
    }

    /// Upstream `JsExtensions.removeCookie(tag)`.
    public func removeCookie(_ tag: String) {
        environment.cookies?.removeCookie(for: tag)
    }

    /// Upstream `JsExtensions.toNumChapter` — the Chinese number of a chapter
    /// title is replaced with its digits (`第十二章` → `第12章`).
    public func toNumChapter(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: RulePatterns.titleNumPattern),
              let match = regex.firstMatch(
                  in: text,
                  range: NSRange(location: 0, length: (text as NSString).length)
              ),
              match.numberOfRanges >= 4 else { return text }
        let ns = text as NSString
        let head = ns.substring(with: match.range(at: 1))
        let number = ChapterProgressMapper.parseChineseNumber(ns.substring(with: match.range(at: 2)))
        let tail = ns.substring(with: match.range(at: 3))
        return ns.replacingCharacters(in: match.range, with: "\(head)\(number)\(tail)")
    }

    // The messages of the rules — upstream `Debug.log`.
    public func log(_ message: String) -> String {
        print("[rule] \(message)")
        return message
    }

    // The toasts of the rules — the port has no cross-platform toast in the
    // core, so the message goes to the log (upstream shows it on the screen).
    public func toast(_ message: String) {
        print("[rule toast] \(message)")
    }

    public func longToast(_ message: String) {
        print("[rule toast] \(message)")
    }

    // MARK: - The file downloads

    /// Upstream `JsExtensions.downloadFile(url)`.
    ///
    /// The upstream analyses the address with the source (the type of the
    /// file may be given in the option block of the address), downloads it
    /// into the cache directory under the name `<md5 of the url>.<type>` and
    /// returns the path RELATIVE to the cache directory.
    public func downloadFile(_ url: String) -> String {
        guard environment.capabilities.contains(.network) else {
            return fail(ScriptEngineError.capabilityDenied("network"))
        }
        guard environment.capabilities.contains(.fileWrite) else {
            return fail(ScriptEngineError.capabilityDenied("fileWrite"))
        }
        guard let client = environment.network else {
            return fail(ScriptEngineError.notImplemented("java.downloadFile requires a network client"))
        }
        guard let files = environment.files else {
            return fail(ScriptEngineError.notImplemented("java.downloadFile requires a file sandbox"))
        }
        do {
            return try fileCache.download(
                url: url,
                client: client,
                files: files,
                headers: requestHeaders()
            )
        } catch {
            return fail(error)
        }
    }

    /// Upstream `JsExtensions.cacheFile(urlStr, saveTime)`.
    ///
    /// The upstream caches the file under the key `md5Encode16(urlStr)` in the
    /// `CacheManager` (with a lifetime of `saveTime` seconds) and returns the
    /// TEXT of the file. The port keeps the downloaded files in the cache
    /// directory of the app and remembers the paths for the session.
    public func cacheFile(_ url: String, saveTime: Int) -> String {
        guard environment.capabilities.contains(.network) else {
            return fail(ScriptEngineError.capabilityDenied("network"))
        }
        guard environment.capabilities.contains(.fileWrite) else {
            return fail(ScriptEngineError.capabilityDenied("fileWrite"))
        }
        guard let client = environment.network else {
            return fail(ScriptEngineError.notImplemented("java.cacheFile requires a network client"))
        }
        guard let files = environment.files else {
            return fail(ScriptEngineError.notImplemented("java.cacheFile requires a file sandbox"))
        }
        do {
            return try fileCache.cacheFile(
                url: url,
                saveTime: saveTime,
                client: client,
                files: files,
                headers: requestHeaders()
            )
        } catch {
            return fail(error)
        }
    }

    // MARK: - Source methods

    public func put(_ key: String, value: String) -> String {
        guard environment.capabilities.contains(.sourceData) else {
            return fail(ScriptEngineError.capabilityDenied("sourceData"))
        }
        return environment.source?.put(key, value: value) ?? value
    }

    public func get(_ key: String) -> String {
        guard environment.capabilities.contains(.sourceData) else {
            return fail(ScriptEngineError.capabilityDenied("sourceData"))
        }
        return environment.source?.get(key) ?? ""
    }

    public func putLoginHeader(_ header: String) -> String {
        guard environment.capabilities.contains(.sourceData) else {
            return fail(ScriptEngineError.capabilityDenied("sourceData"))
        }
        return environment.source?.putLoginHeader(header) ?? ""
    }

    public func getLoginHeader() -> String {
        guard environment.capabilities.contains(.sourceData) else {
            return fail(ScriptEngineError.capabilityDenied("sourceData"))
        }
        return environment.source?.getLoginHeader() ?? ""
    }

    public func removeLoginHeader() -> String {
        guard environment.capabilities.contains(.sourceData) else {
            return fail(ScriptEngineError.capabilityDenied("sourceData"))
        }
        return environment.source?.removeLoginHeader() ?? ""
    }

    public func putLoginInfo(_ info: String) -> Bool {
        guard environment.capabilities.contains(.sourceData) else {
            fail(ScriptEngineError.capabilityDenied("sourceData"))
            return false
        }
        return environment.source?.putLoginInfo(info) ?? false
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
            return fail(ScriptEngineError.notImplemented("java.getVerificationCode requires a verification handler"))
        }
        do {
            return try verification.verificationCode(
                imageURL: imageURL,
                sourceKey: environment.sourceKey ?? "",
                sourceName: environment.sourceName
            )
        } catch {
            return fail(error)
        }
    }

    /// Upstream `java.startBrowserAwait(url, title)` — shows the page in the
    /// built-in browser and waits for the user to finish the check.
    ///
    /// The upstream returns the whole response object; the port returns the
    /// text of the page, which is what the scripts use.
    public func startBrowserAwait(_ url: String, title: String) -> String {
        guard let verification = environment.verification else {
            return fail(ScriptEngineError.notImplemented("java.startBrowserAwait requires a verification handler"))
        }
        do {
            return try verification.browserResult(
                url: url,
                sourceKey: environment.sourceKey ?? "",
                sourceName: environment.sourceName
            )
        } catch {
            return fail(error)
        }
    }

    /// Records `error` and returns the empty string, so a facade method that
    /// hit an error can keep the `String` return type. `evaluate` throws the
    /// recorded error once the script has returned.
    @discardableResult
    private func fail(_ error: Error) -> String {
        if pendingError == nil {
            pendingError = (error as? ScriptEngineError)
                ?? .scriptFailed(error.localizedDescription)
        }
        return ""
    }

    /// Returns and clears the error of the current evaluation.
    func consumeError() -> ScriptEngineError? {
        defer { pendingError = nil }
        return pendingError
    }

    // MARK: - The external links

    /// Upstream `java.openUrl(url, mimeType)` — the script does not open the
    /// link itself: the confirmation dialog of
    /// `OpenUrlConfirmActivity` asks the user first.
    public func openUrl(_ url: String, mimeType: String?) {
        guard let handler = environment.openURL else {
            fail(ScriptEngineError.notImplemented("java.openUrl requires an open url handler"))
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
            fail(error)
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
    /// `nil` when the platform refused to start JavaScriptCore (a restricted
    /// sandbox such as a sideloaded container, where `JSContext()` returns
    /// nil). The engine then reports a script error instead of taking the
    /// whole app down at launch.
    private let context: JSContext?
    private let environment: ScriptEnvironment
    private let javaFacade: LegadoJavaFacade
    /// Serialises the evaluations: a `JSContext` is not thread safe, and the
    /// search, the discovery tab and the chapter loads all share the engine.
    private let evaluationLock = NSRecursiveLock()
    /// The sources whose `jsLib` was already evaluated, with the digest of the
    /// code — upstream `SharedJsScope` keys the scope the same way.
    private var loadedLibraries: [String: String] = [:]

    public init(environment: ScriptEnvironment = ScriptEnvironment()) {
        self.environment = environment
        let context = JSContext()
        self.context = context
        self.javaFacade = LegadoJavaFacade(environment: environment)
        guard let context else { return }
        context.exceptionHandler = { ctx, exception in
            ctx?.exception = exception
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
    public var jsContext: JSContext? { context }

    public func evaluate(_ script: String, bindings: [String: RuleValue]) throws -> RuleValue {
        try evaluate(script, bindings: bindings, source: nil)
    }

    public func evaluate(
        _ script: String,
        bindings: [String: RuleValue],
        source: ScriptSourceContext?
    ) throws -> RuleValue {
        guard let context else {
            throw ScriptEngineError.scriptFailed("the JavaScript runtime is unavailable")
        }
        evaluationLock.lock()
        defer { evaluationLock.unlock() }
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
            environment.ruleEvaluator = source.ruleEvaluator
            environment.ruleListEvaluator = source.ruleListEvaluator
            // Upstream also binds the source itself as `source`; the objects
            // of the sources read `source.key`, `source.getLoginInfoMap()` and
            // the variables through it.
            context.setObject(
                sourceObject(for: source),
                forKeyedSubscript: "source" as NSString
            )
        } else {
            environment.ruleEvaluator = nil
            environment.ruleListEvaluator = nil
            context.setObject(JSValue(nullIn: context), forKeyedSubscript: "source" as NSString)
        }
        for (key, value) in bindings {
            context.setObject(Self.toJS(value, in: context), forKeyedSubscript: key as NSString)
        }
        // A previous evaluation may have recorded an error that the script
        // itself caught.
        _ = javaFacade.consumeError()
        // Evaluate the shared library of the source first — upstream the
        // `jsLib` scope is shared by every script of the source, and rules of
        // the common sources call the helpers it defines.
        if let bookSource = source?.bookSource {
            try evaluateLibrary(of: bookSource, in: context)
        }
        // Evaluated on every call: the old cache stored the *result* of the
        // first evaluation, so a second run of the same script returned the
        // stale value instead of running it again.
        let result = context.evaluateScript(script)
        if let error = javaFacade.consumeError() {
            throw ScriptEngineError.scriptFailed(error.message)
        }
        if let exception = context.exception {
            context.exception = nil
            throw ScriptEngineError.scriptFailed(Self.describe(exception))
        }
        return Self.fromJS(result)
    }

    /// The `source` binding of one evaluation.
    private func sourceObject(for source: ScriptSourceContext) -> Any {
        guard let bookSource = source.bookSource else {
            // A source that is not a book source (the RSS sources): the
            // scripts still read its address.
            return ["key": source.key, "bookSourceUrl": source.key]
        }
        return LegadoSourceObject(
            source: bookSource,
            bridge: environment.source,
            onRefreshJSLib: { [weak self] in
                self?.loadedLibraries.removeValue(forKey: bookSource.key)
            }
        )
    }

    /// Evaluates the `jsLib` of a source once — upstream `SharedJsScope`.
    ///
    /// The library is plain JavaScript in the sources of the collection; the
    /// `{"name": "url"}` form of the upstream is not used by them and is not
    /// downloaded here.
    private func evaluateLibrary(of source: BookSource, in context: JSContext) throws {
        guard let library = source.jsLib, !library.isBlank else { return }
        let digest = ScriptDigest.md5Hex(library)
        if loadedLibraries[source.key] == digest { return }
        _ = context.evaluateScript(library)
        if let exception = context.exception {
            context.exception = nil
            throw ScriptEngineError.scriptFailed(Self.describe(exception))
        }
        loadedLibraries[source.key] = digest
    }

    private static func describe(_ exception: JSValue) -> String {
        if let message = exception.toString() { return message }
        return "JavaScript exception"
    }

    // MARK: - Conversion

    static func toJS(_ value: RuleValue, in context: JSContext) -> Any {
        switch value {
        case .null:
            return JSValue(nullIn: context)
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
            return JSValue(undefinedIn: context)
        }
    }

    static func toJS(_ value: JSONValue, in context: JSContext) -> Any {
        switch value {
        case .null:
            return JSValue(nullIn: context)
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
            // `toArray()` hands back `[Any]` on the current overlay, so each
            // element is cast back to its `JSValue` before the recursion.
            let items = value.toArray()?.map { fromJS($0 as? JSValue) } ?? []
            return .list(items)
        }
        if value.isObject {
            var members: [String: RuleValue] = [:]
            // `objectForKeys()`/`objectForKey(_:)` were obsoleted from the Swift
            // overlay; `toDictionary()` is the supported replacement and yields
            // the same `JSValue` members for a plain JS object.
            if let members_ = value.toDictionary() as? [String: Any] {
                for (key, member) in members_ {
                    members[key] = fromJS(member as? JSValue)
                }
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
