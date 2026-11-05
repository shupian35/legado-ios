//
//  DeepLink.swift
//  LegadoCore
//
//  The port of
//  app/src/main/java/io/legado/app/ui/association/OnLineImportActivity.kt,
//  OnLineImportViewModel.kt and BaseAssociationViewModel.kt.
//
//  Upstream the Android app registers itself for the `legado://` scheme and
//  for the `application/json` / `text/plain` mime types, so a book source (or
//  an RSS source, a replace rule, an HTTP-TTS rule, a dictionary rule, a TXT
//  TOC rule or a theme) can be imported from a browser, a message or a file.
//
//  The URL format is `legado://import/{path}?src={url}`.
//

import Foundation

// MARK: - The kinds of import

/// The kind of object a deep link imports.
///
/// Upstream the kind is detected from the JSON keys
/// (`BaseAssociationViewModel.importJson`).
public enum ImportKind: String, Equatable, CaseIterable, Sendable {
    case bookSource
    case rssSource
    case replaceRule
    case theme
    case dictRule
    case txtRule
    case httpTts
}

// MARK: - The parsed request

/// A parsed `legado://` link.
public struct DeepLinkRequest: Equatable, Sendable {
    /// The path of the link (`/bookSource`, `/rssSource`, …).
    public var path: String
    /// The host of the link — `import` for the documented format, but the
    /// upstream activity also accepts `legado://importonline/…` where the host
    /// selects the kind.
    public var host: String?
    /// The `src` parameter — the URL the data is downloaded from.
    public var source: String

    public init(path: String, host: String?, source: String) {
        self.path = path
        self.host = host
        self.source = source
    }
}

// MARK: - The shortcuts of the home screen

/// The shortcuts of the home screen.
///
/// Upstream `api/ShortCuts.kt` publishes three dynamic shortcuts: the book
/// that was read last, the read aloud of that book and the bookshelf.
public enum ShortcutAction: String, Equatable, CaseIterable, Sendable {
    /// The bookshelf — upstream `buildBookShelfShortCutInfo`.
    case bookshelf
    /// The book that was read last — upstream `buildReadBookShortCutInfo`.
    case lastRead
    /// The read aloud of the book that was read last — upstream
    /// `buildReadAloudShortCutInfo`.
    case readAloud
}

// MARK: - The errors

public enum DeepLinkError: Error, Equatable {
    case wrongScheme(String)
    case missingSource
    case unsupportedPath(String)
    case unknownFormat
    case downloadFailed(String)
    case unsupportedKind(ImportKind)
    case invalidData(ImportKind)
}

// MARK: - The result

/// The result of an import.
public struct ImportSummary: Equatable, Sendable {
    /// What was imported.
    public var kind: ImportKind
    /// How many rows were written.
    public var count: Int
    /// The name of the first imported object (upstream shows it in the dialog).
    public var name: String?

    public init(kind: ImportKind, count: Int, name: String? = nil) {
        self.kind = kind
        self.count = count
        self.name = name
    }
}

// MARK: - The deep link

/// The `legado://` handler.
public enum DeepLink {

    /// The URL scheme upstream registers.
    public static let scheme = "legado"

    /// The schemes upstream registers.
    ///
    /// Upstream `AndroidManifest.xml:337-352` registers the `OnLineImportActivity`
    /// for the schemes `legado` AND `yuedu` — the second one is an alias of the
    /// first one.
    public static let schemes = ["legado", "yuedu"]

    /// The marker upstream uses to send a request without the user agent.
    public static let requestWithoutUserAgent = "#requestWithoutUA"

    /// The shortcut a link selects, or `nil` when the link is not a shortcut.
    ///
    /// The shortcuts of the home screen open the app with a link of the form
    /// `legado://shortcut/{name}`; upstream they are the intents of
    /// `api/ShortCuts.kt`.
    public static func shortcut(from url: URL) -> ShortcutAction? {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else {
            return nil
        }
        guard url.host?.lowercased() == "shortcut" else { return nil }
        let name = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return ShortcutAction(rawValue: name)
    }

    /// Parses a `legado://` link.
    ///
    /// - Parameter url: the link, e.g. `legado://import/bookSource?src=https://…`.
    /// - Throws: `DeepLinkError.wrongScheme` when the scheme is neither
    ///   `legado` nor `yuedu` and `DeepLinkError.missingSource` when the `src`
    ///   parameter is absent.
    public static func parse(_ url: URL) throws -> DeepLinkRequest {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else {
            throw DeepLinkError.wrongScheme(url.scheme ?? "")
        }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let source = components?.queryItems?.first { $0.name == "src" }?.value ?? ""
        guard !source.isEmpty else {
            throw DeepLinkError.missingSource
        }
        return DeepLinkRequest(
            path: url.path.isEmpty ? "/" : url.path,
            host: url.host,
            source: source
        )
    }

    /// Detects the kind of an import from the JSON, like upstream's
    /// `importJson`.
    ///
    /// The document is either an array (the first element is inspected) or a
    /// single object.
    public static func detectKind(json: String) throws -> ImportKind {
        let value: JSONValue
        do {
            value = try JSONValue.parse(json)
        } catch {
            throw DeepLinkError.unknownFormat
        }
        let object: JSONValue
        switch value {
        case .array(let items):
            guard let first = items.first else {
                throw DeepLinkError.unknownFormat
            }
            object = first
        case .object:
            object = value
        default:
            throw DeepLinkError.unknownFormat
        }
        guard case .object(let fields) = object else {
            throw DeepLinkError.unknownFormat
        }
        // The order is the upstream order — the first matching key wins.
        if fields["bookSourceUrl"] != nil { return .bookSource }
        if fields["sourceUrl"] != nil { return .rssSource }
        if fields["pattern"] != nil { return .replaceRule }
        if fields["themeName"] != nil { return .theme }
        if fields["showRule"] != nil { return .dictRule }
        if fields["name"] != nil && fields["rule"] != nil { return .txtRule }
        if fields["name"] != nil && fields["url"] != nil { return .httpTts }
        throw DeepLinkError.unknownFormat
    }

    /// The kind a link path selects, or `nil` when the path only says
    /// "import online" (upstream `/importonline`).
    public static func kind(forPath path: String, host: String?) -> ImportKind? {
        switch path {
        case "/bookSource": return .bookSource
        case "/rssSource": return .rssSource
        case "/replaceRule": return .replaceRule
        case "/textTocRule": return .txtRule
        case "/httpTTS": return .httpTts
        case "/dictRule": return .dictRule
        case "/theme": return .theme
        default: break
        }
        // `legado://importonline/booksource?src=…`
        if path == "/importonline" || path == "/" {
            switch host {
            case "booksource": return .bookSource
            case "rsssource": return .rssSource
            case "replace": return .replaceRule
            default: return nil
            }
        }
        return nil
    }

    /// Downloads the data of a link and imports it.
    ///
    /// - Parameters:
    ///   - request: the parsed link.
    ///   - httpClient: the transport.
    ///   - store: the database the objects are written to.
    ///   - userAgent: the user agent header; upstream sends the literal
    ///     string `null` when the link ends with `#requestWithoutUA`.
    public static func importData(
        from request: DeepLinkRequest,
        httpClient: HttpClient,
        store: LegadoStore,
        userAgent: String = AppSettings.defaultUserAgent
    ) async throws -> ImportSummary {
        var url = request.source
        var headers: [String: String] = [:]
        if url.hasSuffix(requestWithoutUserAgent) {
            url = String(url.dropLast(requestWithoutUserAgent.count))
            headers["User-Agent"] = "null"
        } else {
            headers["User-Agent"] = userAgent
        }
        let response = try await httpClient.send(HttpRequest(url: url, headers: headers))
        guard response.isSuccessful else {
            throw DeepLinkError.downloadFailed("HTTP \(response.code)")
        }
        guard let text = response.body ?? (response.data.map { String(decoding: $0, as: UTF8.self) }) else {
            throw DeepLinkError.downloadFailed("空的响应")
        }
        let kind = try kind(forPath: request.path, host: request.host) ?? detectKind(json: text)
        return try importJSON(text, kind: kind, store: store)
    }

    /// Imports a JSON document of a known kind.
    public static func importJSON(_ json: String, kind: ImportKind, store: LegadoStore) throws -> ImportSummary {
        switch kind {
        case .bookSource:
            let sources = try decodeArray(json) { BookSourceJSONBridge.decode($0) }
            guard !sources.isEmpty else { throw DeepLinkError.invalidData(kind) }
            for source in sources { try store.insert(source) }
            return ImportSummary(kind: kind, count: sources.count, name: sources.first?.bookSourceName)
        case .rssSource:
            let sources = try decodeArray(json) { RssSourceJSONBridge.decode($0) }
            guard !sources.isEmpty else { throw DeepLinkError.invalidData(kind) }
            for source in sources { try store.insert(source) }
            return ImportSummary(kind: kind, count: sources.count, name: sources.first?.sourceName)
        case .replaceRule:
            let rules = try decodeArray(json) { ReplaceRuleJSONBridge.decode($0) }
            guard !rules.isEmpty else { throw DeepLinkError.invalidData(kind) }
            for rule in rules { try store.insert(rule) }
            return ImportSummary(kind: kind, count: rules.count, name: rules.first?.name)
        case .httpTts:
            let rules = try decodeArray(json) { HttpTTSJSONBridge.decode($0) }
            guard !rules.isEmpty else { throw DeepLinkError.invalidData(kind) }
            for rule in rules { try store.insert(rule) }
            return ImportSummary(kind: kind, count: rules.count, name: rules.first?.name)
        case .dictRule:
            let rules = try decodeArray(json) { DictRuleJSONBridge.decode($0) }
            guard !rules.isEmpty else { throw DeepLinkError.invalidData(kind) }
            for rule in rules { try store.insert(rule) }
            return ImportSummary(kind: kind, count: rules.count, name: rules.first?.name)
        case .txtRule:
            let rules = try decodeArray(json) { TxtTocRuleJSONBridge.decode($0) }
            guard !rules.isEmpty else { throw DeepLinkError.invalidData(kind) }
            for rule in rules { try store.insert(rule) }
            return ImportSummary(kind: kind, count: rules.count, name: rules.first?.name)
        case .theme:
            // The port has no theme entity yet (the reader theme is still
            // missing), so a theme import is rejected instead of silently
            // dropped.
            throw DeepLinkError.unsupportedKind(kind)
        }
    }

    // MARK: - Helpers

    /// Decodes a JSON document that is either an array or a single object.
    private static func decodeArray<T>(
        _ json: String,
        _ decode: (JSONValue) -> T?
    ) throws -> [T] {
        let value: JSONValue
        do {
            value = try JSONValue.parse(json)
        } catch {
            throw DeepLinkError.unknownFormat
        }
        switch value {
        case .array(let items):
            return items.compactMap(decode)
        case .object:
            if let single = decode(value) { return [single] }
            return []
        default:
            throw DeepLinkError.unknownFormat
        }
    }
}

// MARK: - The JSON bridges

/// Decodes an `RssSource` from its JSON form.
public enum RssSourceJSONBridge {
    public static func decode(_ value: JSONValue) -> RssSource? {
        guard case .object(let fields) = value, let sourceUrl = fields["sourceUrl"]?.textValue else {
            return nil
        }
        var source = RssSource(sourceUrl: sourceUrl, sourceName: fields["sourceName"]?.textValue ?? "")
        source.sourceIcon = fields["sourceIcon"]?.textValue ?? ""
        source.sourceGroup = fields["sourceGroup"]?.textValue
        source.sourceComment = fields["sourceComment"]?.textValue
        source.enabled = fields["enabled"]?.boolValue ?? true
        source.variableComment = fields["variableComment"]?.textValue
        source.jsLib = fields["jsLib"]?.textValue
        source.enabledCookieJar = fields["enabledCookieJar"]?.boolValue ?? false
        source.concurrentRate = fields["concurrentRate"]?.textValue
        source.header = fields["header"]?.textValue
        source.loginUrl = fields["loginUrl"]?.textValue
        source.loginUi = fields["loginUi"]?.textValue
        source.loginCheckJs = fields["loginCheckJs"]?.textValue
        source.coverDecodeJs = fields["coverDecodeJs"]?.textValue
        source.sortUrl = fields["sortUrl"]?.textValue
        source.singleUrl = fields["singleUrl"]?.boolValue ?? false
        source.articleStyle = fields["articleStyle"]?.intValue ?? 0
        source.ruleArticles = fields["ruleArticles"]?.textValue
        source.ruleNextPage = fields["ruleNextPage"]?.textValue
        source.ruleTitle = fields["ruleTitle"]?.textValue
        source.rulePubDate = fields["rulePubDate"]?.textValue
        source.ruleDescription = fields["ruleDescription"]?.textValue
        source.ruleImage = fields["ruleImage"]?.textValue
        source.ruleLink = fields["ruleLink"]?.textValue
        source.ruleContent = fields["ruleContent"]?.textValue
        source.contentWhitelist = fields["contentWhitelist"]?.textValue
        source.contentBlacklist = fields["contentBlacklist"]?.textValue
        source.shouldOverrideUrlLoading = fields["shouldOverrideUrlLoading"]?.textValue
        source.style = fields["style"]?.textValue
        source.enableJs = fields["enableJs"]?.boolValue ?? false
        source.loadWithBaseUrl = fields["loadWithBaseUrl"]?.boolValue ?? false
        source.injectJs = fields["injectJs"]?.textValue
        source.lastUpdateTime = fields["lastUpdateTime"]?.intValue ?? 0
        source.customOrder = fields["customOrder"]?.intValue ?? 0
        return source
    }

    /// The JSON form of an RSS source (the same fields the upstream GSON
    /// serialisation produces).
    public static func encode(_ source: RssSource) -> JSONValue {
        var fields: [String: JSONValue] = [
            "sourceUrl": .string(source.sourceUrl),
            "sourceName": .string(source.sourceName),
            "enabled": .bool(source.enabled),
            "singleUrl": .bool(source.singleUrl),
            "articleStyle": .number(Double(source.articleStyle)),
            "enableJs": .bool(source.enableJs),
            "loadWithBaseUrl": .bool(source.loadWithBaseUrl),
            "enabledCookieJar": .bool(source.enabledCookieJar),
            "lastUpdateTime": .number(Double(source.lastUpdateTime)),
            "customOrder": .number(Double(source.customOrder))
        ]
        fields["sourceIcon"] = .string(source.sourceIcon ?? "")
        if let group = source.sourceGroup { fields["sourceGroup"] = .string(group) }
        if let comment = source.sourceComment { fields["sourceComment"] = .string(comment) }
        if let variableComment = source.variableComment { fields["variableComment"] = .string(variableComment) }
        if let jsLib = source.jsLib { fields["jsLib"] = .string(jsLib) }
        if let rate = source.concurrentRate { fields["concurrentRate"] = .string(rate) }
        if let header = source.header { fields["header"] = .string(header) }
        if let loginUrl = source.loginUrl { fields["loginUrl"] = .string(loginUrl) }
        if let loginUi = source.loginUi { fields["loginUi"] = .string(loginUi) }
        if let loginCheckJs = source.loginCheckJs { fields["loginCheckJs"] = .string(loginCheckJs) }
        if let coverDecodeJs = source.coverDecodeJs { fields["coverDecodeJs"] = .string(coverDecodeJs) }
        if let sortUrl = source.sortUrl { fields["sortUrl"] = .string(sortUrl) }
        if let ruleArticles = source.ruleArticles { fields["ruleArticles"] = .string(ruleArticles) }
        if let ruleNextPage = source.ruleNextPage { fields["ruleNextPage"] = .string(ruleNextPage) }
        if let ruleTitle = source.ruleTitle { fields["ruleTitle"] = .string(ruleTitle) }
        if let rulePubDate = source.rulePubDate { fields["rulePubDate"] = .string(rulePubDate) }
        if let ruleDescription = source.ruleDescription { fields["ruleDescription"] = .string(ruleDescription) }
        if let ruleImage = source.ruleImage { fields["ruleImage"] = .string(ruleImage) }
        if let ruleLink = source.ruleLink { fields["ruleLink"] = .string(ruleLink) }
        if let ruleContent = source.ruleContent { fields["ruleContent"] = .string(ruleContent) }
        if let whitelist = source.contentWhitelist { fields["contentWhitelist"] = .string(whitelist) }
        if let blacklist = source.contentBlacklist { fields["contentBlacklist"] = .string(blacklist) }
        if let override = source.shouldOverrideUrlLoading { fields["shouldOverrideUrlLoading"] = .string(override) }
        if let style = source.style { fields["style"] = .string(style) }
        if let injectJs = source.injectJs { fields["injectJs"] = .string(injectJs) }
        return .object(fields)
    }
}

/// Decodes a `ReplaceRule` from its JSON form.
public enum ReplaceRuleJSONBridge {
    public static func decode(_ value: JSONValue) -> ReplaceRule? {
        guard case .object(let fields) = value, let name = fields["name"]?.textValue else {
            return nil
        }
        var rule = ReplaceRule(
            id: fields["id"]?.intValue ?? 0,
            name: name,
            pattern: fields["pattern"]?.textValue ?? "",
            replacement: fields["replacement"]?.textValue ?? ""
        )
        rule.group = fields["group"]?.textValue
        rule.scope = fields["scope"]?.textValue
        rule.scopeTitle = fields["scopeTitle"]?.boolValue ?? false
        rule.scopeContent = fields["scopeContent"]?.boolValue ?? false
        rule.excludeScope = fields["excludeScope"]?.textValue
        rule.isEnabled = fields["isEnabled"]?.boolValue ?? true
        rule.isRegex = fields["isRegex"]?.boolValue ?? false
        rule.timeoutMillisecond = fields["timeoutMillisecond"]?.intValue ?? 0
        // Upstream `ReplaceRule.order` — the JSON field is `order` (the
        // database column is `sortOrder`). The port accepts both so that the
        // backups of the earlier versions still restore.
        rule.sortOrder = fields["order"]?.intValue ?? fields["sortOrder"]?.intValue ?? 0
        return rule
    }

    /// Encodes a `ReplaceRule` into its JSON form — the same shape the
    /// upstream API and the backup files use.
    public static func encode(_ rule: ReplaceRule) -> JSONValue {
        var fields: [String: JSONValue] = [
            "id": .number(Double(rule.id)),
            "name": .string(rule.name),
            "pattern": .string(rule.pattern),
            "replacement": .string(rule.replacement),
            "group": .string(rule.group ?? ""),
            "scope": .string(rule.scope ?? ""),
            "scopeTitle": .bool(rule.scopeTitle),
            "scopeContent": .bool(rule.scopeContent),
            "isEnabled": .bool(rule.isEnabled),
            "isRegex": .bool(rule.isRegex),
            "timeoutMillisecond": .number(Double(rule.timeoutMillisecond)),
            "order": .number(Double(rule.sortOrder))
        ]
        if let excludeScope = rule.excludeScope {
            fields["excludeScope"] = .string(excludeScope)
        }
        return .object(fields)
    }
}

/// Decodes an `HttpTTS` rule from its JSON form.
public enum HttpTTSJSONBridge {
    public static func decode(_ value: JSONValue) -> HttpTTS? {
        guard case .object(let fields) = value,
              let name = fields["name"]?.textValue,
              let url = fields["url"]?.textValue else {
            return nil
        }
        // Upstream keeps the id of the document — the default engines use the
        // negative ids (`delete from httpTTS where id < 0`).
        var rule = HttpTTS(id: fields["id"]?.intValue ?? 0, name: name, url: url)
        rule.contentType = fields["contentType"]?.textValue
        rule.concurrentRate = fields["concurrentRate"]?.textValue
        rule.loginUrl = fields["loginUrl"]?.textValue
        rule.loginUi = fields["loginUi"]?.textValue
        rule.header = fields["header"]?.textValue
        rule.jsLib = fields["jsLib"]?.textValue
        rule.enabledCookieJar = fields["enabledCookieJar"]?.boolValue ?? false
        rule.loginCheckJs = fields["loginCheckJs"]?.textValue
        rule.lastUpdateTime = fields["lastUpdateTime"]?.intValue ?? 0
        return rule
    }
}

/// Decodes a `DictRule` from its JSON form.
public enum DictRuleJSONBridge {
    public static func decode(_ value: JSONValue) -> DictRule? {
        guard case .object(let fields) = value,
              let name = fields["name"]?.textValue,
              !name.isEmpty else {
            return nil
        }
        // The upstream `DictRule` has the defaults "" for the url rule and
        // the show rule, so a document without them is still a rule.
        let urlRule = fields["urlRule"]?.textValue ?? ""
        let showRule = fields["showRule"]?.textValue ?? ""
        var rule = DictRule(name: name, urlRule: urlRule, showRule: showRule)
        rule.enabled = fields["enabled"]?.boolValue ?? true
        rule.sortNumber = fields["sortNumber"]?.intValue ?? 0
        return rule
    }
}

/// Decodes a `TxtTocRule` from its JSON form.
public enum TxtTocRuleJSONBridge {
    public static func decode(_ value: JSONValue) -> TxtTocRule? {
        guard case .object(let fields) = value,
              let name = fields["name"]?.textValue,
              let rule = fields["rule"]?.textValue else {
            return nil
        }
        // Upstream keeps the id of the document — the default rules use the
        // negative ids (`delete from txtTocRules where id < 0`).
        var tocRule = TxtTocRule(id: fields["id"]?.intValue ?? 0, name: name, rule: rule)
        tocRule.example = fields["example"]?.textValue
        tocRule.serialNumber = fields["serialNumber"]?.intValue ?? 0
        tocRule.enable = fields["enable"]?.boolValue ?? true
        return tocRule
    }
}
