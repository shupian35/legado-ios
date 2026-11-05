//
//  HttpTTSManager.swift
//  LegadoCore
//
//  The management of the HTTP text-to-speech engines.
//
//  Upstream source of truth:
//  app/src/main/java/io/legado/app/data/entities/HttpTTS.kt
//  app/src/main/java/io/legado/app/ui/book/read/config/SpeakEngineDialog.kt
//  app/src/main/java/io/legado/app/ui/book/read/config/HttpTtsEditDialog.kt
//  app/src/main/java/io/legado/app/ui/association/ImportHttpTtsDialog.kt
//

import Foundation

/// The errors of the HTTP TTS import.
public enum HttpTTSImportError: Error, Equatable, LocalizedError {
    /// The document is not valid JSON.
    case invalidJSON
    /// The engine has no name.
    case missingName
    /// The engine has no address.
    case missingURL

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: return "不是有效的 JSON"
        case .missingName: return "缺少名称"
        case .missingURL: return "缺少地址"
        }
    }
}

/// The HTTP TTS engines — upstream `HttpTTS` + `SpeakEngineDialog`.
public enum HttpTTSManager {
    /// The cache key of an engine — upstream `HttpTTS.getKey()`.
    ///
    /// The login information and the login header of an engine are stored
    /// under this key (`BaseSource.putLoginInfo`).
    public static func key(for id: Int64) -> String {
        "httpTts:\(id)"
    }

    /// Parses the engines of a JSON document — upstream `HttpTTS.fromJson`
    /// (one object) and `HttpTTS.fromJsonArray` (an array).
    public static func parse(_ text: String) throws -> [HttpTTS] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw HttpTTSImportError.invalidJSON }
        guard let value = try? JSONValue.parse(trimmed) else {
            throw HttpTTSImportError.invalidJSON
        }
        switch value {
        case .array(let items):
            return try items.map { try engine(from: $0) }
        default:
            return [try engine(from: value)]
        }
    }

    /// Reads one engine of a JSON value — upstream `HttpTTS.fromJsonDoc`.
    ///
    /// The upstream reads the fields with JSONPath and requires the name and
    /// the address; the `loginUi` is stored as a JSON array.
    public static func engine(from value: JSONValue) throws -> HttpTTS {
        guard case .object(let members) = value else {
            throw HttpTTSImportError.invalidJSON
        }
        guard let name = members["name"]?.textValue, !name.isEmpty else {
            throw HttpTTSImportError.missingName
        }
        guard let url = members["url"]?.textValue, !url.isEmpty else {
            throw HttpTTSImportError.missingURL
        }
        var engine = HttpTTS(id: 0, name: name, url: url)
        if let id = members["id"]?.intValue { engine.id = id }
        engine.contentType = members["contentType"]?.textValue
        engine.concurrentRate = members["concurrentRate"]?.textValue
        engine.loginUrl = members["loginUrl"]?.textValue
        engine.loginCheckJs = members["loginCheckJs"]?.textValue
        engine.header = members["header"]?.textValue
        engine.jsLib = members["jsLib"]?.textValue
        engine.enabledCookieJar = members["enabledCookieJar"]?.boolValue ?? false
        if let lastUpdateTime = members["lastUpdateTime"]?.intValue {
            engine.lastUpdateTime = lastUpdateTime
        }
        // Upstream: a list is stored as a JSON text, everything else as its
        // own string.
        if let loginUi = members["loginUi"] {
            if case .array = loginUi {
                engine.loginUi = loginUi.jsonString
            } else {
                engine.loginUi = loginUi.textValue
            }
        }
        return engine
    }

    /// The export document — upstream `GSON.toJson(adapter.getItems())`.
    ///
    /// The upstream writes it as the file `httpTts.json`.
    public static func exportJSON(_ engines: [HttpTTS]) -> String {
        JSONValue.array(engines.map { engine in
            var members: [String: JSONValue] = [
                "id": .number(Double(engine.id)),
                "name": .string(engine.name),
                "url": .string(engine.url),
                "enabledCookieJar": .bool(engine.enabledCookieJar),
                "lastUpdateTime": .number(Double(engine.lastUpdateTime))
            ]
            if let contentType = engine.contentType { members["contentType"] = .string(contentType) }
            if let concurrentRate = engine.concurrentRate { members["concurrentRate"] = .string(concurrentRate) }
            if let loginUrl = engine.loginUrl { members["loginUrl"] = .string(loginUrl) }
            if let loginUi = engine.loginUi { members["loginUi"] = .string(loginUi) }
            if let loginCheckJs = engine.loginCheckJs { members["loginCheckJs"] = .string(loginCheckJs) }
            if let header = engine.header { members["header"] = .string(header) }
            if let jsLib = engine.jsLib { members["jsLib"] = .string(jsLib) }
            return .object(members)
        }).jsonString
    }

    /// The export file name — upstream `HandleFileContract.FileData`.
    public static let exportFileName = "httpTts.json"

    /// The stored login information of an engine — upstream
    /// `BaseSource.getLoginInfoMap()`.
    public static func loginInfo(
        of engine: HttpTTS,
        loginService: SourceLoginService
    ) -> [String: String]? {
        try? loginService.loginInfo(for: key(for: engine.id))
    }

    /// Whether the engine still has to be logged in — upstream
    /// `!httpTTS.loginUrl.isNullOrBlank() && httpTTS.getLoginInfo().isNullOrBlank()`.
    public static func needsLogin(
        _ engine: HttpTTS,
        loginService: SourceLoginService
    ) -> Bool {
        guard let loginUrl = engine.loginUrl, !loginUrl.isEmpty else { return false }
        guard let info = loginInfo(of: engine, loginService: loginService) else { return true }
        return info.isEmpty
    }
}

// MARK: - The login support

extension HttpTTS: AnalyzeSource {

    /// The unique key of the engine — upstream `HttpTTS.getKey()`.
    public var key: String { HttpTTSManager.key(for: id) }

    /// The tag of the engine — upstream `HttpTTS.getTag()` (its name).
    public var tag: String { name }

    /// The parsed header map — upstream `BaseSource.getHeaderMap`.
    ///
    /// The header of a HTTP TTS engine is a JSON object of request headers;
    /// a script rule (`@js:` / `<js>`) is evaluated, the login header is
    /// merged into it and a default `User-Agent` is added when there is none.
    public func headerMap(
        hasLoginHeader: Bool = false,
        scriptEngine: RuleScriptEngine? = nil,
        userAgent: String = SourceSupport.defaultUserAgent,
        loginHeaderMap: [String: String]? = nil
    ) -> [String: String] {
        SourceSupport.headerMap(
            header: header,
            hasLoginHeader: hasLoginHeader,
            scriptEngine: scriptEngine,
            userAgent: userAgent,
            loginHeaderMap: loginHeaderMap
        )
    }
}

extension HttpTTS: LoginCapable {}
