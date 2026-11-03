//
//  BookListAssembler.swift
//  LegadoCore
//
//  The port of `io.legado.app.model.webBook.BookList`.
//
//  Upstream: app/src/main/java/io/legado/app/model/webBook/BookList.kt
//

import Foundation

/// Parses a book list (search results or the "explore" categories).
public enum BookListAssembler {

    /// Upstream `BookList.analyzeBookList`.
    ///
    /// - Parameters:
    ///   - bookSource: the source the rules belong to.
    ///   - ruleData: the variable store of the evaluation.
    ///   - analyzeUrl: the URL the page was fetched from.
    ///   - baseUrl: the final URL of the response (after redirects).
    ///   - body: the response body.
    ///   - isSearch: `true` for a search, `false` for an explore page.
    ///   - isRedirect: `true` when the response was a redirect to the detail page.
    ///   - filter: an optional name/author filter.
    ///   - shouldBreak: an optional callback that stops the loop.
    public static func analyzeBookList(
        bookSource: BookSource,
        ruleData: RuleDataBox,
        analyzeUrl: AnalyzeUrl,
        baseUrl: String,
        body: String?,
        isSearch: Bool = true,
        isRedirect: Bool = false,
        filter: ((String, String) -> Bool)? = nil,
        shouldBreak: ((Int) -> Bool)? = nil
    ) throws -> [SearchBook] {
        guard let body, !body.isEmpty else {
            throw PipelineError.emptyContent(analyzeUrl.ruleUrl)
        }

        var bookList: [SearchBook] = []
        let analyzeRule = AnalyzeRule(content: .text(body), baseUrl: baseUrl)
        analyzeRule.setRedirectUrl(baseUrl)
        analyzeRule.source = bookSource.variableBox
        analyzeRule.ruleData = ruleData

        // A search URL that matches the detail page pattern is a detail page.
        if isSearch, let pattern = bookSource.bookUrlPattern, !pattern.isEmpty,
           baseUrl.matches(pattern) {
            if let searchBook = try getInfoItem(
                bookSource: bookSource,
                analyzeRule: analyzeRule,
                analyzeUrl: analyzeUrl,
                body: body,
                baseUrl: baseUrl,
                variable: ruleData.getVariable("variable") ?? "",
                isRedirect: isRedirect,
                filter: filter
            ) {
                var book = searchBook
                book.infoHtml = body
                bookList.append(book)
            }
            return bookList
        }

        // The list rule — the explore rule falls back to the search rule.
        let bookListRule: BookListRule
        if isSearch {
            bookListRule = bookSource.searchRule.map(BookListRule.init(searchRule:)) ?? BookListRule()
        } else if bookSource.exploreRule?.bookList?.isBlank != false {
            bookListRule = bookSource.searchRule.map(BookListRule.init(searchRule:)) ?? BookListRule()
        } else {
            bookListRule = bookSource.exploreRule.map(BookListRule.init(exploreRule:)) ?? BookListRule()
        }

        var reverse = false
        var ruleList = bookListRule.bookList ?? ""
        if ruleList.hasPrefix("-") {
            reverse = true
            ruleList = String(ruleList.dropFirst())
        }
        if ruleList.hasPrefix("+") {
            ruleList = String(ruleList.dropFirst())
        }

        let collections = try analyzeRule.getElements(ruleList)
        if collections.isEmpty && (bookSource.bookUrlPattern?.isEmpty ?? true) {
            // No list found — parse the page as a detail page.
            if let searchBook = try getInfoItem(
                bookSource: bookSource,
                analyzeRule: analyzeRule,
                analyzeUrl: analyzeUrl,
                body: body,
                baseUrl: baseUrl,
                variable: ruleData.getVariable("variable") ?? "",
                isRedirect: isRedirect,
                filter: filter
            ) {
                var book = searchBook
                book.infoHtml = body
                bookList.append(book)
            }
            return bookList
        }

        let ruleName = analyzeRule.splitSourceRule(bookListRule.name)
        let ruleBookUrl = analyzeRule.splitSourceRule(bookListRule.bookUrl)
        let ruleAuthor = analyzeRule.splitSourceRule(bookListRule.author)
        let ruleCoverUrl = analyzeRule.splitSourceRule(bookListRule.coverUrl)
        let ruleIntro = analyzeRule.splitSourceRule(bookListRule.intro)
        let ruleKind = analyzeRule.splitSourceRule(bookListRule.kind)
        let ruleLastChapter = analyzeRule.splitSourceRule(bookListRule.lastChapter)
        let ruleWordCount = analyzeRule.splitSourceRule(bookListRule.wordCount)

        for (index, item) in collections.enumerated() {
            let searchBook = try getSearchItem(
                bookSource: bookSource,
                analyzeRule: analyzeRule,
                item: item,
                baseUrl: baseUrl,
                variable: ruleData.getVariable("variable") ?? "",
                filter: filter,
                ruleName: ruleName,
                ruleBookUrl: ruleBookUrl,
                ruleAuthor: ruleAuthor,
                ruleCoverUrl: ruleCoverUrl,
                ruleIntro: ruleIntro,
                ruleKind: ruleKind,
                ruleLastChapter: ruleLastChapter,
                ruleWordCount: ruleWordCount
            )
            if var searchBook {
                if baseUrl == searchBook.bookUrl {
                    searchBook.infoHtml = body
                }
                bookList.append(searchBook)
            }
            if shouldBreak?(bookList.count) == true { break }
            _ = index
        }

        // De-duplicate, keeping the original order.
        var seen = Set<SearchBook>()
        var unique: [SearchBook] = []
        for book in bookList where seen.insert(book).inserted {
            unique.append(book)
        }
        bookList = unique
        if reverse {
            bookList.reverse()
        }
        return bookList
    }

    // MARK: - Detail page

    /// Upstream `BookList.getInfoItem`.
    private static func getInfoItem(
        bookSource: BookSource,
        analyzeRule: AnalyzeRule,
        analyzeUrl: AnalyzeUrl,
        body: String,
        baseUrl: String,
        variable: String,
        isRedirect: Bool,
        filter: ((String, String) -> Bool)?
    ) throws -> SearchBook? {
        var book = Book()
        book.bookUrl = isRedirect
            ? baseUrl
            : NetworkUtils.absoluteURL(base: analyzeUrl.url, analyzeUrl.ruleUrl)
        book.origin = bookSource.bookSourceUrl
        book.originName = bookSource.bookSourceName
        book.originOrder = bookSource.customOrder
        book.type = bookSource.bookType

        let box = RuleDataBox(json: variable.isEmpty ? nil : variable)
        analyzeRule.ruleData = box
        let parsed = try BookInfoAssembler.analyzeBookInfo(
            book: book,
            body: body,
            analyzeRule: analyzeRule,
            bookSource: bookSource,
            baseUrl: baseUrl,
            redirectUrl: baseUrl,
            canReName: false
        )
        if filter?(parsed.name, parsed.author) == false { return nil }
        guard !parsed.name.isEmpty else { return nil }
        return parsed.toSearchBook()
    }

    // MARK: - List item

    /// Upstream `BookList.getSearchItem`.
    private static func getSearchItem(
        bookSource: BookSource,
        analyzeRule: AnalyzeRule,
        item: RuleValue,
        baseUrl: String,
        variable: String,
        filter: ((String, String) -> Bool)?,
        ruleName: [SourceRule],
        ruleBookUrl: [SourceRule],
        ruleAuthor: [SourceRule],
        ruleCoverUrl: [SourceRule],
        ruleIntro: [SourceRule],
        ruleKind: [SourceRule],
        ruleLastChapter: [SourceRule],
        ruleWordCount: [SourceRule]
    ) throws -> SearchBook? {
        var searchBook = SearchBook()
        searchBook.type = bookSource.bookType
        searchBook.origin = bookSource.bookSourceUrl
        searchBook.originName = bookSource.bookSourceName
        searchBook.originOrder = bookSource.customOrder

        let box = RuleDataBox(json: variable.isEmpty ? nil : variable)
        analyzeRule.ruleData = box
        try analyzeRule.setContent(RuleContent.from(ruleValue: item))

        searchBook.name = TextFormat.formatBookName(try analyzeRule.getString(ruleName))
        guard !searchBook.name.isEmpty else { return nil }

        searchBook.author = TextFormat.formatBookAuthor(try analyzeRule.getString(ruleAuthor))
        if filter?(searchBook.name, searchBook.author) == false { return nil }

        if let kinds = try analyzeRule.getStringList(ruleKind), !kinds.isEmpty {
            searchBook.kind = kinds.joined(separator: ",")
        }

        let wordCount = try analyzeRule.getString(ruleWordCount)
        if !wordCount.isEmpty {
            searchBook.wordCount = TextFormat.wordCountFormat(wordCount)
        }

        let lastChapter = try analyzeRule.getString(ruleLastChapter)
        if !lastChapter.isEmpty {
            searchBook.latestChapterTitle = lastChapter
        }

        let intro = try analyzeRule.getString(ruleIntro)
        if !intro.isEmpty {
            searchBook.intro = TextFormat.format(intro)
        }

        let coverUrl = try analyzeRule.getString(ruleCoverUrl)
        if !coverUrl.isEmpty {
            searchBook.coverUrl = NetworkUtils.absoluteURL(base: baseUrl, coverUrl)
        }

        var bookUrl = try analyzeRule.getString(ruleBookUrl, isUrl: true)
        if bookUrl.isEmpty {
            bookUrl = baseUrl
        }
        searchBook.bookUrl = bookUrl
        return searchBook
    }
}

public extension Book {
    /// Upstream `Book.toSearchBook`.
    func toSearchBook() -> SearchBook {
        var searchBook = SearchBook()
        searchBook.bookUrl = bookUrl
        searchBook.origin = origin
        searchBook.originName = originName
        searchBook.type = type
        searchBook.name = name
        searchBook.author = author
        searchBook.kind = kind
        searchBook.coverUrl = coverUrl
        searchBook.intro = intro
        searchBook.wordCount = wordCount
        searchBook.latestChapterTitle = latestChapterTitle
        searchBook.tocUrl = tocUrl
        searchBook.variable = variable
        searchBook.originOrder = originOrder
        searchBook.infoHtml = infoHtml
        searchBook.tocHtml = tocHtml
        return searchBook
    }
}
