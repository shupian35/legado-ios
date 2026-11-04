//
//  ChangeChapterSource.swift
//  LegadoCore
//
//  Changing the source of ONE chapter (章节换源).
//
//  Upstream `ui/book/changesource/ChangeChapterSourceDialog.kt` (414 lines)
//  and `ChangeChapterSourceViewModel.kt` (46 lines):
//
//  * the same search as the change-source dialog finds the book in the other
//    sources;
//  * tapping a result loads the table of contents of THAT book and finds the
//    chapter that matches the current one
//    (`BookHelp.getDurChapter(chapterIndex, chapterTitle, toc)`);
//  * tapping a chapter of the new list fetches the content of that chapter
//    from the other source (`WebBook.getContentAwait`) and the reader replaces
//    the content of the chapter it is showing with it
//    (`ReadBookViewModel.saveContent`).
//
//  The port keeps the logic in `LegadoCore` so that it can be tested on
//  Linux; the UI lives in `LegadoUI`.
//

import Foundation

/// One chapter of another source — the candidate of the per-chapter change.
public struct ChapterSourceMatch: Equatable, Sendable {

    /// The book of the other source.
    public var book: Book
    /// The URL of the source of the book.
    public var sourceUrl: String
    /// The name of the source of the book.
    public var sourceName: String
    /// The table of contents of the other source.
    public var toc: [BookChapter]
    /// The index of the chapter that matches the current one (the upstream
    /// `BookHelp.getDurChapter`).
    public var durChapterIndex: Int

    public init(
        book: Book,
        sourceUrl: String,
        sourceName: String,
        toc: [BookChapter],
        durChapterIndex: Int
    ) {
        self.book = book
        self.sourceUrl = sourceUrl
        self.sourceName = sourceName
        self.toc = toc
        self.durChapterIndex = durChapterIndex
    }
}

/// The service of the per-chapter source change.
public enum ChangeChapterSourceService {

    /// The error of the per-chapter source change.
    public enum Error: Swift.Error, Equatable {
        /// The source of the book is not known (the upstream
        /// `NoStackTraceException("书源不存在")`).
        case sourceNotFound
        /// The chapter could not be fetched (the upstream "获取正文出错").
        case contentFailed(String)
    }

    /// Loads the table of contents of a candidate and finds the chapter that
    /// matches the current one.
    ///
    /// Upstream `ChangeChapterSourceDialog.openToc(searchBook)`:
    /// `viewModel.getToc(book, …)` and then
    /// `BookHelp.getDurChapter(chapterIndex, chapterTitle, toc)`.
    ///
    /// - Parameters:
    ///   - candidate: the result of the change-source search.
    ///   - source: the source of the candidate.
    ///   - chapterIndex: the index of the chapter the reader is on.
    ///   - chapterTitle: the title of the chapter the reader is on.
    ///   - oldChapterCount: the number of chapters of the current book (the
    ///     upstream `BookHelp.getDurChapter` uses it to estimate the position).
    ///   - dependencies: the network dependencies.
    public static func loadMatch(
        candidate: ChangeSourceCandidate,
        source: BookSource,
        chapterIndex: Int,
        chapterTitle: String?,
        oldChapterCount: Int = 0,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> ChapterSourceMatch {
        var book = candidate.book
        var toc = candidate.toc ?? []
        if toc.isEmpty {
            // The upstream always loads the table of contents of the other
            // source — the candidate of the search may not have one.
            let result = try await WebBook.getChapterList(
                bookSource: source,
                book: book,
                dependencies: dependencies
            )
            book = result.book
            toc = result.chapters
        }
        let index = ChapterProgressMapper.durChapter(
            oldIndex: chapterIndex,
            oldTitle: chapterTitle,
            newToc: toc,
            oldCount: oldChapterCount
        )
        return ChapterSourceMatch(
            book: book,
            sourceUrl: candidate.sourceUrl,
            sourceName: candidate.sourceName,
            toc: toc,
            durChapterIndex: index
        )
    }

    /// Fetches the content of a chapter of another source.
    ///
    /// Upstream `ChangeChapterSourceViewModel.getContent(book, chapter,
    /// nextChapterUrl, success, error)`:
    /// `WebBook.getContentAwait(bookSource, book, chapter, nextChapterUrl,
    /// false)`.
    ///
    /// - Parameters:
    ///   - match: the match of the chapter (the book of the other source).
    ///   - source: the source of the other book.
    ///   - chapter: the chapter of the other source.
    ///   - nextChapterUrl: the URL of the next chapter of the other source.
    ///   - dependencies: the network dependencies.
    public static func content(
        match: ChapterSourceMatch,
        source: BookSource,
        chapter: BookChapter,
        nextChapterUrl: String? = nil,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> String {
        do {
            return try await WebBook.getContent(
                bookSource: source,
                book: match.book,
                bookChapter: chapter,
                nextChapterUrl: nextChapterUrl,
                dependencies: dependencies
            )
        } catch {
            throw Error.contentFailed(error.localizedDescription)
        }
    }

    /// The URL of the next chapter of the other source (the upstream
    /// `nextChapterUrl` of the chapter list).
    public static func nextChapterUrl(in toc: [BookChapter], after index: Int) -> String? {
        guard toc.indices.contains(index) else { return nil }
        let next = index + 1
        guard toc.indices.contains(next) else { return nil }
        return toc[next].url
    }
}
