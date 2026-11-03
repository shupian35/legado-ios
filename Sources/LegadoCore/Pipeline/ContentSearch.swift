//
//  ContentSearch.swift
//  LegadoCore
//
//  The content search (搜索正文).
//
//  Upstream `ui/book/searchContent/SearchContentViewModel.kt` (108 lines)
//  and `SearchResult.kt` (61 lines):
//
//  * only the CACHED chapters are searched (`BookHelp.getContent` returns the
//    cached file, `null` when the chapter was never downloaded);
//  * the search is a plain, case SENSITIVE substring search; the matches do
//    not overlap;
//  * the searched text is the PROCESSED text (the chapter title is
//    prepended, the replace rules and the Chinese conversion are applied);
//    the QUERY itself is never converted;
//  * every result shows ±20 characters around the match.
//
//  The port reproduces that behaviour; the UI lives in `LegadoUI`.
//

import Foundation

/// One result of the content search.
public struct ContentSearchResult: Equatable, Sendable {
    /// The number of the result over all the chapters.
    public var resultCount: Int
    /// The number of the result inside its chapter.
    public var resultCountWithinChapter: Int
    /// The text around the match.
    public var resultText: String
    /// The title of the chapter.
    public var chapterTitle: String
    /// The query.
    public var query: String
    /// The number of the pages of the chapter.
    public var pageSize: Int
    /// The index of the chapter.
    public var chapterIndex: Int
    /// The index of the page the match is on.
    public var pageIndex: Int
    /// The offset of the query inside `resultText`.
    public var queryIndexInResult: Int
    /// The offset of the query inside the chapter.
    public var queryIndexInChapter: Int

    public init(
        resultCount: Int = 0,
        resultCountWithinChapter: Int = 0,
        resultText: String = "",
        chapterTitle: String = "",
        query: String = "",
        pageSize: Int = 0,
        chapterIndex: Int = 0,
        pageIndex: Int = 0,
        queryIndexInResult: Int = 0,
        queryIndexInChapter: Int = 0
    ) {
        self.resultCount = resultCount
        self.resultCountWithinChapter = resultCountWithinChapter
        self.resultText = resultText
        self.chapterTitle = chapterTitle
        self.query = query
        self.pageSize = pageSize
        self.chapterIndex = chapterIndex
        self.pageIndex = pageIndex
        self.queryIndexInResult = queryIndexInResult
        self.queryIndexInChapter = queryIndexInChapter
    }
}

/// The options of the content search.
public struct ContentSearchOptions: Equatable, Sendable {
    /// Whether the replace rules are applied to the searched text.
    public var useReplaceRule: Bool
    /// The Chinese conversion of the searched text.
    public var chineseConversionMode: ChineseConversionMode
    /// The number of characters shown around the match.
    public var contextLength: Int

    public init(
        useReplaceRule: Bool = false,
        chineseConversionMode: ChineseConversionMode = .off,
        contextLength: Int = 20
    ) {
        self.useReplaceRule = useReplaceRule
        self.chineseConversionMode = chineseConversionMode
        self.contextLength = contextLength
    }
}

/// The content search.
public enum ContentSearcher {

    /// The positions of the (non overlapping) matches of the pattern.
    public static func positions(of pattern: String, in content: String) -> [Int] {
        guard !pattern.isEmpty else { return [] }
        var result: [Int] = []
        var searchStart = content.startIndex
        while searchStart < content.endIndex {
            guard let range = content.range(of: pattern, range: searchStart..<content.endIndex) else { break }
            result.append(content.distance(from: content.startIndex, to: range.lowerBound))
            let next = content.index(range.lowerBound, offsetBy: pattern.count)
            searchStart = next
        }
        return result
    }

    /// The text around the match and the offset of the query inside it.
    public static func resultAndQueryIndex(
        content: String,
        queryIndex: Int,
        query: String,
        contextLength: Int = 20
    ) -> (index: Int, text: String) {
        let lower = max(0, queryIndex - contextLength)
        let upper = min(content.count, queryIndex + query.count + contextLength)
        let start = content.index(content.startIndex, offsetBy: lower)
        let end = content.index(content.startIndex, offsetBy: upper)
        return (queryIndex - lower, String(content[start..<end]))
    }

    /// Searches one chapter.
    ///
    /// - Parameters:
    ///   - query: the query (never converted).
    ///   - chapter: the chapter.
    ///   - content: the PROCESSED text of the chapter.
    ///   - chapterTitle: the (converted) title of the chapter.
    public static func searchChapter(
        query: String,
        chapter: BookChapter,
        content: String,
        chapterTitle: String,
        options: ContentSearchOptions = ContentSearchOptions()
    ) -> [ContentSearchResult] {
        let positions = positions(of: query, in: content)
        return positions.enumerated().map { index, position in
            let constructed = resultAndQueryIndex(
                content: content,
                queryIndex: position,
                query: query,
                contextLength: options.contextLength
            )
            return ContentSearchResult(
                resultCountWithinChapter: index,
                resultText: constructed.text,
                chapterTitle: chapterTitle,
                query: query,
                chapterIndex: Int(chapter.index),
                queryIndexInResult: constructed.index,
                queryIndexInChapter: position
            )
        }
    }

    /// Searches the cached chapters of a book.
    ///
    /// - Parameters:
    ///   - book: the book.
    ///   - chapters: the chapters to search (only the cached ones are read).
    ///   - query: the query.
    ///   - storage: the cache that holds the downloaded chapters.
    ///   - titleRules: the replace rules of the titles.
    ///   - contentRules: the replace rules of the content.
    public static func search(
        book: Book,
        chapters: [BookChapter],
        query: String,
        storage: BookCacheStorage,
        titleRules: [ReplaceRule] = [],
        contentRules: [ReplaceRule] = [],
        options: ContentSearchOptions = ContentSearchOptions(),
        scriptEngine: RuleScriptEngine? = nil
    ) -> [ContentSearchResult] {
        guard !query.isEmpty else { return [] }
        var results: [ContentSearchResult] = []
        var total = 0
        for chapter in chapters {
            // Only the cached chapters are searched.
            guard let raw = storage.content(book: book, chapter: chapter) else { continue }
            var title = chapter.title
            switch options.chineseConversionMode {
            case .traditionalToSimplified:
                title = ChineseConverter.toSimplified(title)
            case .simplifiedToTraditional:
                title = ChineseConverter.toTraditional(title)
            case .off:
                break
            }
            let processed = (try? ReplaceRuleEngine.processContent(
                book: book,
                chapter: chapter,
                content: raw,
                includeTitle: true,
                useReplace: options.useReplaceRule,
                chineseConvert: options.chineseConversionMode != .off,
                reSegment: false,
                titleRules: titleRules,
                contentRules: contentRules,
                conversionMode: options.chineseConversionMode,
                converter: DefaultChineseConverter(),
                scriptEngine: scriptEngine
            ))?.contents.joined(separator: "\n") ?? raw
            let hits = searchChapter(
                query: query,
                chapter: chapter,
                content: processed,
                chapterTitle: title,
                options: options
            )
            for var hit in hits {
                total += 1
                hit.resultCount = total
                results.append(hit)
            }
        }
        return results
    }
}
