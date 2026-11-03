//
//  TextFormat.swift
//  LegadoCore
//
//  The port of the small text helpers of the upstream app:
//  `io.legado.app.help.book.BookHelp.formatBookName/formatBookAuthor`,
//  `io.legado.app.utils.StringUtils.wordCountFormat`,
//  `io.legado.app.utils.HtmlFormatter` and `io.legado.app.utils.isTrue`.
//

import Foundation

public enum TextFormat {

    // MARK: - Book name and author

    /// Upstream `BookHelp.formatBookName`.
    public static func formatBookName(_ name: String) -> String {
        replace(name, pattern: RulePatterns.namePattern, with: "")
            .trimmingJavaSpaces()
    }

    /// Upstream `BookHelp.formatBookAuthor`.
    public static func formatBookAuthor(_ author: String) -> String {
        replace(author, pattern: RulePatterns.authorPattern, with: "")
            .trimmingJavaSpaces()
    }

    /// Upstream `StringUtils.wordCountFormat(Int)`.
    public static func wordCountFormat(_ words: Int) -> String {
        guard words > 0 else { return "" }
        if words > 10000 {
            let value = Double(words) / 10000.0
            return String(format: "%.1f", value) + "万字"
        }
        return "\(words)字"
    }

    /// Upstream `StringUtils.wordCountFormat(String?)`.
    public static func wordCountFormat(_ wordCount: String?) -> String {
        guard let wordCount else { return "" }
        let trimmed = wordCount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let words = Int(trimmed) else { return wordCount }
        guard words > 0 else { return "" }
        if words > 10000 {
            let value = Double(words) / 10000.0
            return String(format: "%.1f", value) + "万字"
        }
        return "\(words)字"
    }

    /// Upstream `String?.isTrue`.
    public static func isTrue(_ value: String?, nullIsTrue: Bool = false) -> Bool {
        guard let value else { return nullIsTrue }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "null" { return nullIsTrue }
        let lowered = trimmed.lowercased()
        return !(lowered == "false" || lowered == "no" || lowered == "not" || lowered == "0")
    }

    // MARK: - HTML

    /// Upstream `HtmlFormatter.format`.
    public static func format(_ html: String?, otherPattern: NSRegularExpression? = nil) -> String {
        guard let html else { return "" }
        var text = html
        text = replace(text, pattern: RulePatterns.nbspPattern, with: " ")
        text = replace(text, pattern: RulePatterns.espPattern, with: " ")
        text = replace(text, pattern: RulePatterns.noPrintPattern, with: "")
        text = replace(text, pattern: RulePatterns.wrapHtmlPattern, with: "\n")
        text = replace(text, pattern: RulePatterns.commentPattern, with: "")
        text = replace(text, pattern: otherPattern ?? RulePatterns.otherHtmlPattern, with: "")
        text = replace(text, pattern: RulePatterns.indent1Pattern, with: "\n　　")
        text = replace(text, pattern: RulePatterns.indent2Pattern, with: "　　")
        text = replace(text, pattern: RulePatterns.lastPattern, with: "")
        return text
    }

    /// Upstream `HtmlFormatter.formatKeepImg`.
    public static func formatKeepImg(_ html: String?, redirectUrl: URL? = nil) -> String {
        guard let html else { return "" }
        let text = format(html, otherPattern: RulePatterns.notImgHtmlPattern)
        var result = ""
        var appendPosition = text.startIndex
        let fullRange = NSRange(location: 0, length: (text as NSString).length)
        for match in RulePatterns.formatImagePattern.matches(in: text, options: [], range: fullRange) {
            guard let matchRange = text.range(from: match.range) else { continue }
            var raw = ""
            for index in 1...3 {
                let range = match.range(at: index)
                if range.location != NSNotFound, let swiftRange = text.range(from: range) {
                    raw = String(text[swiftRange])
                    break
                }
            }
            var url = raw
            var param = ""
            let rawRange = NSRange(location: 0, length: (raw as NSString).length)
            if let match = RulePatterns.paramPattern.firstMatch(in: raw, options: [], range: rawRange),
               let optionRange = raw.range(from: match.range) {
                param = "," + String(raw[optionRange.upperBound...])
                url = String(raw[raw.startIndex..<optionRange.lowerBound])
            }
            result += String(text[appendPosition..<matchRange.lowerBound])
            result += "<img src=\"\(NetworkUtils.absoluteURL(baseURL: redirectUrl, url))\(param)\">"
            appendPosition = matchRange.upperBound
        }
        result += String(text[appendPosition...])
        return result
    }

    // MARK: - Regex helpers

    /// Replace every match of `pattern` with `template`.
    private static func replace(
        _ text: String,
        pattern: NSRegularExpression,
        with template: String
    ) -> String {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return pattern.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}

public extension String {
    /// The Swift range of an UTF-16 range — `Range(NSRange, in:)` is not
    /// available in swift-corelibs-foundation.
    func range(from nsRange: NSRange) -> Range<String.Index>? {
        guard nsRange.location != NSNotFound, nsRange.location >= 0 else { return nil }
        let length = utf16.count
        guard nsRange.location + nsRange.length <= length else { return nil }
        let start = String.Index(utf16Offset: nsRange.location, in: self)
        let end = String.Index(utf16Offset: nsRange.location + nsRange.length, in: self)
        return start..<end
    }

    /// Whether the string matches the regular expression — upstream
    /// `String.matches(Regex)`.
    func matches(_ pattern: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: (self as NSString).length)
        return regex.firstMatch(in: self, options: [], range: range) != nil
    }
}
