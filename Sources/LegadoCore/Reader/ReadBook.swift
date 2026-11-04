//
//  ReadBook.swift
//  LegadoCore
//
//  The reading state machine.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/model/ReadBook.kt (1054 lines)
//
//  Upstream is an `object` (a process-wide singleton bound to the Android main
//  thread). The port is an ordinary object owned by the reader screen, so two
//  reader windows can never fight over the same state, and the coroutine work
//  is expressed as `async` functions the caller awaits.
//

import Foundation

/// The events the reader screen listens to.
public protocol ReadBookDelegate: AnyObject {
    /// A chapter was loaded and paginated.
    func readBook(_ readBook: ReadBook, didLoad chapter: TextChapter, position: Int)
    /// The current page changed (page turn, chapter change).
    func readBook(_ readBook: ReadBook, didChangePageIndex index: Int)
    /// The reading progress was persisted.
    func readBook(_ readBook: ReadBook, didSaveProgress book: Book)
    /// Loading failed.
    func readBook(_ readBook: ReadBook, didFail error: Error)
}

/// Persists the reading progress.
///
/// Upstream writes `appDb.bookDao.update(book)`; the port goes through a
/// protocol so the core does not depend on the SQLite implementation.
public protocol ReadProgressPersisting: AnyObject {
    func saveBook(_ book: Book) throws
    func loadChapters(bookUrl: String) throws -> [BookChapter]
}

/// Where the raw chapter text comes from.
public typealias ReadBookContentProvider = ChapterContentProviding

/// The reading state machine of one book.
public final class ReadBook {
    /// The book being read.
    public private(set) var book: Book
    /// The chapter list of the book.
    public private(set) var chapterList: [BookChapter]
    /// The title of the chapter the reader is on.
    public var durChapterTitle: String {
        if chapterList.indices.contains(durChapterIndex) {
            return chapterList[durChapterIndex].title
        }
        return book.durChapterTitle ?? ""
    }

    /// The current chapter index.
    public var durChapterIndex: Int
    /// The current position inside the chapter (a character offset).
    public var durChapterPos: Int
    /// The index of the page currently shown inside the current chapter.
    public private(set) var pageIndex: Int = 0

    /// The chapter currently laid out.
    public private(set) var curTextChapter: TextChapter?
    /// The previous chapter, laid out ahead of time.
    public private(set) var prevTextChapter: TextChapter?
    /// The next chapter, laid out ahead of time.
    public private(set) var nextTextChapter: TextChapter?

    /// The delegate.
    public weak var delegate: ReadBookDelegate?
    /// The persistence layer.
    ///
    /// The reference is strong on purpose: the callers create the persister
    /// inline (`readBook.persister = StoreProgressPersister(store:)`) and a weak
    /// reference would be deallocated immediately, so the progress would never
    /// be written.
    public var persister: ReadProgressPersisting?

    private let contentProvider: ReadBookContentProvider
    private let measurer: TextMeasuring
    private let scriptEngine: RuleScriptEngine?
    private let titleRules: [ReplaceRule]
    private let contentRules: [ReplaceRule]
    private let configProvider: () -> ReaderConfig
    private let layoutProvider: () -> ReaderLayout
    /// The Chinese converter of the content.
    ///
    /// The upstream reloads the converter when the user picks another one
    /// (`ReadStyleDialog.kt:110`: `ChineseUtils.unLoad` +
    /// `EventBus.postEvent(EventBus.UP_CONFIG, arrayListOf(5))`), so the mode
    /// can be changed while the reader is open.
    public var chineseConversionMode: ChineseConversionMode
    private let preDownloadCount: Int

    /// Guards the layout work so a fast page turn cannot interleave two
    /// chapters (upstream uses `curChapterLoadingLock` / `prevChapterLoadingLock`).
    private var loadingLock = false
    private var loadedChapters: [Int: TextChapter] = [:]

    public init(
        book: Book,
        chapterList: [BookChapter],
        contentProvider: ReadBookContentProvider,
        measurer: TextMeasuring,
        scriptEngine: RuleScriptEngine? = nil,
        titleRules: [ReplaceRule] = [],
        contentRules: [ReplaceRule] = [],
        configProvider: @escaping () -> ReaderConfig,
        layoutProvider: @escaping () -> ReaderLayout,
        preDownloadCount: Int = 1,
        chineseConversionMode: ChineseConversionMode = .off
    ) {
        self.book = book
        self.chapterList = chapterList
        self.contentProvider = contentProvider
        self.measurer = measurer
        self.scriptEngine = scriptEngine
        self.titleRules = titleRules
        self.contentRules = contentRules
        self.configProvider = configProvider
        self.layoutProvider = layoutProvider
        self.chineseConversionMode = chineseConversionMode
        self.preDownloadCount = max(0, preDownloadCount)
        self.durChapterIndex = max(0, min(Int(book.durChapterIndex), max(0, chapterList.count - 1)))
        self.durChapterPos = Int(book.durChapterPos)
    }

    // MARK: - Loading

    /// Loads the chapter the reader is on (upstream `contentLoadFinish`).
    public func loadCurrentChapter() async {
        guard !loadingLock else { return }
        loadingLock = true
        defer { loadingLock = false }
        do {
            let chapter = try await loadChapter(at: durChapterIndex)
            curTextChapter = chapter
            // Restore the page that holds the saved position
            // (upstream `ReadBook.getPageIndex`).
            pageIndex = chapter.pageIndex(forCharacterIndex: durChapterPos)
            delegate?.readBook(self, didLoad: chapter, position: pageIndex)
            delegate?.readBook(self, didChangePageIndex: pageIndex)
        } catch {
            delegate?.readBook(self, didFail: error)
        }
    }

    /// Lays the chapters out again.
    ///
    /// The page size changed (the device was rotated, the font was changed) —
    /// the cached layouts are dropped and the current chapter is laid out
    /// again, keeping the reading position.
    public func reloadCurrentChapter() async {
        loadedChapters.removeAll()
        prevTextChapter = nil
        nextTextChapter = nil
        await loadCurrentChapter()
    }

    /// Loads the chapter at `index`, reusing the cached layout when possible.
    @discardableResult
    public func loadChapter(at index: Int) async throws -> TextChapter {
        if let cached = loadedChapters[index] { return cached }
        guard chapterList.indices.contains(index) else {
            throw ChapterProviderError.emptyContent
        }
        let chapter = chapterList[index]
        let textChapter = try await ChapterProvider.textChapter(
            book: book,
            chapter: chapter,
            chaptersSize: chapterList.count,
            contentProvider: contentProvider,
            titleRules: titleRules,
            contentRules: contentRules,
            scriptEngine: scriptEngine,
            config: configProvider(),
            layout: layoutProvider(),
            measurer: measurer,
            chineseConversionMode: chineseConversionMode
        )
        loadedChapters[index] = textChapter
        return textChapter
    }

    /// Lays out the neighbouring chapters in the background
    /// (upstream `preDownload` / the `nextChapter`/`prevChapter` mutexes).
    public func preloadNeighbours() async {
        let wanted = [durChapterIndex + 1, durChapterIndex - 1]
        for index in wanted where chapterList.indices.contains(index) {
            guard loadedChapters[index] == nil else { continue }
            _ = try? await loadChapter(at: index)
        }
        nextTextChapter = loadedChapters[durChapterIndex + 1]
        prevTextChapter = loadedChapters[durChapterIndex - 1]
    }

    /// Pre-fetches the text of the following chapters (upstream
    /// `ReadBook.preDownload`, which stops after three failures per chapter).
    public func preDownload() async {
        let end = min(chapterList.count, durChapterIndex + 1 + preDownloadCount)
        guard end > durChapterIndex + 1 else { return }
        for index in (durChapterIndex + 1)..<end {
            let chapter = chapterList[index]
            _ = try? await contentProvider.chapterContent(book: book, chapter: chapter)
        }
    }

    // MARK: - The new chapters

    /// Checks whether the book has new chapters — upstream `ReadBook.upToc()`
    /// (`model/ReadBook.kt:863-887`).
    ///
    /// The check is skipped when the book cannot be updated, when at least
    /// three unread chapters are left and when the last check is less than
    /// ten minutes old. When the new chapter list is longer, the list is
    /// replaced and the progress is kept.
    ///
    /// - Parameter refresher: fetches the new chapter list; `nil` disables
    ///   the check (the default, because the core does not do any I/O).
    /// - Returns: the number of the new chapters, or `nil` when there was no
    ///   check.
    @discardableResult
    public func checkForNewChapters(
        refresher: ((Book) async throws -> [BookChapter])?
    ) async -> Int? {
        guard let refresher else { return nil }
        let unread = chapterList.count - durChapterIndex - 1
        guard BookUpdater.shouldCheckForNewChapters(book: book, unreadChapters: unread) else {
            return nil
        }
        // The upstream stamps the check time BEFORE the request.
        var stamped = book
        stamped.lastCheckTime = Int64(Date().timeIntervalSince1970 * 1000)
        book = stamped
        guard let chapters = try? await refresher(book), chapters.count > chapterList.count else {
            return nil
        }
        chapterList = chapters
        book.totalChapterNum = Int64(chapters.count)
        book.lastCheckCount = Int64(chapters.count - Int(book.totalChapterNum))
        await loadCurrentChapter()
        return chapters.count
    }

    /// Replaces the chapter list and lays the current chapter out again —
    /// upstream `ReadBookActivity.onTocRegexDialogResult` → `loadChapterList`.
    public func replaceChapterList(_ chapters: [BookChapter]) async {
        chapterList = chapters
        book.totalChapterNum = Int64(chapters.count)
        loadedChapters.removeAll()
        curTextChapter = nil
        prevTextChapter = nil
        nextTextChapter = nil
        loadingLock = false
        await loadCurrentChapter()
    }

    // MARK: - Navigation

    /// Opens the chapter at `index` (upstream `ReadBook.openChapter`).
    public func openChapter(index: Int, position: Int = 0) async {
        guard chapterList.indices.contains(index) else { return }
        if index != durChapterIndex {
            await saveRead(pageChanged: true)
        }
        durChapterIndex = index
        durChapterPos = position
        curTextChapter = nil
        loadingLock = false
        await loadCurrentChapter()
        await preloadNeighbours()
        await preDownload()
    }

    /// Goes to the next chapter; returns `false` when there is none.
    @discardableResult
    public func moveToNextChapter() async -> Bool {
        guard durChapterIndex + 1 < chapterList.count else { return false }
        await openChapter(index: durChapterIndex + 1)
        return true
    }

    /// Goes to the previous chapter; returns `false` when there is none.
    @discardableResult
    public func moveToPrevChapter() async -> Bool {
        guard durChapterIndex > 0 else { return false }
        await openChapter(index: durChapterIndex - 1)
        return true
    }

    /// Records the page the reader moved to.
    public func updatePageIndex(_ index: Int) {
        guard let chapter = curTextChapter else { return }
        pageIndex = max(0, min(index, max(0, chapter.pageSize - 1)))
        durChapterPos = chapter.readLength(pageIndex: pageIndex)
        delegate?.readBook(self, didChangePageIndex: pageIndex)
    }

    /// Moves the reading position to a character offset inside the current
    /// chapter — upstream `ReadBook.durChapterPos = chapterStart` (the read
    /// aloud follows the spoken paragraph).
    public func moveToPosition(_ position: Int) {
        guard let chapter = curTextChapter else { return }
        durChapterPos = max(0, position)
        pageIndex = chapter.pageIndex(forCharacterIndex: durChapterPos)
        delegate?.readBook(self, didChangePageIndex: pageIndex)
    }

    // MARK: - Progress

    /// Persists the reading progress (upstream `ReadBook.saveRead`).
    public func saveRead(pageChanged: Bool) async {
        book.durChapterIndex = Int64(durChapterIndex)
        book.durChapterPos = Int64(durChapterPos)
        book.durChapterTitle = durChapterTitle
        book.durChapterTime = Int64(Date().timeIntervalSince1970 * 1000)
        if pageChanged {
            book.lastCheckTime = Int64(Date().timeIntervalSince1970 * 1000)
        }
        do {
            try persister?.saveBook(book)
            delegate?.readBook(self, didSaveProgress: book)
        } catch {
            delegate?.readBook(self, didFail: error)
        }
    }

    /// Merges a remote progress into the local one, choosing the further of the
    /// two (upstream `ReadBook.syncProgress`).
    public func mergeRemoteProgress(_ remote: BookProgress) -> Bool {
        let remoteIndex = Int(remote.durChapterIndex)
        let remotePos = Int(remote.durChapterPos)
        let remoteIsFurther = remoteIndex > durChapterIndex
            || (remoteIndex == durChapterIndex && remotePos > durChapterPos)
        guard remoteIsFurther else { return false }
        durChapterIndex = max(0, min(remoteIndex, max(0, chapterList.count - 1)))
        durChapterPos = max(0, remotePos)
        return true
    }

    /// The reading progress as a 0…1 fraction.
    public var progress: Double {
        guard let chapter = curTextChapter, chapter.pageSize > 0, chapter.chaptersSize > 0 else {
            return 0
        }
        return Double(chapter.position) / Double(chapter.chaptersSize)
            + 1.0 / Double(chapter.chaptersSize) * Double(pageIndex + 1) / Double(chapter.pageSize)
    }
}
