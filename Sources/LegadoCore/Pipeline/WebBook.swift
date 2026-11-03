//
//  WebBook.swift
//  LegadoCore
//
//  The port of `io.legado.app.model.webBook.WebBook`.
//
//  Upstream: app/src/main/java/io/legado/app/model/webBook/WebBook.kt
//

import Foundation

/// The entry points of the network book flow — search, explore, detail page,
/// table of contents and chapter content.
public enum WebBook {

    // MARK: - Search

    /// Upstream `WebBook.searchBookAwait`.
    public static func searchBook(
        bookSource: BookSource,
        key: String,
        page: Int? = 1,
        filter: ((String, String) -> Bool)? = nil,
        shouldBreak: ((Int) -> Bool)? = nil,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> [SearchBook] {
        guard let searchUrl = bookSource.searchUrl, !searchUrl.isBlank else {
            throw PipelineError.emptyContent("搜索url不能为空")
        }
        let ruleData = RuleDataBox()
        let analyzeUrl = AnalyzeUrl(
            url: searchUrl,
            key: key,
            page: page,
            baseUrl: bookSource.bookSourceUrl,
            source: bookSource,
            dependencies: dependencies
        )
        var response = try await analyzeUrl.strResponse()
        response = try applyLoginCheck(bookSource, analyzeUrl, response)
        return try BookListAssembler.analyzeBookList(
            bookSource: bookSource,
            ruleData: ruleData,
            analyzeUrl: analyzeUrl,
            baseUrl: response.url,
            body: response.body,
            isSearch: true,
            isRedirect: false,
            filter: filter,
            shouldBreak: shouldBreak
        )
    }

    /// Upstream `WebBook.preciseSearchAwait`.
    public static func preciseSearch(
        bookSource: BookSource,
        name: String,
        author: String,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> Book {
        let results = try await searchBook(
            bookSource: bookSource,
            key: name,
            filter: { fName, fAuthor in fName == name && fAuthor == author },
            shouldBreak: { $0 > 0 },
            dependencies: dependencies
        )
        guard let searchBook = results.first else {
            throw PipelineError.emptyContent("未搜索到 \(name)(\(author)) 书籍")
        }
        return searchBook.toBook()
    }

    // MARK: - Explore

    /// Upstream `WebBook.exploreBookAwait`.
    public static func exploreBook(
        bookSource: BookSource,
        url: String,
        page: Int? = 1,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> [SearchBook] {
        let ruleData = RuleDataBox()
        let analyzeUrl = AnalyzeUrl(
            url: url,
            page: page,
            baseUrl: bookSource.bookSourceUrl,
            source: bookSource,
            dependencies: dependencies
        )
        var response = try await analyzeUrl.strResponse()
        response = try applyLoginCheck(bookSource, analyzeUrl, response)
        return try BookListAssembler.analyzeBookList(
            bookSource: bookSource,
            ruleData: ruleData,
            analyzeUrl: analyzeUrl,
            baseUrl: response.url,
            body: response.body,
            isSearch: false,
            isRedirect: false
        )
    }

    // MARK: - Detail page

    /// Upstream `WebBook.getBookInfoAwait`.
    public static func getBookInfo(
        bookSource: BookSource,
        book: Book,
        canReName: Bool = true,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> Book {
        var book = book
        // Upstream `book.removeAllBookType(); book.addType(bookSource.getBookType())`:
        // only the book-type bits are replaced — the other bits (the "not on
        // the shelf" flag, the "update failed" flag, the local flag) survive.
        book.type = (book.type & ~BookType.allBookType) | bookSource.bookType
        if let infoHtml = book.infoHtml, !infoHtml.isEmpty {
            // The upstream Kotlin writes the parsed fields back into the book;
            // Swift returns a copy, so the parsed book has to be returned.
            return try BookInfoAssembler.analyzeBookInfo(
                bookSource: bookSource,
                book: book,
                baseUrl: book.bookUrl,
                redirectUrl: book.bookUrl,
                body: infoHtml,
                canReName: canReName
            )
        }
        let analyzeUrl = AnalyzeUrl(
            url: book.bookUrl,
            baseUrl: bookSource.bookSourceUrl,
            source: bookSource,
            dependencies: dependencies
        )
        var response = try await analyzeUrl.strResponse()
        response = try applyLoginCheck(bookSource, analyzeUrl, response)
        return try BookInfoAssembler.analyzeBookInfo(
            bookSource: bookSource,
            book: book,
            baseUrl: book.bookUrl,
            redirectUrl: response.url,
            body: response.body,
            canReName: canReName
        )
    }

    // MARK: - Table of contents

    /// Upstream `WebBook.getChapterListAwait`.
    public static func getChapterList(
        bookSource: BookSource,
        book: Book,
        runPerJs: Bool = false,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> ChapterListResult {
        var book = book
        // Upstream `book.removeAllBookType(); book.addType(bookSource.getBookType())`:
        // only the book-type bits are replaced — the other bits (the "not on
        // the shelf" flag, the "update failed" flag, the local flag) survive.
        book.type = (book.type & ~BookType.allBookType) | bookSource.bookType

        if runPerJs, let preUpdateJs = bookSource.tocRule?.preUpdateJs, !preUpdateJs.isBlank {
            try runPreUpdateJs(preUpdateJs, bookSource: bookSource, book: book, dependencies: dependencies)
        }

        if book.bookUrl == book.tocUrl, let tocHtml = book.tocHtml, !tocHtml.isEmpty {
            return try await BookChapterListAssembler.analyzeChapterList(
                bookSource: bookSource,
                book: book,
                baseUrl: book.tocUrl,
                redirectUrl: book.tocUrl,
                body: tocHtml,
                fetch: { try await fetchPage(bookSource: bookSource, url: $0, dependencies: dependencies) },
                scriptEngine: dependencies.scriptEngine
            )
        }

        let analyzeUrl = AnalyzeUrl(
            url: book.tocUrl,
            baseUrl: book.bookUrl,
            source: bookSource,
            dependencies: dependencies
        )
        var response = try await analyzeUrl.strResponse()
        response = try applyLoginCheck(bookSource, analyzeUrl, response)
        return try await BookChapterListAssembler.analyzeChapterList(
            bookSource: bookSource,
            book: book,
            baseUrl: book.tocUrl,
            redirectUrl: response.url,
            body: response.body,
            fetch: { try await fetchPage(bookSource: bookSource, url: $0, dependencies: dependencies) },
            scriptEngine: dependencies.scriptEngine
        )
    }

    /// Upstream `WebBook.runPreUpdateJs`.
    public static func runPreUpdateJs(
        _ preUpdateJs: String,
        bookSource: BookSource,
        book: Book,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) throws {
        guard let engine = dependencies.scriptEngine else { return }
        let analyzeRule = AnalyzeRule(content: .text(""), baseUrl: book.bookUrl)
        analyzeRule.source = bookSource.variableBox
        analyzeRule.bookName = book.name
        _ = try engine.evaluate(preUpdateJs, bindings: [
            "book": .scriptObject(["name": .text(book.name), "bookUrl": .text(book.bookUrl)]),
            "baseUrl": .text(book.bookUrl)
        ])
    }

    // MARK: - Chapter content

    /// Upstream `WebBook.getContentAwait`.
    public static func getContent(
        bookSource: BookSource,
        book: Book,
        bookChapter: BookChapter,
        nextChapterUrl: String? = nil,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> String {
        let contentRule = bookSource.contentRule ?? ContentRule()
        guard let contentText = contentRule.content, !contentText.isEmpty else {
            // An empty content rule — the chapter URL is the content.
            return bookChapter.url
        }
        if bookChapter.isVolume && bookChapter.url.hasPrefix(bookChapter.title) {
            // A volume chapter has no content.
            return bookChapter.tag ?? ""
        }

        let chapterUrl = NetworkUtils.absoluteURL(base: book.tocUrl, bookChapter.url)
        if bookChapter.url == book.bookUrl, let tocHtml = book.tocHtml, !tocHtml.isEmpty {
            return try await BookContentAssembler.analyzeContent(
                bookSource: bookSource,
                book: book,
                bookChapter: bookChapter,
                baseUrl: chapterUrl,
                redirectUrl: chapterUrl,
                body: tocHtml,
                nextChapterUrl: nextChapterUrl,
                fetch: { try await fetchPage(bookSource: bookSource, url: $0, dependencies: dependencies) }
            )
        }

        let analyzeUrl = AnalyzeUrl(
            url: chapterUrl,
            baseUrl: book.tocUrl,
            source: bookSource,
            bookName: book.name,
            chapterTitle: bookChapter.title,
            dependencies: dependencies
        )
        var response = try await analyzeUrl.strResponse(
            jsString: contentRule.webJs,
            sourceRegex: contentRule.sourceRegex
        )
        response = try applyLoginCheck(bookSource, analyzeUrl, response)
        return try await BookContentAssembler.analyzeContent(
            bookSource: bookSource,
            book: book,
            bookChapter: bookChapter,
            baseUrl: chapterUrl,
            redirectUrl: response.url,
            body: response.body,
            nextChapterUrl: nextChapterUrl,
            fetch: { try await fetchPage(bookSource: bookSource, url: $0, dependencies: dependencies) }
        )
    }

    // MARK: - Helpers

    /// Fetch one page of a source.
    private static func fetchPage(
        bookSource: BookSource,
        url: String,
        dependencies: AnalyzeUrlDependencies
    ) async throws -> String {
        let analyzeUrl = AnalyzeUrl(
            url: url,
            source: bookSource,
            dependencies: dependencies
        )
        let response = try await analyzeUrl.strResponse()
        return response.body ?? ""
    }

    /// Upstream — the login check script may rewrite the response.
    private static func applyLoginCheck(
        _ bookSource: BookSource,
        _ analyzeUrl: AnalyzeUrl,
        _ response: HttpResponse
    ) throws -> HttpResponse {
        guard let checkJs = bookSource.loginCheckJs, !checkJs.isBlank else { return response }
        var result = response
        let value = try analyzeUrl.evalJS(checkJs, result: .scriptObject([
            "url": .text(response.url),
            "body": .text(response.body ?? ""),
            "code": .number(Double(response.code))
        ]))
        if case .scriptObject(let members) = value {
            if let url = members["url"]?.textValue, !url.isEmpty { result.url = url }
            if let body = members["body"]?.textValue { result.body = body }
            if let code = members["code"]?.textValue, let intCode = Int(code) { result.code = intCode }
        } else if case .text(let text) = value, !text.isEmpty {
            result.body = text
        }
        return result
    }
}

public extension SearchBook {
    /// Upstream `SearchBook.toBook`.
    func toBook() -> Book {
        var book = Book()
        book.bookUrl = bookUrl
        book.origin = origin
        book.originName = originName
        book.type = type
        book.name = name
        book.author = author
        book.kind = kind
        book.coverUrl = coverUrl
        book.intro = intro
        book.wordCount = wordCount
        book.latestChapterTitle = latestChapterTitle
        book.tocUrl = tocUrl
        book.variable = variable
        book.originOrder = originOrder
        book.infoHtml = infoHtml
        book.tocHtml = tocHtml
        return book
    }
}
