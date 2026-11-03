//
//  BookInfoAssembler.swift
//  LegadoCore
//
//  The port of `io.legado.app.model.webBook.BookInfo`.
//
//  Upstream: app/src/main/java/io/legado/app/model/webBook/BookInfo.kt
//

import Foundation

/// Parses the detail page of a book.
public enum BookInfoAssembler {

    /// Upstream `BookInfo.analyzeBookInfo` — the entry point that fetches the
    /// rule from the source and creates the rule engine.
    @discardableResult
    public static func analyzeBookInfo(
        bookSource: BookSource,
        book: Book,
        baseUrl: String,
        redirectUrl: String,
        body: String?,
        canReName: Bool
    ) throws -> Book {
        guard let body, !body.isEmpty else {
            throw PipelineError.emptyContent(baseUrl)
        }
        let analyzeRule = AnalyzeRule(content: .text(body), baseUrl: baseUrl)
        analyzeRule.setRedirectUrl(redirectUrl)
        analyzeRule.source = bookSource.variableBox
        return try analyzeBookInfo(
            book: book,
            body: body,
            analyzeRule: analyzeRule,
            bookSource: bookSource,
            baseUrl: baseUrl,
            redirectUrl: redirectUrl,
            canReName: canReName
        )
    }

    /// Upstream `BookInfo.analyzeBookInfo` — the overload that works with an
    /// existing rule engine (the search list reuses the engine of the page).
    ///
    /// The upstream Kotlin passes the book by reference, so the parsed fields
    /// are written back into the caller's book. Swift passes structs by value,
    /// so the updated book is returned.
    @discardableResult
    public static func analyzeBookInfo(
        book: Book,
        body: String,
        analyzeRule: AnalyzeRule,
        bookSource: BookSource,
        baseUrl: String,
        redirectUrl: String,
        canReName: Bool
    ) throws -> Book {
        var book = book
        let infoRule = bookSource.bookInfoRule ?? BookInfoRule()

        // The optional `init` rule narrows the document down.
        if let initRule = infoRule.`init`, !initRule.isBlank {
            if let element = try analyzeRule.getElement(initRule) {
                try analyzeRule.setContent(RuleContent.from(ruleValue: element))
            }
        }

        let canReName = canReName && !(infoRule.canReName ?? "").isBlank

        let name = TextFormat.formatBookName(try analyzeRule.getString(infoRule.name))
        if !name.isEmpty && (canReName || book.name.isEmpty) {
            book.name = name
        }

        let author = TextFormat.formatBookAuthor(try analyzeRule.getString(infoRule.author))
        if !author.isEmpty && (canReName || book.author.isEmpty) {
            book.author = author
        }

        if let kinds = try analyzeRule.getStringList(infoRule.kind), !kinds.isEmpty {
            book.kind = kinds.joined(separator: ",")
        }

        let wordCount = try analyzeRule.getString(infoRule.wordCount)
        if !wordCount.isEmpty {
            book.wordCount = TextFormat.wordCountFormat(wordCount)
        }

        let lastChapter = try analyzeRule.getString(infoRule.lastChapter)
        if !lastChapter.isEmpty {
            book.latestChapterTitle = lastChapter
        }

        let intro = try analyzeRule.getString(infoRule.intro)
        if !intro.isEmpty {
            book.intro = TextFormat.format(intro)
        }

        let coverUrl = try analyzeRule.getString(infoRule.coverUrl)
        if !coverUrl.isEmpty {
            book.coverUrl = NetworkUtils.absoluteURL(base: redirectUrl, coverUrl)
        }

        if !book.isWebFile {
            var tocUrl = try analyzeRule.getString(infoRule.tocUrl, isUrl: true)
            if tocUrl.isEmpty { tocUrl = baseUrl }
            book.tocUrl = tocUrl
            if tocUrl == baseUrl {
                book.tocHtml = body
            }
        } else {
            let downloadUrls = try analyzeRule.getStringList(infoRule.downloadUrls, isUrl: true)
            guard let downloadUrls, !downloadUrls.isEmpty else {
                throw PipelineError.downloadUrlsEmpty
            }
            book.downloadUrls = downloadUrls
        }
        return book
    }
}
