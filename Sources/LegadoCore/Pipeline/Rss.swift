//
//  Rss.swift
//  LegadoCore
//
//  The RSS pipeline.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/model/rss/Rss.kt (103 lines)
//  app/src/main/java/io/legado/app/model/rss/RssParserByRule.kt (132 lines)
//  app/src/main/java/io/legado/app/model/rss/RssParserDefault.kt (150 lines)
//
//  The rule parser is a faithful port. The default parser uses SwiftSoup's XML
//  mode instead of Android's `XmlPullParser`, which produces the same articles
//  for the tags that matter.
//

import Foundation
import SwiftSoup

public enum RssError: Error, Equatable {
    case emptyBody(String)
    case invalidXML
}

/// Fetches the article list of one feed.
public struct RssArticlePage: Equatable {
    public var articles: [RssArticle]
    public var nextUrl: String?
    public init(articles: [RssArticle], nextUrl: String? = nil) {
        self.articles = articles
        self.nextUrl = nextUrl
    }
}

public enum Rss {
    // MARK: - Article list

    /// Fetches and parses one page of a feed (upstream `Rss.getArticlesAwait`).
    public static func articles(
        sortName: String,
        sortUrl: String,
        rssSource: RssSource,
        page: Int,
        dependencies: AnalyzeUrlDependencies,
        scriptEngine: RuleScriptEngine? = nil
    ) async throws -> RssArticlePage {
        let ruleData = RuleDataBox()
        var analyzeUrl = AnalyzeUrl(
            url: sortUrl,
            page: page,
            source: rssSource,
            hasLoginHeader: false,
            dependencies: dependencies
        )
        try analyzeUrl.initUrl()
        let response = try await analyzeUrl.strResponse()
        return try parseArticles(
            sortName: sortName,
            sortUrl: sortUrl,
            redirectUrl: response.url,
            body: response.body ?? "",
            rssSource: rssSource,
            ruleData: ruleData,
            scriptEngine: scriptEngine
        )
    }

    /// Parses an article list page with the source rules, falling back to the
    /// default RSS parser when the source has no list rule
    /// (upstream `RssParserByRule.parseXML`).
    public static func parseArticles(
        sortName: String,
        sortUrl: String,
        redirectUrl: String,
        body: String?,
        rssSource: RssSource,
        ruleData: RuleDataBox,
        scriptEngine: RuleScriptEngine? = nil
    ) throws -> RssArticlePage {
        guard let body = body, !body.isBlank else {
            throw RssError.emptyBody(rssSource.sourceUrl)
        }

        guard var ruleArticles = rssSource.ruleArticles, !ruleArticles.isBlank else {
            return try parseDefault(sortName: sortName, xml: body, sourceUrl: rssSource.sourceUrl)
        }

        let analyzeRule = AnalyzeRule()
        // `ruleData`/`source` are weak on `AnalyzeRule` (upstream keeps them in
        // strong fields), so the boxes are held here for the whole parse.
        let sourceBox = rssSource.variableBox
        analyzeRule.ruleData = ruleData
        analyzeRule.source = sourceBox
        analyzeRule.scriptEngine = scriptEngine
        _ = try analyzeRule.setContent(.text(body))
        analyzeRule.setBaseUrl(sortUrl)
        analyzeRule.setRedirectUrl(redirectUrl)

        var reverse = false
        if ruleArticles.hasPrefix("-") {
            reverse = true
            ruleArticles = String(ruleArticles.dropFirst())
        }

        let collections = try analyzeRule.getElements(ruleArticles)

        var nextUrl: String? = nil
        if let ruleNextPage = rssSource.ruleNextPage, !ruleNextPage.isEmpty {
            if ruleNextPage.uppercased() == "PAGE" {
                nextUrl = sortUrl
            } else {
                let value = try analyzeRule.getString(ruleNextPage)
                if !value.isEmpty {
                    nextUrl = NetworkUtils.absoluteURL(base: sortUrl, value)
                }
            }
        }

        let ruleTitle = analyzeRule.splitSourceRule(rssSource.ruleTitle)
        let rulePubDate = analyzeRule.splitSourceRule(rssSource.rulePubDate)
        let ruleDescription = analyzeRule.splitSourceRule(rssSource.ruleDescription)
        let ruleImage = analyzeRule.splitSourceRule(rssSource.ruleImage)
        let ruleLink = analyzeRule.splitSourceRule(rssSource.ruleLink)
        let variable = ruleData.json

        var articles: [RssArticle] = []
        for item in collections {
            if let article = try getItem(
                sourceUrl: rssSource.sourceUrl,
                item: item,
                analyzeRule: analyzeRule,
                variable: variable,
                ruleTitle: ruleTitle,
                rulePubDate: rulePubDate,
                ruleDescription: ruleDescription,
                ruleImage: ruleImage,
                ruleLink: ruleLink
            ) {
                var result = article
                result.sort = sortName
                result.origin = rssSource.sourceUrl
                articles.append(result)
            }
        }
        if reverse {
            articles.reverse()
        }
        return RssArticlePage(articles: articles, nextUrl: nextUrl)
    }

    private static func getItem(
        sourceUrl: String,
        item: RuleValue,
        analyzeRule: AnalyzeRule,
        variable: String?,
        ruleTitle: [SourceRule],
        rulePubDate: [SourceRule],
        ruleDescription: [SourceRule],
        ruleImage: [SourceRule],
        ruleLink: [SourceRule]
    ) throws -> RssArticle? {
        var article = RssArticle(origin: sourceUrl, sort: "", title: "", link: "")
        // Upstream seeds the article with the list-page variables
        // (`RssArticle(variable = variable)`).
        let articleBox = RuleDataBox(json: variable)
        analyzeRule.ruleData = articleBox
        try analyzeRule.setContent(RuleContent.from(ruleValue: item))

        article.title = try analyzeRule.getString(ruleTitle)
        article.pubDate = try analyzeRule.getString(rulePubDate)
        if ruleDescription.isEmpty {
            // No description rule — the content page will be parsed instead.
            article.description = nil
        } else {
            article.description = try analyzeRule.getString(ruleDescription)
        }
        article.image = try analyzeRule.getString(ruleImage, isUrl: true)
        article.link = NetworkUtils.absoluteURL(
            base: sourceUrl,
            try analyzeRule.getString(ruleLink)
        )
        article.variable = articleBox.json
        guard !article.title.isBlank else { return nil }
        return article
    }

    // MARK: - Content

    /// Fetches and parses the body of one article
    /// (upstream `Rss.getContentAwait`).
    public static func content(
        article: RssArticle,
        ruleContent: String,
        rssSource: RssSource,
        dependencies: AnalyzeUrlDependencies,
        scriptEngine: RuleScriptEngine? = nil
    ) async throws -> String {
        var analyzeUrl = AnalyzeUrl(
            url: article.link,
            baseUrl: article.origin,
            source: rssSource,
            hasLoginHeader: false,
            dependencies: dependencies
        )
        try analyzeUrl.initUrl()
        let response = try await analyzeUrl.strResponse()

        let analyzeRule = AnalyzeRule()
        let articleBox = RuleDataBox(json: article.variable)
        let sourceBox = rssSource.variableBox
        analyzeRule.ruleData = articleBox
        analyzeRule.source = sourceBox
        analyzeRule.scriptEngine = scriptEngine
        _ = try analyzeRule.setContent(.text(response.body ?? ""))
        analyzeRule.setBaseUrl(
            NetworkUtils.absoluteURL(base: article.origin, article.link)
        )
        analyzeRule.setRedirectUrl(response.url)
        return try analyzeRule.getString(ruleContent)
    }

    // MARK: - Default parser

    /// The built-in RSS/Atom parser (upstream `RssParserDefault.parseXML`).
    public static func parseDefault(
        sortName: String,
        xml: String,
        sourceUrl: String
    ) throws -> RssArticlePage {
        let document: Document
        do {
            document = try SwiftSoup.parseXML(xml)
        } catch {
            throw RssError.invalidXML
        }

        var articles: [RssArticle] = []
        let items = try document.getElementsByTag("item")
        for item in items {
            var article = RssArticle(origin: sourceUrl, sort: sortName, title: "", link: "")
            article.title = (try text(of: item, "title")) ?? ""
            article.link = (try text(of: item, "link")) ?? ""
            article.image = try attribute(of: item, "media:thumbnail", "url")
            if article.image == nil {
                // An <enclosure type="image/..."> also carries the image.
                for enclosure in try item.getElementsByTag("enclosure") {
                    let type = try enclosure.attr("type")
                    if type.contains("image/") {
                        article.image = try enclosure.attr("url")
                        break
                    }
                }
            }
            article.description = try text(of: item, "description")
            if article.image == nil, let description = article.description {
                article.image = imageURL(in: description)
            }
            article.content = try text(of: item, "content:encoded")
            if article.image == nil, let content = article.content {
                article.image = imageURL(in: content)
            }
            article.pubDate = try text(of: item, "pubDate")
            if article.pubDate == nil || article.pubDate?.isEmpty == true {
                article.pubDate = try text(of: item, "time")
            }
            articles.append(article)
        }
        return RssArticlePage(articles: articles, nextUrl: nil)
    }

    /// The trimmed text of the first child with `tag`
    /// (`getElementsByTag` is used instead of a selector because SwiftSoup's
    /// query parser rejects the ":" of `content:encoded`).
    private static func text(of element: Element, _ tag: String) throws -> String? {
        guard let child = try element.getElementsByTag(tag).first() else { return nil }
        let value = (try? child.text()) ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func attribute(
        of element: Element,
        _ tag: String,
        _ name: String
    ) throws -> String? {
        guard let child = try element.getElementsByTag(tag).first() else { return nil }
        let value = try child.attr(name)
        return value.isEmpty ? nil : value
    }

    /// The `src` of the first `<img>` of `input`
    /// (upstream `RssParserDefault.getImageUrl`).
    static func imageURL(in input: String) -> String? {
        guard let match = RulePatterns.imageTagPattern.firstMatch(
            in: input,
            options: [],
            range: NSRange(location: 0, length: input.utf16.count)
        ) else { return nil }
        let nsInput = input as NSString
        guard match.numberOfRanges > 1 else { return nil }
        let tag = nsInput.substring(with: match.range(at: 1))
        guard let linkMatch = RulePatterns.imageSrcPattern.firstMatch(
            in: tag,
            options: [],
            range: NSRange(location: 0, length: tag.utf16.count)
        ) else { return nil }
        guard linkMatch.numberOfRanges > 1 else { return nil }
        return (tag as NSString)
            .substring(with: linkMatch.range(at: 1))
            .trimmingCharacters(in: .whitespaces)
    }
}
