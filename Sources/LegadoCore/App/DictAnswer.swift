//
//  DictAnswer.swift
//  LegadoCore
//
//  The answer of a dictionary rule — upstream
//  `app/src/main/java/io/legado/app/ui/dict/DictDialog.kt:65`
//  (`binding.tvDict.setHtml(it)`).
//
//  The answer of a rule is an HTML document (the body of the request when
//  the rule has no show rule); the upstream shows it in a `TextView` that
//  renders the HTML. The port renders it in a web view on the Apple
//  platforms; this helper prepares the HTML and decides whether the answer
//  is a document or plain text.
//

import Foundation

/// The HTML of the answer of a dictionary rule.
public enum DictAnswer {

    /// The pattern of an HTML tag — `<div>`, `</div>`, `<br/>`, …
    private static let tagPattern = try? NSRegularExpression(
        pattern: "<\\s*/?\\s*[a-zA-Z][^>]*>",
        options: []
    )

    /// Whether the answer is an HTML document — the upstream shows the
    /// answer with `setHtml`, so a document and a plain text are both
    /// possible.
    public static func isHTML(_ text: String) -> Bool {
        guard let tagPattern else { return false }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return tagPattern.firstMatch(in: text, options: [], range: range) != nil
    }

    /// The HTML of the answer — upstream `tvDict.setHtml(it)`.
    ///
    /// An HTML document is used as it is; a plain text is escaped and its
    /// line breaks become `<br>` so that the lines stay apart (the upstream
    /// `TextView` keeps the line breaks of a plain text).
    public static func html(_ text: String) -> String {
        if isHTML(text) { return text }
        return escape(text).replacingOccurrences(of: "\n", with: "<br>\n")
    }

    /// The escaped text — the five XML entities.
    public static func escape(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }
}
