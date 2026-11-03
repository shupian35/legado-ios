//
//  BookChapterListAssembler.swift
//  LegadoCore
//
//  The port of `io.legado.app.model.webBook.BookChapterList`.
//
//  Upstream: app/src/main/java/io/legado/app/model/webBook/BookChapterList.kt
//

import Foundation

/// Fetches the body of a "next page" URL.
public typealias ChapterPageFetcher = (String) async throws -> String

/// The result of a table of contents fetch — the chapters plus the book with
/// the chapter-count fields the upstream updates in place.
public struct ChapterListResult: Equatable, Sendable {
    /// The parsed chapters.
    public var chapters: [BookChapter]
    /// The book with `totalChapterNum`, `latestChapterTitle`, `durChapterTitle`,
    /// `lastCheckTime` and `lastCheckCount` updated.
    public var book: Book

    public init(chapters: [BookChapter], book: Book) {
        self.chapters = chapters
        self.book = book
    }
}

/// Parses the table of contents of a book.
public enum BookChapterListAssembler {

    /// Upstream `BookChapterList.analyzeChapterList`.
    public static func analyzeChapterList(
        bookSource: BookSource,
        book: Book,
        baseUrl: String,
        redirectUrl: String,
        body: String?,
        fetch: ChapterPageFetcher? = nil,
        scriptEngine: RuleScriptEngine? = nil
    ) async throws -> ChapterListResult {
        guard let body, !body.isEmpty else {
            throw PipelineError.emptyContent(baseUrl)
        }

        let tocRule = bookSource.tocRule ?? TocRule()
        var visitedUrls = [redirectUrl]
        var reverse = false
        var listRule = tocRule.chapterList ?? ""
        if listRule.hasPrefix("-") {
            reverse = true
            listRule = String(listRule.dropFirst())
        }
        if listRule.hasPrefix("+") {
            listRule = String(listRule.dropFirst())
        }

        var chapterList: [BookChapter] = []
        var page = try analyzePage(
            book: book,
            baseUrl: baseUrl,
            redirectUrl: redirectUrl,
            body: body,
            tocRule: tocRule,
            listRule: listRule,
            bookSource: bookSource,
            getNextUrl: true
        )
        chapterList.append(contentsOf: page.chapters)

        switch page.nextUrls.count {
        case 0:
            break
        case 1:
            // One next page — follow it sequentially.
            var nextUrl = page.nextUrls[0]
            while !nextUrl.isEmpty && !visitedUrls.contains(nextUrl) {
                visitedUrls.append(nextUrl)
                guard let fetch, let nextBody = try? await fetch(nextUrl) else { break }
                page = try analyzePage(
                    book: book,
                    baseUrl: nextUrl,
                    redirectUrl: nextUrl,
                    body: nextBody,
                    tocRule: tocRule,
                    listRule: listRule,
                    bookSource: bookSource,
                    getNextUrl: true
                )
                nextUrl = page.nextUrls.first ?? ""
                chapterList.append(contentsOf: page.chapters)
            }
        default:
            // Several next pages — fetch them in parallel.
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
                        tocRule: tocRule,
                        listRule: listRule,
                        bookSource: bookSource,
                        getNextUrl: false
                    ) {
                        chapterList.append(contentsOf: nextPage.chapters)
                    }
                }
            }
        }

        guard !chapterList.isEmpty else {
            throw PipelineError.tocEmpty
        }

        if !reverse {
            chapterList.reverse()
        }

        // De-duplicate, keeping the original order.
        var seen = Set<BookChapter>()
        var list: [BookChapter] = []
        for chapter in chapterList where seen.insert(chapter).inserted {
            list.append(chapter)
        }
        if !book.reverseToc {
            list.reverse()
        }

        for (index, chapter) in list.enumerated() {
            list[index].index = Int64(index)
        }

        // The optional title formatting script.
        if let formatJs = tocRule.formatJs, !formatJs.isBlank, let scriptEngine {
            for index in list.indices {
                let chapter = list[index]
                let bindings: [String: RuleValue] = [
                    "gInt": .number(0),
                    "index": .number(Double(index + 1)),
                    "chapter": .scriptObject([
                        "title": .text(chapter.title),
                        "url": .text(chapter.url),
                        "index": .number(Double(chapter.index))
                    ]),
                    "title": .text(chapter.title)
                ]
                if let value = try? scriptEngine.evaluate(formatJs, bindings: bindings) {
                    let text = value.textValue
                    if !text.isEmpty { list[index].title = text }
                }
            }
        }

        var book = book
        book.durChapterTitle = list.indices.contains(Int(book.durChapterIndex))
            ? list[Int(book.durChapterIndex)].title
            : list.last?.title
        if book.totalChapterNum < Int64(list.count) {
            book.lastCheckCount = Int64(list.count) - book.totalChapterNum
            book.latestChapterTime = Int64(Date().timeIntervalSince1970 * 1000)
        }
        book.lastCheckTime = Int64(Date().timeIntervalSince1970 * 1000)
        book.totalChapterNum = Int64(list.count)
        book.latestChapterTitle = list.last?.title

        // The upstream Kotlin writes these fields into the book that the caller
        // keeps; Swift passes structs by value, so the updated book travels
        // back with the chapter list.
        return ChapterListResult(chapters: list, book: book)
    }

    // MARK: - One page

    private struct ChapterPage {
        var chapters: [BookChapter]
        var nextUrls: [String]
    }

    /// Upstream `BookChapterList.analyzeChapterList` (the private overload).
    private static func analyzePage(
        book: Book,
        baseUrl: String,
        redirectUrl: String,
        body: String,
        tocRule: TocRule,
        listRule: String,
        bookSource: BookSource,
        getNextUrl: Bool
    ) throws -> ChapterPage {
        let analyzeRule = AnalyzeRule(content: .text(body), baseUrl: baseUrl)
        analyzeRule.setRedirectUrl(redirectUrl)
        analyzeRule.source = bookSource.variableBox

        let elements = try analyzeRule.getElements(listRule)

        // The next page URLs.
        var nextUrlList: [String] = []
        if getNextUrl, let nextTocRule = tocRule.nextTocUrl, !nextTocRule.isEmpty {
            if let urls = try analyzeRule.getStringList(nextTocRule, isUrl: true) {
                for item in urls where item != redirectUrl {
                    nextUrlList.append(item)
                }
            }
        }

        var chapterList: [BookChapter] = []
        if !elements.isEmpty {
            let nameRule = analyzeRule.splitSourceRule(tocRule.chapterName)
            let urlRule = analyzeRule.splitSourceRule(tocRule.chapterUrl)
            let vipRule = analyzeRule.splitSourceRule(tocRule.isVip)
            let payRule = analyzeRule.splitSourceRule(tocRule.isPay)
            let upTimeRule = analyzeRule.splitSourceRule(tocRule.updateTime)
            let isVolumeRule = analyzeRule.splitSourceRule(tocRule.isVolume)

            for (index, item) in elements.enumerated() {
                try analyzeRule.setContent(RuleContent.from(ruleValue: item))
                var bookChapter = BookChapter()
                bookChapter.bookUrl = book.bookUrl
                bookChapter.title = try analyzeRule.getString(nameRule)
                bookChapter.url = try analyzeRule.getString(urlRule)
                bookChapter.tag = try analyzeRule.getString(upTimeRule)
                let isVolume = try analyzeRule.getString(isVolumeRule)
                bookChapter.isVolume = TextFormat.isTrue(isVolume)
                if bookChapter.url.isEmpty {
                    bookChapter.url = bookChapter.isVolume
                        ? bookChapter.title + String(index)
                        : baseUrl
                }
                if !bookChapter.title.isEmpty {
                    bookChapter.isVip = TextFormat.isTrue(try analyzeRule.getString(vipRule))
                    bookChapter.isPay = TextFormat.isTrue(try analyzeRule.getString(payRule))
                    chapterList.append(bookChapter)
                }
            }
        }

        return ChapterPage(chapters: chapterList, nextUrls: nextUrlList)
    }
}
