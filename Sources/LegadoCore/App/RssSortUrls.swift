//
//  RssSortUrls.swift
//  LegadoCore
//
//  The sorts of an RSS source — upstream
//  `help/source/RssSourceExtensions.kt:17-56`.
//
//  The `sortUrl` field of an RSS source holds either a JavaScript snippet
//  that returns the sorts or a list of `名称::网址` pairs separated by
//  `(&&|\n)+`. The upstream shows one tab per sort in the article screen
//  (`ui/rss/article/RssSortActivity.kt`).
//

import Foundation

/// One sort of an RSS source.
public struct RssSort: Equatable, Sendable {
    /// The name of the sort (the tab title).
    public let name: String
    /// The URL of the sort (the address of the article list).
    public let url: String

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}

/// Parses the sorts of an RSS source.
public enum RssSortUrls {

    /// The separator between two sorts — upstream `(&&|\n)+`.
    public static let separatorPattern = "(&&|\n)+"

    /// Parses the sorts of the source.
    ///
    /// - Parameters:
    ///   - sortUrl: the `sortUrl` field of the source (may be a JS snippet).
    ///   - sourceUrl: the address of the source (the base of the relative
    ///     sort URLs).
    ///   - scriptEngine: evaluates the JS snippet (upstream caches the result,
    ///     the port evaluates it on demand).
    /// - Returns: the sorts; when the source has none the list holds a single
    ///   sort with the empty name and the source address.
    public static func parse(
        sortUrl: String?,
        sourceUrl: String,
        scriptEngine: RuleScriptEngine? = nil
    ) -> [RssSort] {
        var sorts: [RssSort] = []
        var raw = sortUrl ?? ""

        // A JS snippet — upstream `sortUrl.startsWith("<js>")` or "@js:".
        if raw.lowercased().hasPrefix("<js>") || raw.lowercased().hasPrefix("@js:") {
            if let scriptEngine {
                // The upstream takes `substring(4, lastIndexOf("<"))` for the
                // "<js>…</js>" form and `substring(4)` for the "@js:" form.
                let js: String
                if raw.hasPrefix("@") {
                    js = String(raw.dropFirst(4))
                } else {
                    let end = raw.lastIndex(of: "<") ?? raw.index(raw.startIndex, offsetBy: 4)
                    let start = raw.index(raw.startIndex, offsetBy: 4)
                    js = end > start ? String(raw[start..<end]) : ""
                }
                if let value = try? scriptEngine.evaluate(js, bindings: [:]) {
                    let text = value.textValue
                    if !text.isEmpty {
                        raw = text
                    }
                }
            }
        }

        for part in split(separatorPattern, in: raw) {
            let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let name = String(trimmed.prefix(while: { $0 != ":" }))
            // The upstream splits at the FIRST "::".
            guard let separatorRange = trimmed.range(of: "::") else { continue }
            let url = String(trimmed[separatorRange.upperBound...])
            guard !url.isEmpty else { continue }
            if url.hasPrefix("{{") {
                sorts.append(RssSort(name: name, url: url))
            } else {
                sorts.append(RssSort(name: name, url: NetworkUtils.absoluteURL(base: sourceUrl, url)))
            }
        }

        if sorts.isEmpty {
            sorts.append(RssSort(name: "", url: sourceUrl))
        }
        return sorts
    }

    /// Splits a string at the given regular expression.
    ///
    /// The upstream uses `split("(&&|\n)+".toRegex())`; the port splits with
    /// the same pattern but without the empty parts.
    static func split(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text.components(separatedBy: "\n")
        }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        var parts: [String] = []
        var last = 0
        for match in regex.matches(in: text, options: [], range: range) {
            let location = match.range.location
            guard location >= last else { continue }
            let piece = ns.substring(with: NSRange(location: last, length: location - last))
            if !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(piece)
            }
            last = location + match.range.length
        }
        if last < ns.length {
            let piece = ns.substring(from: last)
            if !piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(piece)
            }
        }
        return parts
    }
}
