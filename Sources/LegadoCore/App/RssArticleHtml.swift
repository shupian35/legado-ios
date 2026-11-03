//
//  RssArticleHtml.swift
//  LegadoCore
//
//  The HTML of an RSS article.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/rss/read/ReadRssViewModel.kt (clHtml)
//  app/src/main/java/io/legado/app/ui/rss/read/ReadRssActivity.kt
//  (CustomWebViewClient.shouldInterceptRequest)
//

import Foundation

/// The HTML of an RSS article — upstream `ReadRssViewModel.clHtml`.
///
/// The upstream renders the article in a `WebView`: the content is wrapped
/// in a `<style>` block (the style of the source, the style of the content
/// or the default style) and the requests of the page are filtered with the
/// black list and the white list of the source.
public enum RssArticleHtml {

    /// The default style of an article — upstream `ReadRssViewModel.clHtml`.
    public static let defaultStyle = """
    img{max-width:100%;height:auto}
    video{object-fit:fill;max-width:100%;max-height:100%;height:auto}
    body{word-wrap:break-word;height:auto;max-width:100%;width:auto}
    """

    /// The HTML of an article — upstream `ReadRssViewModel.clHtml`.
    ///
    /// The custom style of the source wins, a content that already carries a
    /// `<style>` block is used as it is and a plain content gets the default
    /// style.
    public static func html(content: String, source: RssSource) -> String {
        if let style = source.style, !style.isEmpty {
            return "<style>\(style)</style>\(content)"
        }
        if content.contains("<style>") {
            return content
        }
        return "<style>\(defaultStyle)</style>\(content)"
    }

    /// The full HTML document of an article.
    ///
    /// The upstream loads the HTML with `loadDataWithBaseURL`; when the
    /// source has `loadWithBaseUrl` the base URL is the address of the
    /// article, otherwise the relative links of the content do not resolve.
    public static func document(
        content: String,
        source: RssSource,
        baseURL: String? = nil
    ) -> String {
        let body = html(content: content, source: source)
        let head = """
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        """
        return "<!DOCTYPE html><html><head>\(head)</head><body>\(body)</body></html>"
    }

    /// Whether a request of the article is allowed — upstream
    /// `ReadRssActivity.CustomWebViewClient.shouldInterceptRequest`.
    ///
    /// The upstream checks the black list first: a URL that starts with a
    /// rule or that matches its regular expression is blocked. Only when the
    /// black list is empty the white list is used — a URL in the white list
    /// passes, every other URL is blocked. When neither list is set every
    /// request passes.
    public static func isAllowed(url: String, source: RssSource) -> Bool {
        let blacklist = splitRules(source.contentBlacklist)
        if !blacklist.isEmpty {
            for rule in blacklist where matches(url: url, rule: rule) { return false }
            return true
        }
        let whitelist = splitRules(source.contentWhitelist)
        if !whitelist.isEmpty {
            for rule in whitelist where matches(url: url, rule: rule) { return true }
            return false
        }
        return true
    }

    /// The rules of a black list or of a white list.
    ///
    /// Upstream `splitNotBlank(",")` — the rules are separated by commas.
    private static func splitRules(_ rules: String?) -> [String] {
        guard let rules, !rules.isEmpty else { return [] }
        return rules
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Whether a URL matches a rule — upstream
    /// `url.startsWith(it) || url.matches(it.toRegex())`.
    private static func matches(url: String, rule: String) -> Bool {
        url.hasPrefix(rule) || url.matches(rule)
    }
}
