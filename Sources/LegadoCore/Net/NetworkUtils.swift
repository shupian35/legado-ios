//
//  NetworkUtils.swift
//  LegadoCore
//
//  URL helpers — the port of the parts of
//  app/src/main/java/io/legado/app/utils/NetworkUtils.kt the rule engine needs.
//

import Foundation

public enum NetworkUtils {

    // MARK: - Absolute URLs

    /// `true` when the string is an absolute http(s) URL.
    public static func isAbsUrl(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// `true` when the string is a `data:` URL.
    public static func isDataUrl(_ url: String) -> Bool {
        url.lowercased().hasPrefix("data:")
    }

    /// The absolute URL of `relativePath` — upstream `getAbsoluteURL`.
    ///
    /// The upstream implementation uses `java.net.URL(base, relative)`, which
    /// resolves a relative path against the *directory* of the base URL.
    public static func absoluteURL(base: String?, _ relativePath: String) -> String {
        let trimmedBase = (base ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedBase.isEmpty { return relativePath.trimmingCharacters(in: .whitespacesAndNewlines) }
        // The upstream strips an option block before parsing the base URL.
        let baseOnly = trimmedBase.components(separatedBy: ",").first ?? trimmedBase
        guard let baseURL = URL(string: baseOnly) else {
            return relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return absoluteURL(baseURL: baseURL, relativePath)
    }

    /// The absolute URL of `relativePath` — upstream `getAbsoluteURL(URL?, String)`.
    ///
    /// `URL(string:relativeTo:)` is avoided on purpose: it is unreliable in
    /// swift-corelibs-foundation, so the `java.net.URL(base, relative)`
    /// semantics are implemented directly.
    public static func absoluteURL(baseURL: URL?, _ relativePath: String) -> String {
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = baseURL else { return trimmed }
        if isAbsUrl(trimmed) { return trimmed }
        if isDataUrl(trimmed) { return trimmed }
        if trimmed.lowercased().hasPrefix("javascript") { return "" }
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: true) else { return trimmed }
        var relPath = trimmed
        var query: String?
        var fragment: String?
        if let hashIndex = relPath.firstIndex(of: "#") {
            fragment = String(relPath[relPath.index(after: hashIndex)...])
            relPath = String(relPath[..<hashIndex])
        }
        if let questionIndex = relPath.firstIndex(of: "?") {
            query = String(relPath[relPath.index(after: questionIndex)...])
            relPath = String(relPath[..<questionIndex])
        }
        let basePath = components.path
        let directory: String
        if let slashIndex = basePath.lastIndex(of: "/") {
            directory = String(basePath[basePath.startIndex...slashIndex])
        } else {
            directory = "/"
        }
        let combined = relPath.hasPrefix("/") ? relPath : directory + relPath
        components.path = foldPath(combined)
        components.query = query
        components.fragment = fragment
        return components.string ?? trimmed
    }

    /// Folds the "." and ".." segments of a URL path.
    public static func foldPath(_ path: String) -> String {
        let isAbsolute = path.hasPrefix("/")
        let segments = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var stack: [String] = []
        for segment in segments {
            switch segment {
            case "", ".":
                continue
            case "..":
                if !stack.isEmpty { stack.removeLast() }
            default:
                stack.append(segment)
            }
        }
        let joined = stack.joined(separator: "/")
        if isAbsolute { return "/" + joined }
        return joined.isEmpty ? "." : joined
    }

    /// The scheme + host of a URL — upstream `getBaseUrl`.
    public static func baseUrl(_ url: String?) -> String? {
        guard let url else { return nil }
        let lower = url.lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return nil }
        guard let index = url.dropFirst(9).firstIndex(of: "/") else { return url }
        return String(url[url.startIndex..<index])
    }

    /// The registrable domain of a URL — upstream `getSubDomain`.
    ///
    /// The upstream uses the PublicSuffixDatabase; the port falls back to a
    /// label heuristic, which covers the common cases.
    public static func subDomain(_ url: String) -> String {
        guard let base = baseUrl(url) else { return url }
        guard let host = URL(string: base)?.host else { return base }
        if isIPAddress(host) { return host }
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count > 2 else { return host }
        // A two letter top level domain means the public suffix has three
        // labels, e.g. "biquge.com.cn".
        if labels[labels.count - 1].count == 2 {
            return labels[(labels.count - 3)...].joined(separator: ".")
        }
        return labels[(labels.count - 2)...].joined(separator: ".")
    }

    /// `true` when the host is an IPv4 or IPv6 address.
    public static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        for part in parts {
            guard let value = Int(part), (0...255).contains(value), part.count <= 3 else { return false }
        }
        return true
    }

    // MARK: - Encoding

    private static let notNeedEncodingQuery: Set<Character> = {
        var set = Set<Character>("abcdefghijklmnopqrstuvwxyz")
        set.formUnion("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        set.formUnion("0123456789")
        set.formUnion("!$&()*+,-./:;=?@[\\]^_`{|}~")
        return set
    }()

    private static let notNeedEncodingForm: Set<Character> = {
        var set = Set<Character>("abcdefghijklmnopqrstuvwxyz")
        set.formUnion("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        set.formUnion("0123456789")
        set.formUnion("*-._")
        return set
    }()

    /// `true` when the string is already url encoded — upstream `encodedQuery`.
    public static func encodedQuery(_ str: String) -> Bool {
        return isEncoded(str, allowed: notNeedEncodingQuery)
    }

    /// `true` when the string is already url encoded — upstream `encodedForm`.
    public static func encodedForm(_ str: String) -> Bool {
        return isEncoded(str, allowed: notNeedEncodingForm)
    }

    private static func isEncoded(_ str: String, allowed: Set<Character>) -> Bool {
        let chars = Array(str)
        var index = 0
        while index < chars.count {
            let character = chars[index]
            if allowed.contains(character) {
                index += 1
                continue
            }
            if character == "%", index + 2 < chars.count {
                let first = chars[index + 1]
                let second = chars[index + 2]
                if isHexDigit(first), isHexDigit(second) {
                    index += 3
                    continue
                }
            }
            return false
        }
        return true
    }

    private static func isHexDigit(_ character: Character) -> Bool {
        return character.isHexDigit
    }
}
