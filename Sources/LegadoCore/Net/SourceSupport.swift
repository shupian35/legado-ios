//
//  SourceSupport.swift
//  LegadoCore
//
//  The port of the parts of app/src/main/java/io/legado/app/data/entities/BaseSource.kt
//  that the network layer needs.
//

import Foundation

/// The parts of the upstream `BaseSource` the network layer needs.
///
/// Upstream `AnalyzeUrl` takes a `BaseSource?`, which both `BookSource` and
/// `RssSource` implement. The port spells that out as a protocol so the URL
/// layer works for RSS too.
public protocol AnalyzeSource {
    /// Upstream `BaseSource.getKey()`.
    var key: String { get }
    /// Upstream `BaseSource.concurrentRate`.
    var concurrentRate: String? { get }
    /// Upstream `BaseSource.enabledCookieJar`.
    var enabledCookieJar: Bool { get }

    /// The parsed header map — upstream `BaseSource.getHeaderMap`.
    func headerMap(
        hasLoginHeader: Bool,
        scriptEngine: RuleScriptEngine?,
        userAgent: String,
        loginHeaderMap: [String: String]?
    ) -> [String: String]
}

extension BookSource: AnalyzeSource {
    /// The unique key of the source — upstream `BaseSource.getKey()`.
    public var key: String { bookSourceUrl }

    /// The tag of the source — upstream `BaseSource.getTag()`.
    public var tag: String { bookSourceUrl }

    /// Parse the header rule — upstream `BaseSource.getHeaderMap`.
    ///
    /// - Parameters:
    ///   - hasLoginHeader: also merge the login header.
    ///   - scriptEngine: used when the header rule is a script.
    ///   - userAgent: the fallback `User-Agent`.
    ///   - loginHeaderMap: the stored login header.
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

extension RssSource: AnalyzeSource {
    /// The unique key of the source — upstream `BaseSource.getKey()`.
    public var key: String { sourceUrl }

    /// The tag of the source — upstream `BaseSource.getTag()`.
    public var tag: String { sourceUrl }

    /// Parse the header rule — upstream `BaseSource.getHeaderMap`.
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

public enum SourceSupport {
    public static let userAgentName = "User-Agent"

    /// The default `User-Agent` of the app — upstream `AppConfig.userAgent`.
    public static var defaultUserAgent = "Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36"

    /// The shared header parsing of `BaseSource.getHeaderMap`.
    public static func headerMap(
        header: String?,
        hasLoginHeader: Bool,
        scriptEngine: RuleScriptEngine?,
        userAgent: String,
        loginHeaderMap: [String: String]?
    ) -> [String: String] {
        var map: [String: String] = [:]
        if let header, !header.isEmpty {
            var json = header
            if header.lowercased().hasPrefix("@js:") {
                json = (try? scriptEngine?.evaluate(String(header.dropFirst(4)), bindings: [:]))?
                    .textValue ?? ""
            } else if header.lowercased().hasPrefix("<js>") {
                let end = header.lastIndex(of: "<") ?? header.endIndex
                let body = String(header[header.index(header.startIndex, offsetBy: 4)..<end])
                json = (try? scriptEngine?.evaluate(body, bindings: [:]))?.textValue ?? ""
            }
            if let parsed = parseStringMap(json) {
                map.merge(parsed) { _, new in new }
            }
        }
        if !map.keys.contains(where: { $0.lowercased() == userAgentName.lowercased() }) {
            map[userAgentName] = userAgent
        }
        if hasLoginHeader, let loginHeaderMap {
            map.merge(loginHeaderMap) { _, new in new }
        }
        return map
    }

    /// Parse a JSON object of string values — the port of `GSON.fromJsonObject<Map<String, String>>`.
    public static func parseStringMap(_ json: String) -> [String: String]? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var map: [String: String] = [:]
        for (key, value) in object {
            if let string = value as? String {
                map[key] = string
            } else if let number = value as? NSNumber {
                map[key] = number.stringValue
            } else if value is NSNull {
                continue
            } else {
                map[key] = "\(value)"
            }
        }
        return map
    }
}
