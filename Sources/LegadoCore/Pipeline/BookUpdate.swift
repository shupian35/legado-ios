//
//  BookUpdate.swift
//  LegadoCore
//
//  The table-of-contents update — upstream `ui/main/MainViewModel.updateToc`
//  (`:149-188`) and `help/book/BookExtensions.kt:238` (`Book.sync`).
//
//  The upstream refreshes the chapter list of a book:
//
//  * the books that are not local and have `canUpdate` are queued;
//  * the queue is processed by `min(threadCount, MAX_THREAD)` workers;
//  * every book: the source is looked up by `book.origin` (a missing source
//    sets the "update failed" bit), the book info is refreshed when the
//    `tocUrl` is blank, the pre-update script runs otherwise, the new
//    chapter list is fetched, the reading progress is carried over, the
//    chapters are replaced and the new chapters are queued for the cache.
//
//  The "new chapters" rule is the upstream one: the new count is compared
//  with the stored `totalChapterNum` — there is no per-chapter diff
//  (`model/webBook/BookChapterList.kt:153-164`).
//

import Foundation

/// The result of one book update.
public struct BookUpdateResult: Equatable, Sendable {
    /// The URL of the updated book.
    public let bookUrl: String
    /// Whether the update succeeded.
    public let isSuccess: Bool
    /// The message — the upstream logs "更新目录失败".
    public let message: String
    /// The number of chapters after the update.
    public let newChapterCount: Int
    /// The number of the new chapters (the upstream `lastCheckCount`).
    public let newChapterCountDelta: Int
    /// The book after the update.
    public let book: Book
    /// The chapter list after the update.
    public let chapters: [BookChapter]

    public init(
        bookUrl: String,
        isSuccess: Bool,
        message: String,
        newChapterCount: Int,
        newChapterCountDelta: Int,
        book: Book,
        chapters: [BookChapter]
    ) {
        self.bookUrl = bookUrl
        self.isSuccess = isSuccess
        self.message = message
        self.newChapterCount = newChapterCount
        self.newChapterCountDelta = newChapterCountDelta
        self.book = book
        self.chapters = chapters
    }

    /// Whether the book has new chapters — the upstream compares the stored
    /// `totalChapterNum` with the size of the new list.
    public var hasNewChapters: Bool { newChapterCountDelta > 0 }
}

/// The table-of-contents update.
public enum BookUpdater {

    /// The maximum number of concurrent updates — upstream
    /// `min(AppConfig.threadCount, AppConst.MAX_THREAD)`.
    public static let maxThreadCount = 9

    /// Updates one book — upstream `MainViewModel.updateToc(bookUrl)`.
    ///
    /// - Parameters:
    ///   - book: the book to update.
    ///   - source: the source of the book; when it is `nil` the source is
    ///     looked up in the store and the book is marked as "update failed"
    ///     when it is missing.
    ///   - store: the store the chapters and the book live in.
    ///   - dependencies: the network dependencies.
    /// - Returns: the result of the update.
    public static func update(
        book: Book,
        source: BookSource?,
        store: LegadoStore,
        dependencies: AnalyzeUrlDependencies
    ) async -> BookUpdateResult {
        let resolvedSource: BookSource?
        if let source {
            resolvedSource = source
        } else {
            resolvedSource = try? store.source(url: book.origin)
        }

        guard let source = resolvedSource else {
            // Upstream: the source is gone → the "update failed" bit.
            var failed = book
            failed.type = failed.type | BookType.updateError
            try? store.update(failed)
            return BookUpdateResult(
                bookUrl: book.bookUrl,
                isSuccess: false,
                message: "书源不存在",
                newChapterCount: 0,
                newChapterCountDelta: 0,
                book: failed,
                chapters: []
            )
        }

        let oldChapters = (try? store.chapters(bookUrl: book.bookUrl)) ?? []
        let oldTotal = Int(book.totalChapterNum)

        do {
            // Upstream: the info is refreshed when the toc URL is blank,
            // otherwise the pre-update script runs.
            var updated = book
            if updated.tocUrl.isEmpty {
                updated = try await WebBook.getBookInfo(
                    bookSource: source,
                    book: updated,
                    dependencies: dependencies
                )
            } else {
                try? await WebBook.runPreUpdateJs(
                    source.tocRule?.preUpdateJs ?? "",
                    bookSource: source,
                    book: updated,
                    dependencies: dependencies
                )
            }

            let result = try await WebBook.getChapterList(
                bookSource: source,
                book: updated,
                dependencies: dependencies
            )
            updated = result.book
            let chapters = result.chapters

            // Upstream `Book.sync(oldBook)`: the reading progress of the
            // stored book wins over the one of the fetched book.
            updated = sync(updated, with: book, chapters: chapters, store: store)
            updated.type = updated.type & ~BookType.updateError

            try store.update(updated)
            // Upstream: the old chapters are deleted wholesale and the new
            // list is inserted — there is no diff.
            try store.deleteChapters(bookUrl: updated.bookUrl)
            try store.insert(chapters)

            let delta = max(0, chapters.count - oldTotal)
            return BookUpdateResult(
                bookUrl: updated.bookUrl,
                isSuccess: true,
                message: "更新成功",
                newChapterCount: chapters.count,
                newChapterCountDelta: delta,
                book: updated,
                chapters: chapters
            )
        } catch {
            // Upstream: the failure sets the "update failed" bit.
            var failed = book
            failed.type = failed.type | BookType.updateError
            try? store.update(failed)
            return BookUpdateResult(
                bookUrl: book.bookUrl,
                isSuccess: false,
                message: "更新目录失败：\(error.localizedDescription)",
                newChapterCount: oldChapters.count,
                newChapterCountDelta: 0,
                book: failed,
                chapters: oldChapters
            )
        }
    }

    /// Carries the reading progress of the stored book over to the fetched
    /// one — upstream `Book.sync(oldBook)`
    /// (`help/book/BookExtensions.kt:238-251`).
    ///
    /// `durChapterTime`, `durChapterPos`, `canUpdate` and `readConfig` are
    /// copied from the stored book; when the chapter index changed, the
    /// title is read again from the new chapter list.
    public static func sync(
        _ book: Book,
        with stored: Book,
        chapters: [BookChapter],
        store: LegadoStore
    ) -> Book {
        var synced = book
        synced.durChapterTime = stored.durChapterTime
        synced.durChapterPos = stored.durChapterPos
        if synced.durChapterIndex != stored.durChapterIndex {
            synced.durChapterIndex = stored.durChapterIndex
            let rules = (try? store.replaceRulesForTitle(
                name: synced.name,
                origin: synced.origin
            )) ?? []
            if let chapter = chapters.first(where: { $0.index == stored.durChapterIndex }) {
                synced.durChapterTitle = (try? ReplaceRuleEngine.displayTitle(
                    chapter,
                    replaceRules: rules,
                    useReplace: synced.useReplaceRule
                )) ?? chapter.title
            }
        }
        synced.canUpdate = stored.canUpdate
        synced.readConfig = stored.readConfig
        return synced
    }

    /// Updates a list of books — upstream `MainViewModel.upToc(books)`.
    ///
    /// The local books and the books with `canUpdate == false` are skipped
    /// (upstream `books.filter { !it.isLocal && it.canUpdate }`); the rest is
    /// processed by `min(threadCount, 9)` workers.
    public static func updateAll(
        books: [Book],
        store: LegadoStore,
        dependencies: AnalyzeUrlDependencies,
        threadCount: Int = 4,
        onUpdate: @escaping @Sendable (BookUpdateResult) -> Void = { _ in }
    ) async -> [BookUpdateResult] {
        let candidates = books.filter { !$0.isLocal && $0.canUpdate }
        guard !candidates.isEmpty else { return [] }

        let limit = max(1, min(threadCount, maxThreadCount))
        return await withTaskGroup(
            of: BookUpdateResult.self,
            returning: [BookUpdateResult].self
        ) { group in
            var collected: [BookUpdateResult] = []
            for book in candidates {
                group.addTask {
                    await update(
                        book: book,
                        source: nil,
                        store: store,
                        dependencies: dependencies
                    )
                }
            }
            while let result = await group.next() {
                collected.append(result)
                onUpdate(result)
            }
            return collected
        }
    }

    /// Whether the reader should check for new chapters — upstream
    /// `ReadBook.upToc()` (`model/ReadBook.kt:863-887`).
    ///
    /// The check is skipped when the book cannot be updated, when at least
    /// three unread chapters are left and when the last check is less than
    /// ten minutes old.
    public static func shouldCheckForNewChapters(
        book: Book,
        unreadChapters: Int,
        now: Date = Date(),
        minimumInterval: TimeInterval = 600
    ) -> Bool {
        guard book.canUpdate else { return false }
        guard unreadChapters < 3 else { return false }
        let lastCheck = TimeInterval(book.lastCheckTime) / 1000
        guard now.timeIntervalSince1970 - lastCheck >= minimumInterval else { return false }
        return true
    }
}
