//
//  BookContentAssembler.swift
//  LegadoCore
//
//  The port of `io.legado.app.model.webBook.BookContent`.
//
//  Upstream: app/src/main/java/io/legado/app/model/webBook/BookContent.kt
//

import Foundation

/// Parses the content of a chapter.
public enum BookContentAssembler {

    /// Upstream `BookContent.analyzeContent`.
    public static func analyzeContent(
        bookSource: BookSource,
        book: Book,
        bookChapter: BookChapter,
        baseUrl: String,
        redirectUrl: String,
        body: String?,
        nextChapterUrl: String?,
        fetch: ChapterPageFetcher? = nil
    ) async throws -> String {
        var bookChapter = bookChapter
        guard let body, !body.isEmpty else {
            throw PipelineError.emptyContent(baseUrl)
        }

        let nextChapterUrl = (nextChapterUrl?.isEmpty == false) ? nextChapterUrl : nil
        let contentRule = bookSource.contentRule ?? ContentRule()

        let analyzeRule = AnalyzeRule(content: .text(body), baseUrl: baseUrl)
        analyzeRule.setRedirectUrl(redirectUrl)
        analyzeRule.source = bookSource.variableBox
        analyzeRule.chapter = bookChapter.variableBox
        analyzeRule.bookName = book.name
        analyzeRule.chapterTitle = bookChapter.title
        analyzeRule.nextChapterUrl = nextChapterUrl

        // The optional title rule.
        if let titleRule = contentRule.title, !titleRule.isBlank {
            if let title = try? analyzeRule.getString(titleRule), !title.isBlank {
                bookChapter.title = title
                bookChapter.titleMD5 = nil
            }
        }

        var contentList: [String] = []
        var visitedUrls = [redirectUrl]
        var page = try analyzePage(
            book: book,
            baseUrl: baseUrl,
            redirectUrl: redirectUrl,
            body: body,
            contentRule: contentRule,
            chapter: bookChapter,
            bookSource: bookSource,
            nextChapterUrl: nextChapterUrl
        )
        contentList.append(page.content)

        switch page.nextUrls.count {
        case 0:
            break
        case 1:
            var nextUrl = page.nextUrls[0]
            while !nextUrl.isEmpty && !visitedUrls.contains(nextUrl) {
                if let nextChapterUrl,
                   NetworkUtils.absoluteURL(base: redirectUrl, nextUrl)
                    == NetworkUtils.absoluteURL(base: redirectUrl, nextChapterUrl) {
                    break
                }
                visitedUrls.append(nextUrl)
                guard let fetch, let nextBody = try? await fetch(nextUrl) else { break }
                page = try analyzePage(
                    book: book,
                    baseUrl: nextUrl,
                    redirectUrl: nextUrl,
                    body: nextBody,
                    contentRule: contentRule,
                    chapter: bookChapter,
                    bookSource: bookSource,
                    nextChapterUrl: nextChapterUrl
                )
                nextUrl = page.nextUrls.first ?? ""
                contentList.append(page.content)
            }
        default:
            if let fetch {
                let urls = page.nextUrls
                let bodies = await withTaskGroup(of: String?.self) { group -> [String?] in
                    for url in urls {
                        group.addTask { try? await fetch(url) }
                    }
                    var results: [String?] = []
                    for await body in group { results.append(body) }
                    return results
                }
                for (index, url) in urls.enumerated() {
                    guard let nextBody = bodies[index], !nextBody.isEmpty else { continue }
                    if let nextPage = try? analyzePage(
                        book: book,
                        baseUrl: url,
                        redirectUrl: url,
                        body: nextBody,
                        contentRule: contentRule,
                        chapter: bookChapter,
                        bookSource: bookSource,
                        nextChapterUrl: nextChapterUrl,
                        getNextPageUrl: false
                    ) {
                        contentList.append(nextPage.content)
                    }
                }
            }
        }

        var contentStr = contentList.joined(separator: "\n")

        // The full-text replacement.
        if let replaceRegex = contentRule.replaceRegex, !replaceRegex.isEmpty {
            contentStr = contentStr
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            contentStr = try analyzeRule.getString(replaceRegex, .text(contentStr))
            contentStr = contentStr
                .components(separatedBy: "\n")
                .map { line in "　　\(line)" }
                .joined(separator: "\n")
        }

        if !bookChapter.isVolume && contentStr.isBlank {
            throw PipelineError.contentEmpty
        }
        return contentStr
    }

    // MARK: - One page

    private struct ContentPage {
        var content: String
        var nextUrls: [String]
    }

    /// Upstream `BookContent.analyzeContent` (the private overload).
    private static func analyzePage(
        book: Book,
        baseUrl: String,
        redirectUrl: String,
        body: String,
        contentRule: ContentRule,
        chapter: BookChapter,
        bookSource: BookSource,
        nextChapterUrl: String?,
        getNextPageUrl: Bool = true
    ) throws -> ContentPage {
        let analyzeRule = AnalyzeRule(content: .text(body), baseUrl: baseUrl)
        analyzeRule.setRedirectUrl(redirectUrl)
        analyzeRule.source = bookSource.variableBox
        analyzeRule.chapter = chapter.variableBox
        analyzeRule.bookName = book.name
        analyzeRule.chapterTitle = chapter.title
        analyzeRule.nextChapterUrl = nextChapterUrl

        var content = try analyzeRule.getString(contentRule.content, unescape: false)
        content = TextFormat.formatKeepImg(content, redirectUrl: analyzeRule.redirectUrl)
        if content.contains("&") {
            content = RuleEntities.unescapeHTML4(content)
        }

        var nextUrlList: [String] = []
        if getNextPageUrl, let nextUrlRule = contentRule.nextContentUrl, !nextUrlRule.isEmpty {
            if let urls = try analyzeRule.getStringList(nextUrlRule, isUrl: true) {
                nextUrlList.append(contentsOf: urls)
            }
        }

        return ContentPage(content: content, nextUrls: nextUrlList)
    }
}
