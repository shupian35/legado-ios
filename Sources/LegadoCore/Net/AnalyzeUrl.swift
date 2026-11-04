//
//  AnalyzeUrl.swift
//  LegadoCore
//
//  The port of app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeUrl.kt.
//
//  It turns a source URL rule into a concrete HTTP request: it evaluates the
//  embedded scripts, expands the keywords and the page placeholders, parses the
//  trailing option block and encodes the query / form parameters.
//

import Foundation

/// The dependencies of `AnalyzeUrl`.
public struct AnalyzeUrlDependencies {
    public var httpClient: HttpClient
    public var cookieStore: CookieStore
    public var scriptEngine: RuleScriptEngine?
    public var userAgent: String
    public var loginHeaderMap: [String: String]?
    /// Receives the raw HTML of every fetched page — upstream
    /// `Debug.log(sourceUrl, body, state = 10/20/30/40)`.
    ///
    /// The state tells the step: 10 = the search page, 20 = the detail page,
    /// 30 = the table of contents and 40 = the chapter content. The debugger
    /// shows the four pages in the "原始HTML" dialogs of the upstream's
    /// `BookSourceDebugActivity`.
    public var debugCapture: ((Int, String) -> Void)?

    public init(
        httpClient: HttpClient = URLSessionHttpClient(),
        cookieStore: CookieStore = CookieStore(),
        scriptEngine: RuleScriptEngine? = nil,
        userAgent: String = SourceSupport.defaultUserAgent,
        loginHeaderMap: [String: String]? = nil,
        debugCapture: ((Int, String) -> Void)? = nil
    ) {
        self.httpClient = httpClient
        self.cookieStore = cookieStore
        self.scriptEngine = scriptEngine
        self.userAgent = userAgent
        self.loginHeaderMap = loginHeaderMap
        self.debugCapture = debugCapture
    }
}

public enum AnalyzeUrlError: Error, Equatable {
    case invalidURL(String)
    case scriptFailed(String)
}

public final class AnalyzeUrl {
    /// The URL rule after the scripts were evaluated.
    public private(set) var ruleUrl: String = ""
    /// The final URL.
    public private(set) var url: String = ""
    /// The response type of the option block.
    public private(set) var type: String?
    /// The request headers.
    public private(set) var headerMap: [String: String] = [:]
    /// The WebDAV server id of the option block.
    public private(set) var serverID: Int64?

    private var body: String?
    private var urlNoQuery: String = ""
    private var encodedForm: String?
    private var encodedQuery: String?
    private var charset: String?
    private var method: String = "GET"
    private var proxy: String?
    private var retry: Int = 0
    private var useWebView: Bool = false
    private var webJs: String?
    private let enabledCookieJar: Bool
    /// The registrable domain the request belongs to.
    public private(set) var domain: String = ""
    private var webViewDelayTime: Int64 = 0
    private let concurrentRateLimiter: ConcurrentRateLimiter

    // MARK: - Inputs

    private let mUrl: String
    private let key: String?
    private let page: Int?
    private let speakText: String?
    private let speakSpeed: Int?
    private var baseUrl: String?
    private let source: (any AnalyzeSource)?
    private let bookName: String?
    private let chapterTitle: String?
    private let readTimeout: TimeInterval
    private let callTimeout: TimeInterval
    private let dependencies: AnalyzeUrlDependencies

    /// `paramPattern` — the start of the option block.
    private static let paramPattern = "\\s*,\\s*(?=\\{)"

    public init(
        url mUrl: String,
        key: String? = nil,
        page: Int? = nil,
        speakText: String? = nil,
        speakSpeed: Int? = nil,
        baseUrl: String? = nil,
        source: (any AnalyzeSource)? = nil,
        bookName: String? = nil,
        chapterTitle: String? = nil,
        readTimeout: TimeInterval = 20,
        callTimeout: TimeInterval = 60,
        headerMap headerMapF: [String: String]? = nil,
        hasLoginHeader: Bool = false,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) {
        self.mUrl = mUrl
        self.key = key
        self.page = page
        self.speakText = speakText
        self.speakSpeed = speakSpeed
        self.baseUrl = baseUrl
        self.source = source
        self.bookName = bookName
        self.chapterTitle = chapterTitle
        self.readTimeout = readTimeout
        self.callTimeout = callTimeout
        self.dependencies = dependencies
        self.enabledCookieJar = source?.enabledCookieJar == true
        self.concurrentRateLimiter = ConcurrentRateLimiter(
            key: source?.key,
            concurrentRate: source?.concurrentRate
        )

        // Strip the option block from the base URL.
        if let baseUrl {
            if let range = AnalyzeUrl.firstOptionBlockRange(in: baseUrl) {
                let ns = baseUrl as NSString
                self.baseUrl = ns.substring(to: range.location)
            } else {
                self.baseUrl = baseUrl
            }
        }

        // The request headers.
        let headers: [String: String]
        if let headerMapF {
            headers = headerMapF
        } else {
            headers = source?.headerMap(
                hasLoginHeader: hasLoginHeader,
                scriptEngine: dependencies.scriptEngine,
                userAgent: dependencies.userAgent,
                loginHeaderMap: dependencies.loginHeaderMap
            ) ?? [:]
        }
        if !headers.isEmpty {
            headerMap = headers
            if let proxyHeader = headers["proxy"] {
                proxy = proxyHeader
                headerMap.removeValue(forKey: "proxy")
            }
        }

        initUrl()
        domain = NetworkUtils.subDomain(source?.key ?? url)
    }

    // MARK: - URL processing

    /// Process the URL — upstream `initUrl`.
    public func initUrl() {
        ruleUrl = mUrl
        analyzeJs()
        replaceKeyPageJs()
        analyzeUrl()
    }

    /// Evaluate the `@js:` / `<js>` blocks — upstream `analyzeJs`.
    private func analyzeJs() {
        var start = 0
        var result = ruleUrl
        let ns = ruleUrl as NSString
        let pattern = RulePatterns.jsPattern
        pattern.enumerateMatches(
            in: ruleUrl,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        ) { match, _, _ in
            guard let match else { return }
            if match.range.location > start {
                let literal = ns.substring(with: NSRange(location: start, length: match.range.location - start))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !literal.isEmpty {
                    result = literal.replacingOccurrences(of: "@result", with: result)
                }
            }
            let jsText: String
            if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound {
                jsText = ns.substring(with: match.range(at: 2))
            } else {
                jsText = ns.substring(with: match.range(at: 1))
            }
            result = (try? self.evalJS(jsText, result: .text(result)))?.textValue ?? ""
            start = match.range.location + match.range.length
        }
        if ns.length > start {
            let literal = ns.substring(from: start)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !literal.isEmpty {
                result = literal.replacingOccurrences(of: "@result", with: result)
            }
        }
        ruleUrl = result
    }

    /// Replace the keywords, the page placeholders and the `{{js}}` blocks.
    private func replaceKeyPageJs() {
        // The embedded `{{js}}` rules are replaced first, so that a rule
        // containing `<` or `>` is not cut in the wrong place.
        if ruleUrl.contains("{{"), ruleUrl.contains("}}") {
            let analyzer = RuleAnalyzer(ruleUrl)
            let resolved = analyzer.innerRule(startStr: "{{", endStr: "}}") { inner -> String? in
                guard let value = try? evalJS(inner, result: nil) else { return nil }
                switch value {
                case .text(let text):
                    return text
                case .number(let number):
                    if number == number.rounded(), number.magnitude < 1e15 {
                        return String(format: "%.0f", number)
                    }
                    return "\(number)"
                default:
                    return value.textValue
                }
            }
            if !resolved.isEmpty { ruleUrl = resolved }
        }
        // The page placeholders `<1,2,3>`.
        if let page {
            let pattern = RulePatterns.pagePattern
            var matches: [NSTextCheckingResult] = []
            let ns = ruleUrl as NSString
            pattern.enumerateMatches(
                in: ruleUrl,
                options: [],
                range: NSRange(location: 0, length: ns.length)
            ) { match, _, _ in
                if let match { matches.append(match) }
            }
            for match in matches {
                let group = ns.substring(with: match.range(at: 1))
                let pages = group.components(separatedBy: ",")
                let replacement: String
                if page <= pages.count, page >= 1 {
                    replacement = pages[page - 1].trimmingJavaSpaces()
                } else {
                    replacement = pages.last?.trimmingJavaSpaces() ?? ""
                }
                let matched = ns.substring(with: match.range)
                ruleUrl = ruleUrl.replacingOccurrences(of: matched, with: replacement)
            }
        }
    }

    /// Parse the URL and the option block — upstream `analyzeUrl`.
    private func analyzeUrl() {
        let urlNoOption: String
        var optionRange: NSRange?
        if let range = AnalyzeUrl.firstOptionBlockRange(in: ruleUrl) {
            optionRange = range
            urlNoOption = (ruleUrl as NSString).substring(to: range.location)
        } else {
            urlNoOption = ruleUrl
        }
        url = NetworkUtils.absoluteURL(base: baseUrl, urlNoOption)
        if let newBase = NetworkUtils.baseUrl(url) {
            baseUrl = newBase
        }
        if let optionRange, urlNoOption.count != ruleUrl.count {
            let optionString = (ruleUrl as NSString).substring(from: optionRange.location + optionRange.length)
            if let option = AnalyzeUrl.parseOption(optionString) {
                if let method = option.method, method.uppercased() == "POST" {
                    self.method = "POST"
                }
                if let headers = option.headers {
                    for (key, value) in headers {
                        headerMap[key] = value
                    }
                }
                if let body = option.body {
                    self.body = body
                }
                type = option.type
                charset = option.charset
                retry = option.retry ?? 0
                useWebView = option.useWebView
                webJs = option.webJs
                if let jsString = option.js,
                   let value = try? evalJS(jsString, result: .text(url)) {
                    let text = value.textValue
                    if !text.isEmpty { url = text }
                }
                serverID = option.serverID
                webViewDelayTime = max(0, option.webViewDelayTime ?? 0)
            }
        }
        urlNoQuery = url
        if method == "GET" {
            if let position = url.firstIndex(of: "?") {
                let query = String(url[url.index(after: position)...])
                encodedQuery = encodeParams(query, charset: charset, isQuery: true)
                urlNoQuery = String(url[url.startIndex..<position])
            }
        } else if method == "POST", let body {
            let isJson = body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{")
                || body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[")
            let isXml = body.contains("<")
            let hasContentType = headerMap["Content-Type"] != nil
            if !isJson, !isXml, !hasContentType {
                encodedForm = encodeParams(body, charset: charset, isQuery: false)
            }
        }
    }

    /// Encode the query or the form parameters — upstream `encodeParams`.
    private func encodeParams(_ params: String, charset: String?, isQuery: Bool) -> String {
        let checkEncoded = (charset ?? "").isEmpty
        if isQuery, charset != "escape", NetworkUtils.encodedQuery(params) {
            return params
        }
        if isQuery, charset != "escape" {
            return AnalyzeUrl.percentEncodeQuery(params)
        }
        var output = ""
        let characters = Array(params)
        var position = 0
        let length = characters.count
        while position <= length {
            if !output.isEmpty { output += "&" }
            var ampOffset = position
            while ampOffset < length, characters[ampOffset] != "&" { ampOffset += 1 }
            var eqOffset = -1
            var index = position
            while index < ampOffset {
                if characters[index] == "=" { eqOffset = index; break }
                index += 1
            }
            let key: String
            let value: String?
            if eqOffset == -1 {
                key = String(characters[position..<ampOffset])
                value = nil
            } else {
                key = String(characters[position..<eqOffset])
                value = String(characters[(eqOffset + 1)..<ampOffset])
            }
            output += AnalyzeUrl.appendEncoded(key, checkEncoded: checkEncoded, charset: charset)
            if let value {
                output += "="
                output += AnalyzeUrl.appendEncoded(value, checkEncoded: checkEncoded, charset: charset)
            }
            position = ampOffset + 1
        }
        return output
    }

    private static func appendEncoded(_ value: String, checkEncoded: Bool, charset: String?) -> String {
        if checkEncoded, NetworkUtils.encodedForm(value) { return value }
        if charset == "escape" { return escape(value) }
        return percentEncodeForm(value)
    }

    // MARK: - Requests

    /// `true` when the request is a POST.
    public var isPost: Bool { method == "POST" }

    /// The `User-Agent` used by the request.
    public var userAgent: String {
        headerMap.first { $0.key.lowercased() == SourceSupport.userAgentName.lowercased() }?.value
            ?? dependencies.userAgent
    }

    /// Perform the request — upstream `getStrResponseAwait`.
    @discardableResult
    public func strResponse(
        jsString: String? = nil,
        sourceRegex: String? = nil,
        useWebView: Bool = false
    ) async throws -> HttpResponse {
        if let type, !type.isEmpty {
            // A typed request returns the raw bytes.
            let data = try await rawBytes()
            return HttpResponse(url: url, body: data.map { String(data: $0, encoding: .utf8) ?? "" }, data: data)
        }
        return try await concurrentRateLimiter.withLimit {
            setCookie()
            var request = HttpRequest(
                url: url,
                method: method,
                headers: headerMap,
                body: requestBody(),
                readTimeout: readTimeout,
                callTimeout: max(60, readTimeout * 2),
                proxy: proxy
            )
            if request.body == nil, let encodedQuery {
                request.url = urlNoQuery + "?" + encodedQuery
            }
            let response = try await dependencies.httpClient.send(request)
            saveCookie(response)
            return response
        }
    }

    private func requestBody() -> Data? {
        if let encodedForm { return encodedForm.data(using: .utf8) }
        if let body { return body.data(using: .utf8) }
        return nil
    }

    private func rawBytes() async throws -> Data? {
        var request = HttpRequest(
            url: url,
            method: method,
            headers: headerMap,
            body: requestBody(),
            readTimeout: readTimeout,
            callTimeout: max(60, readTimeout * 2),
            proxy: proxy
        )
        if request.body == nil, let encodedQuery {
            request.url = urlNoQuery + "?" + encodedQuery
        }
        let response = try await dependencies.httpClient.send(request)
        return response.data
    }

    /// Merge the stored cookie into the request — upstream `setCookie`.
    public func setCookie() {
        guard enabledCookieJar else { return }
        let cookie = dependencies.cookieStore.cookie(url: url)
        if !cookie.isEmpty {
            headerMap["Cookie"] = cookie
        }
    }

    /// Store the cookies of the response — upstream `saveCookie`.
    public func saveCookie(_ response: HttpResponse) {
        guard enabledCookieJar else { return }
        for (name, value) in response.headers where name.lowercased() == "set-cookie" {
            dependencies.cookieStore.replaceCookie(url: url, cookie: value)
        }
    }

    // MARK: - Upload

    /// Upload a file — the port of the upstream `AnalyzeUrl.upload`
    /// (`app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeUrl.kt:587`).
    ///
    /// The option block's `body` is a JSON map; every value equal to
    /// `fileRequest` is replaced by the uploaded file (the upstream builds a
    /// `mapOf("fileName", "file", "contentType")` for it). The request drops the
    /// query (`url(urlNoQuery)`) and sends a `multipart/form-data` body.
    public func upload(fileName: String, file: Data, contentType: String) async throws -> HttpResponse {
        guard let body else {
            throw AnalyzeUrlError.invalidURL("上传地址缺少 body 参数")
        }
        guard let parsed = try? JSONValue.parse(body), let map = parsed.objectValue else {
            throw AnalyzeUrlError.invalidURL("上传地址的 body 不是合法的 JSON")
        }
        var parts: [MultipartBody.Part] = []
        for (key, value) in map {
            if value.stringValue == "fileRequest" {
                parts.append(
                    MultipartBody.Part(
                        name: key,
                        fileName: fileName,
                        contentType: contentType,
                        data: file
                    )
                )
            } else {
                parts.append(MultipartBody.Part.field(key, value.stringValue ?? ""))
            }
        }
        let boundary = MultipartBody.makeBoundary()
        let payload = MultipartBody.encode(parts, boundary: boundary)
        return try await concurrentRateLimiter.withLimit {
            setCookie()
            var headers = headerMap
            headers["Content-Type"] = "multipart/form-data; boundary=\(boundary)"
            let request = HttpRequest(
                url: urlNoQuery,
                method: "POST",
                headers: headers,
                body: payload,
                readTimeout: readTimeout,
                callTimeout: max(60, readTimeout * 2),
                proxy: proxy
            )
            let response = try await dependencies.httpClient.send(request)
            saveCookie(response)
            return response
        }
    }

    // MARK: - Scripts

    /// Evaluate a script — upstream `evalJS`.
    @discardableResult
    public func evalJS(_ jsString: String, result: RuleValue? = nil) throws -> RuleValue {
        guard let engine = dependencies.scriptEngine else {
            throw AnalyzeUrlError.scriptFailed("脚本引擎不可用")
        }
        var bindings: [String: RuleValue] = [:]
        if let baseUrl { bindings["baseUrl"] = .text(baseUrl) }
        if let key { bindings["key"] = .text(key) }
        if let page { bindings["page"] = .number(Double(page)) }
        if let speakText { bindings["speakText"] = .text(speakText) }
        if let speakSpeed { bindings["speakSpeed"] = .number(Double(speakSpeed)) }
        if let bookName { bindings["book"] = .scriptObject(["name": .text(bookName)]) }
        if let chapterTitle { bindings["chapter"] = .scriptObject(["title": .text(chapterTitle)]) }
        if let result { bindings["result"] = result }
        return try engine.evaluate(jsString, bindings: bindings)
    }

    // MARK: - Helpers

    /// The range of the trailing option block.
    static func firstOptionBlockRange(in text: String) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: paramPattern) else { return nil }
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return match.range
    }

    /// Parse the option block — upstream `UrlOption`.
    static func parseOption(_ json: String) -> UrlOption? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return UrlOption(dictionary: object)
    }

    /// The option block embedded in a URL — upstream
    /// `AnalyzeUrl.paramPattern` + `GSON.fromJsonObject`.
    ///
    /// The upstream reads the origin of the source out of it to find the
    /// source of a book url (`AddToBookshelfDialog`).
    public static func option(of url: String) -> UrlOption? {
        guard let range = firstOptionBlockRange(in: url) else { return nil }
        let ns = url as NSString
        let start = range.location + range.length
        guard start <= ns.length else { return nil }
        return parseOption(ns.substring(from: start))
    }

    static func percentEncodeQuery(_ value: String) -> String {
        var output = ""
        for byte in Array(value.utf8) {
            let character = Character(UnicodeScalar(byte))
            if character.isLetter || character.isNumber || "!$&()*+,-./:;=?@[]^_`{|}~".contains(character) {
                output.append(character)
            } else if character == " " {
                output.append("+")
            } else {
                output.append(String(format: "%%%02X", byte))
            }
        }
        return output
    }

    static func percentEncodeForm(_ value: String) -> String {
        var output = ""
        for byte in Array(value.utf8) {
            let character = Character(UnicodeScalar(byte))
            if character.isLetter || character.isNumber || "*-._".contains(character) {
                output.append(character)
            } else if character == " " {
                output.append("+")
            } else {
                output.append(String(format: "%%%02X", byte))
            }
        }
        return output
    }

    /// The upstream `EncoderUtils.escape`.
    static func escape(_ value: String) -> String {
        var output = ""
        for character in value {
            if character.isLetter || character.isNumber || "@*_+-./".contains(character) {
                output.append(character)
            } else if let ascii = character.asciiValue, ascii > 0x7F {
                output.append(String(format: "%%%02X", ascii))
            } else {
                output.append(String(format: "%%%02X", character.asciiValue ?? 0))
            }
        }
        return output
    }
}

/// The trailing option block of a URL rule — upstream `UrlOption`.
public struct UrlOption {
    public var method: String?
    public var charset: String?
    public var headers: [String: String]?
    public var body: String?
    public var origin: String?
    public var retry: Int?
    public var type: String?
    public var useWebView: Bool
    public var webJs: String?
    public var js: String?
    public var serverID: Int64?
    public var webViewDelayTime: Int64?

    /// The charsets of the URL option — upstream `AppConst.charsets`.
    public static let charsets = [
        "UTF-8", "GB2312", "GB18030", "GBK", "Unicode", "UTF-16", "UTF-16LE", "ASCII"
    ]

    public init(
        method: String? = nil,
        charset: String? = nil,
        headers: [String: String]? = nil,
        body: String? = nil,
        origin: String? = nil,
        retry: Int? = nil,
        type: String? = nil,
        useWebView: Bool = false,
        webJs: String? = nil,
        js: String? = nil,
        serverID: Int64? = nil,
        webViewDelayTime: Int64? = nil
    ) {
        self.method = method
        self.charset = charset
        self.headers = headers
        self.body = body
        self.origin = origin
        self.retry = retry
        self.type = type
        self.useWebView = useWebView
        self.webJs = webJs
        self.js = js
        self.serverID = serverID
        self.webViewDelayTime = webViewDelayTime
    }

    /// The JSON of the option block — the upstream `GSON.toJson(urlOption)`.
    /// The null fields are omitted, exactly like GSON does, and the fields
    /// keep the order of the upstream's data class.
    public func jsonString() -> String {
        var parts: [String] = []
        if let method, !method.isEmpty {
            parts.append("\"method\":\"\(UrlOption.escape(method))\"")
        }
        if let charset, !charset.isEmpty {
            parts.append("\"charset\":\"\(UrlOption.escape(charset))\"")
        }
        if let headers, !headers.isEmpty {
            let items = headers.keys.sorted().map { key in
                "\"\(UrlOption.escape(key))\":\"\(UrlOption.escape(headers[key] ?? ""))\""
            }
            parts.append("\"headers\":{\(items.joined(separator: ","))}")
        }
        if let body, !body.isEmpty {
            parts.append("\"body\":\"\(UrlOption.escape(body))\"")
        }
        if let origin, !origin.isEmpty {
            parts.append("\"origin\":\"\(UrlOption.escape(origin))\"")
        }
        if let retry {
            parts.append("\"retry\":\(retry)")
        }
        if let type, !type.isEmpty {
            parts.append("\"type\":\"\(UrlOption.escape(type))\"")
        }
        if useWebView {
            // Upstream `useWebView(false)` stores null, so the field is only
            // written when it is on.
            parts.append("\"webView\":true")
        }
        if let webJs, !webJs.isEmpty {
            parts.append("\"webJs\":\"\(UrlOption.escape(webJs))\"")
        }
        if let js, !js.isEmpty {
            parts.append("\"js\":\"\(UrlOption.escape(js))\"")
        }
        if let serverID {
            parts.append("\"serverID\":\(serverID)")
        }
        if let webViewDelayTime {
            parts.append("\"webViewDelayTime\":\(webViewDelayTime)")
        }
        return "{\(parts.joined(separator: ","))}"
    }

    /// Escapes a string for a JSON literal.
    static func escape(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default: out.append(character)
            }
        }
        return out
    }

    init(dictionary: [String: Any]) {
        method = UrlOption.string(dictionary["method"])
        charset = UrlOption.string(dictionary["charset"])
        body = UrlOption.body(dictionary["body"])
        origin = UrlOption.string(dictionary["origin"])
        js = UrlOption.string(dictionary["js"])
        webJs = UrlOption.string(dictionary["webJs"])
        type = UrlOption.string(dictionary["type"])
        if let raw = dictionary["retry"] as? NSNumber {
            retry = raw.intValue
        } else if let text = UrlOption.string(dictionary["retry"]) {
            retry = Int(text)
        }
        if let raw = dictionary["serverID"] as? NSNumber {
            serverID = raw.int64Value
        } else if let text = UrlOption.string(dictionary["serverID"]) {
            serverID = Int64(text)
        }
        if let raw = dictionary["webViewDelayTime"] as? NSNumber {
            webViewDelayTime = raw.int64Value
        } else if let text = UrlOption.string(dictionary["webViewDelayTime"]) {
            webViewDelayTime = Int64(text)
        }
        useWebView = UrlOption.boolean(dictionary["webView"])
        if let raw = dictionary["headers"] as? [String: Any] {
            var map: [String: String] = [:]
            for (key, value) in raw {
                if let string = value as? String {
                    map[key] = string
                } else if let number = value as? NSNumber {
                    map[key] = number.stringValue
                } else {
                    map[key] = "\(value)"
                }
            }
            headers = map
        }
    }

    private static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    /// The body of the option block — upstream `UrlOption.setBody` /
    /// `UrlOption.getBody`.
    ///
    /// A JSON object or an array is re-serialized (the upstream keeps it as a
    /// map and `getBody` writes it back as JSON); a plain string is kept.
    private static func body(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
                // The upstream parses a JSON body into a map and writes it
                // back as JSON.
                if let parsed = try? JSONValue.parse(trimmed) {
                    return parsed.jsonString
                }
            }
            return trimmed
        }
        if value is [String: Any] || value is [Any] {
            // `JSONSerialization` needs a valid object; the option block is
            // already parsed from JSON.
            if let data = try? JSONSerialization.data(withJSONObject: value),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
        }
        return nil
    }

    private static func boolean(_ value: Any?) -> Bool {
        guard let value else { return false }
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            let lowered = string.lowercased()
            return !(lowered.isEmpty || lowered == "false")
        }
        return false
    }
}
