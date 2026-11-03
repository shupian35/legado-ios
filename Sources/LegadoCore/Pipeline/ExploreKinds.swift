//
//  ExploreKinds.swift
//  LegadoCore
//
//  The explore categories of a book source.
//
//  Upstream `help/source/BookSourceExtensions.kt:41-89` (`exploreKinds()`):
//
//  * the `exploreUrl` field holds the rule; when it starts with `<js>` or
//    `@js:` the rule is the result of that script (the upstream caches it);
//  * when the rule is a JSON ARRAY it is parsed as a list of `ExploreKind`
//    objects (`{"title": …, "url": …}`);
//  * otherwise the rule is a list of `分类::网址` pairs separated by the
//    regular expression `(&&|\n)+`.
//
//  The port keeps the exact parsing so that a source written for the Android
//  app offers the same categories.
//

import Foundation

/// The parser of the explore categories.
public enum ExploreKinds {

    /// Parses the explore categories of a source.
    ///
    /// - Parameter exploreUrl: the `exploreUrl` field of the source.
    public static func parse(_ exploreUrl: String?) -> [ExploreKind] {
        guard let exploreUrl, !exploreUrl.isBlank else { return [] }
        let rule = exploreUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = try? JSONValue.parse(rule), case .array(let items) = value {
            return items.compactMap { item in
                guard case .object(let members) = item else { return nil }
                let title = members["title"]?.textValue ?? ""
                let url = members["url"]?.textValue
                return ExploreKind(title: title, url: url)
            }
        }
        // The plain "分类::网址" list, separated by "(&&|\n)+".
        return split(separatorPattern: "(&&|\n)+", in: rule).map { part in
            let fields = part.components(separatedBy: "::")
            let title = fields.first ?? ""
            let url = fields.count > 1 ? fields[1] : nil
            return ExploreKind(title: title, url: url)
        }
    }

    /// Splits a string on a regular expression (the upstream
    /// `split("(&&|\n)+".toRegex())`).
    private static func split(separatorPattern: String, in text: String) -> [String] {
        guard let separator = try? NSRegularExpression(pattern: separatorPattern) else {
            return [text]
        }
        var parts: [String] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\n" {
                parts.append(current)
                current = ""
                index = text.index(after: index)
                continue
            }
            if character == "&",
               text.index(after: index) < text.endIndex,
               text[text.index(after: index)] == "&" {
                parts.append(current)
                current = ""
                index = text.index(index, offsetBy: 2)
                continue
            }
            current.append(character)
            index = text.index(after: index)
        }
        parts.append(current)
        // The upstream drops the empty parts.
        return parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}
