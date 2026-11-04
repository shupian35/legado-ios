import Foundation

/// The on-disk layout of the chapter cache — the port of upstream
/// `help/book/BookHelp.kt` (`cacheFolderName = "book_cache"`) plus
/// `Book.getFolderName()` (`data/entities/Book.kt:309-316`) and
/// `BookChapter.getFileName()` (`data/entities/BookChapter.kt:164-167`).
///
/// ```
/// <root>/<folderName>/<index 05d>-<md5(title) 16>.nb      — the chapter text
/// <root>/<folderName>/images/<md5(src) 16>.<suffix>      — a cached image
/// ```
///
/// The folder name is `min(9, name) + md5Encode16(bookUrl)`, so two books with
/// the same title never collide and a rename keeps its cache while the URL is
/// unchanged.
public struct BookCacheLayout: Equatable, Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// The `[\\/:*?"<>|.]` characters upstream strips out of a file name.
    /// `AppPattern.fileNameRegex` (`constant/AppPattern.kt:19`).
    public static let illegalFileNameCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|.")

    /// The folder of one book — upstream `Book.getFolderNameNoCache()`.
    public static func folderName(for book: Book) -> String {
        let cleaned = book.name.components(separatedBy: illegalFileNameCharacters).joined()
        let prefix = String(cleaned.prefix(9))
        return prefix + ScriptDigest.md5Encode16(book.bookUrl)
    }

    /// The file of one chapter — upstream `BookChapter.getFileName("nb")`.
    public static func chapterFileName(for chapter: BookChapter) -> String {
        let title = chapter.titleMD5 ?? ScriptDigest.md5Encode16(chapter.title)
        let index = String(format: "%05d", Int32(truncatingIfNeeded: chapter.index))
        return "\(index)-\(title).nb"
    }

    /// The file of one image — upstream `BookHelp.getImage(book, src)`.
    public static func imageFileName(for src: String) -> String {
        let suffix = BookExporter.imageSuffix(for: src)
        return "\(ScriptDigest.md5Encode16(src)).\(suffix)"
    }

    public func folder(for book: Book) -> URL {
        root.appendingPathComponent(Self.folderName(for: book), isDirectory: true)
    }

    public func chapterFile(book: Book, chapter: BookChapter) -> URL {
        folder(for: book).appendingPathComponent(Self.chapterFileName(for: chapter))
    }

    public func imagesFolder(for book: Book) -> URL {
        folder(for: book).appendingPathComponent("images", isDirectory: true)
    }

    public func imageFile(book: Book, src: String) -> URL {
        imagesFolder(for: book).appendingPathComponent(Self.imageFileName(for: src))
    }
}

/// The chapter text cache — the port of upstream `BookHelp`'s
/// `getContent` / `saveText` / `delContent` / `hasContent` / `getImage` /
/// `writeImage` family.
///
/// This is a plain synchronous file store: the reader and the downloader both
/// touch it, and the downloader is the only writer for downloaded chapters.
public final class BookCacheStorage: @unchecked Sendable {
    public let layout: BookCacheLayout
    private let fileManager: FileManager

    public init(layout: BookCacheLayout, fileManager: FileManager = .default) {
        self.layout = layout
        self.fileManager = fileManager
    }

    // MARK: - Chapter text

    /// Upstream `BookHelp.hasContent`.
    public func hasContent(book: Book, chapter: BookChapter) -> Bool {
        if book.isLocalTxt { return true }
        if chapter.isVolume && chapter.url.hasPrefix(chapter.title) { return true }
        return fileManager.fileExists(atPath: layout.chapterFile(book: book, chapter: chapter).path)
    }

    /// Upstream `BookHelp.getContent`. An empty file reads as nil, exactly like
    /// upstream's `if (string.isEmpty()) return null`.
    public func content(book: Book, chapter: BookChapter) -> String? {
        let file = layout.chapterFile(book: book, chapter: chapter)
        guard let data = try? Data(contentsOf: file) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    /// Upstream `BookHelp.saveText`. An empty content is not written.
    public func saveText(book: Book, chapter: BookChapter, content: String) throws {
        guard !content.isEmpty else { return }
        let file = layout.chapterFile(book: book, chapter: chapter)
        try fileManager.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(content.utf8).write(to: file, options: .atomic)
    }

    /// Upstream `BookHelp.delContent`.
    public func deleteContent(book: Book, chapter: BookChapter) {
        try? fileManager.removeItem(at: layout.chapterFile(book: book, chapter: chapter))
    }

    // MARK: - The duplicated title

    /// The marker file that keeps the duplicated title of a chapter — upstream
    /// `BookHelp.setRemoveSameTitle` (the chapter file name with the "nr"
    /// suffix).
    public func sameTitleMarker(book: Book, chapter: BookChapter) -> URL {
        let name = BookCacheLayout.chapterFileName(for: chapter)
        let base = name.hasSuffix(".nb") ? String(name.dropLast(3)) : name
        return layout.folder(for: book).appendingPathComponent(base + ".nr")
    }

    /// Whether the duplicated title is removed for the chapter — upstream
    /// `BookHelp.removeSameTitle` (the marker file exists ⇒ the title is
    /// kept).
    public func isSameTitleRemoved(book: Book, chapter: BookChapter) -> Bool {
        !fileManager.fileExists(atPath: sameTitleMarker(book: book, chapter: chapter).path)
    }

    /// Sets whether the duplicated title is removed for the chapter — upstream
    /// `BookHelp.setRemoveSameTitle`.
    public func setSameTitleRemoved(book: Book, chapter: BookChapter, removed: Bool) {
        let marker = sameTitleMarker(book: book, chapter: chapter)
        if removed {
            try? fileManager.removeItem(at: marker)
        } else {
            try? fileManager.createDirectory(
                at: marker.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try? Data().write(to: marker, options: .atomic)
        }
    }

    /// The names of the chapter files already cached for a book — upstream
    /// `BookHelp.getChapterFiles`. A local TXT book keeps nothing on disk.
    public func chapterFileNames(book: Book) -> Set<String> {
        if book.isLocalTxt { return [] }
        let folder = layout.folder(for: book)
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder.path) else {
            return []
        }
        return Set(names)
    }

    // MARK: - Images

    /// Upstream `BookHelp.isImageExist`.
    public func hasImage(book: Book, src: String) -> Bool {
        fileManager.fileExists(
            atPath: layout.imageFile(book: book, src: src).path
        )
    }

    public func image(book: Book, src: String) -> Data? {
        try? Data(contentsOf: layout.imageFile(book: book, src: src))
    }

    /// Upstream `BookHelp.writeImage`.
    public func saveImage(book: Book, src: String, data: Data) throws {
        let file = layout.imageFile(book: book, src: src)
        try fileManager.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: file, options: .atomic)
    }

    /// Deletes the cached image — the "refresh the image" action of the image
    /// menu (upstream `ReadBookViewModel.refreshImage`) needs it.
    public func deleteImage(book: Book, src: String) {
        let file = layout.imageFile(book: book, src: src)
        try? fileManager.removeItem(at: file)
    }

    /// Upstream `BookHelp.hasImageContent`: the chapter is cached *and* every
    /// `<img src>` in it has a file on disk.
    public func hasImageContent(book: Book, chapter: BookChapter) -> Bool {
        guard hasContent(book: book, chapter: chapter) else { return false }
        guard let text = content(book: book, chapter: chapter) else { return false }
        for src in Self.imageSources(in: text, chapterURL: chapter.url) {
            if !hasImage(book: book, src: src) { return false }
        }
        return true
    }

    /// The absolute image sources of a chapter — upstream `BookHelp.flowImages`
    /// (`BookHelp.kt:200-209`): every `<img src>` resolved against the chapter
    /// URL. The capture group of `AppPattern.imgPattern` is the raw `src`.
    public static func imageSources(in content: String, chapterURL: String) -> [String] {
        var sources: [String] = []
        let ns = content as NSString
        let matches = RulePatterns.compiledImgPattern.matches(
            in: content,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        )
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            let src = ns.substring(with: match.range(at: 1))
            guard !src.isEmpty else { continue }
            sources.append(NetworkUtils.absoluteURL(base: chapterURL, src))
        }
        return sources
    }

    /// The chapter files of a book whose text is present — the UI's
    /// "downloaded" set.
    public func cachedChapters(
        book: Book,
        chapters: [BookChapter]
    ) -> [BookChapter] {
        chapters.filter { hasContent(book: book, chapter: $0) }
    }

    /// Deletes every cached chapter of a book — upstream `BookHelp.clearCache`.
    public func clearCache(book: Book) {
        try? fileManager.removeItem(at: layout.folder(for: book))
    }

    /// Deletes the whole cache — upstream `BookHelp.clearCache()` (the version
    /// without a book: it removes the cache folder of every book).
    public func clearAllCache() {
        try? fileManager.removeItem(at: layout.root)
        try? fileManager.createDirectory(at: layout.root, withIntermediateDirectories: true)
    }
}

/// The progress of one download batch.
public struct CacheBookProgress: Equatable, Sendable {
    public var waiting: Int
    public var downloading: Int
    public var failed: Int
    public var succeeded: Int

    public init(waiting: Int = 0, downloading: Int = 0, failed: Int = 0, succeeded: Int = 0) {
        self.waiting = waiting
        self.downloading = downloading
        self.failed = failed
        self.succeeded = succeeded
    }

    public var isIdle: Bool { waiting == 0 && downloading == 0 }

    /// Upstream `CacheBook.downloadSummary`.
    public var summary: String {
        "正在下载:\(downloading)|等待中:\(waiting)|失败:\(failed)|成功:\(succeeded)"
    }
}

public enum CacheBookError: Error, Equatable {
    case noBook(String)
    case noBookSource(String)
    case emptyContent(String)
}

/// Downloads whole books into the chapter cache — the port of upstream
/// `model/CacheBook.kt` (417 lines).
///
/// Upstream is a process-wide `object` guarded by `@Synchronized` methods and
/// driven by a `CacheBookService` foreground service. Here it is an actor: the
/// same mutations are serialized, but the caller decides when work runs
/// (`run()` drains until idle, `start(book:start:end:)` merely enqueues).
///
/// Reproduced upstream behaviour:
/// * a chapter already on `downloading` is never queued twice;
/// * a volume chapter is skipped (it has no content) but still counts;
/// * a missing chapter row is dropped silently;
/// * a chapter whose text *and* images are cached is skipped entirely;
/// * a chapter with text but missing images only re-fetches the images;
/// * a failed chapter is retried up to `maxRetries` times, `retryDelay` apart,
///   and only then counted as failed;
/// * the success / failure sets are keyed by `bookUrl + url`
///   (`BookChapter.primaryStr()`) and survive across books;
/// * `summary` reads `正在下载:…|等待中:…|失败:…|成功:…`.
public actor CacheBookManager {

    public struct Configuration: Sendable {
        /// Upstream `AppConfig.threadCount` (default 16) clamped by
        /// `AppConst.MAX_THREAD` (9) in `CacheBookService`.
        public var threadCount: Int = 3
        public var maxRetries: Int = 3
        public var retryDelay: TimeInterval = 1
        /// Whether images are cached alongside the text.
        public var cacheImages: Bool = true

        public init(
            threadCount: Int = 3,
            maxRetries: Int = 3,
            retryDelay: TimeInterval = 1,
            cacheImages: Bool = true
        ) {
            self.threadCount = max(1, threadCount)
            self.maxRetries = maxRetries
            self.retryDelay = retryDelay
            self.cacheImages = cacheImages
        }
    }

    /// Fetches one chapter's content. Defaults to `WebBook.getContent`.
    public typealias ContentFetcher = @Sendable (BookSource, Book, BookChapter) async throws -> String
    /// Fetches one image's bytes.
    public typealias ImageFetcher = @Sendable (BookSource, String) async throws -> Data

    private struct BookTask {
        var book: Book
        var source: BookSource
        var order: [Int]
        var queued: Set<Int>
        var downloading: Set<Int>
        var stopped: Bool
    }

    private var tasks: [String: BookTask] = [:]
    private let chapterLoader: @Sendable (String, Int) throws -> BookChapter?
    private let contentFetcher: ContentFetcher
    private let imageFetcher: ImageFetcher?
    public let storage: BookCacheStorage
    public var configuration: Configuration

    /// Keyed by `bookUrl + chapterUrl` — upstream `successDownloadSet`.
    public private(set) var succeeded: Set<String> = []
    /// Keyed by `bookUrl + chapterUrl` — upstream `errorDownloadMap`.
    public private(set) var failureCounts: [String: Int] = [:]
    /// The message of the last failure per chapter, for the UI's error list.
    public private(set) var failures: [String: String] = [:]

    public init(
        storage: BookCacheStorage,
        configuration: Configuration = Configuration(),
        chapterLoader: @escaping @Sendable (String, Int) throws -> BookChapter?,
        contentFetcher: @escaping ContentFetcher = { source, book, chapter in
            try await WebBook.getContent(bookSource: source, book: book, bookChapter: chapter)
        },
        imageFetcher: ImageFetcher? = nil
    ) {
        self.storage = storage
        self.configuration = configuration
        self.chapterLoader = chapterLoader
        self.contentFetcher = contentFetcher
        self.imageFetcher = imageFetcher
    }

    public func setConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
    }

    // MARK: - Enqueueing

    /// Upstream `CacheBook.start` — a local book is never downloaded; an
    /// unknown book or source is refused.
    public func start(book: Book, source: BookSource, start: Int, end: Int) throws {
        guard !book.isLocal else { return }
        guard !book.bookUrl.isEmpty else { throw CacheBookError.noBook(book.bookUrl) }
        guard !source.bookSourceUrl.isEmpty else {
            throw CacheBookError.noBookSource(book.origin)
        }
        addDownload(book: book, source: source, start: start, end: end)
    }

    /// Upstream `CacheBookModel.addDownload`: enqueue a range, skipping the
    /// chapters that are already downloading, and un-stop the batch.
    public func addDownload(book: Book, source: BookSource, start: Int, end: Int) {
        guard start <= end else { return }
        var task = tasks[book.bookUrl] ?? BookTask(
            book: book,
            source: source,
            order: [],
            queued: [],
            downloading: [],
            stopped: false
        )
        task.book = book
        task.source = source
        task.stopped = false
        for index in start...end where !task.downloading.contains(Int(index)) {
            if task.queued.insert(Int(index)).inserted {
                task.order.append(index)
            }
        }
        tasks[book.bookUrl] = task
    }

    /// Upstream `CacheBook.remove`.
    public func remove(bookUrl: String) {
        tasks.removeValue(forKey: bookUrl)
    }

    /// Upstream `CacheBookModel.stop` — drops the queue but keeps the counters.
    public func stop(bookUrl: String) {
        guard var task = tasks[bookUrl] else { return }
        task.order.removeAll()
        task.queued.removeAll()
        task.stopped = true
        tasks[bookUrl] = task
    }

    /// Upstream `CacheBook.stop` for every book.
    public func stopAll() {
        for key in tasks.keys { stop(bookUrl: key) }
    }

    /// Upstream `CacheBook.close`.
    public func close() {
        tasks.removeAll()
        succeeded.removeAll()
        failureCounts.removeAll()
        failures.removeAll()
    }

    /// Upstream `CacheBook.isRun`.
    public var isRunning: Bool {
        tasks.values.contains { !$0.order.isEmpty || !$0.downloading.isEmpty }
    }

    /// Upstream `CacheBook.downloadSummary` inputs.
    public func progress(bookUrl: String? = nil) -> CacheBookProgress {
        var result = CacheBookProgress(failed: failureCounts.count, succeeded: succeeded.count)
        for (key, task) in tasks {
            if let bookUrl, key != bookUrl { continue }
            result.waiting += task.order.count
            result.downloading += task.downloading.count
        }
        return result
    }

    // MARK: - Running

    /// Drains the queue and returns when nothing is left. Concurrent workers
    /// up to `configuration.threadCount`.
    public func run() async {
        let workers = max(1, configuration.threadCount)
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<workers {
                group.addTask { await self.worker() }
            }
            await group.waitForAll()
        }
    }

    /// Downloads one specific chapter immediately, bypassing the queue — the
    /// reader's "open this chapter now" path (`CacheBookModel.downloadAwait`).
    @discardableResult
    public func downloadNow(book: Book, source: BookSource, chapter: BookChapter) async -> String? {
        var task = tasks[book.bookUrl] ?? BookTask(
            book: book,
            source: source,
            order: [],
            queued: [],
            downloading: [],
            stopped: false
        )
        task.queued.remove(Int(chapter.index))
        task.order.removeAll { $0 == chapter.index }
        task.downloading.insert(Int(chapter.index))
        tasks[book.bookUrl] = task

        defer {
            if var current = tasks[book.bookUrl] {
                current.downloading.remove(Int(chapter.index))
                tasks[book.bookUrl] = current
                finishIfIdle(bookUrl: book.bookUrl)
            }
        }

        do {
            let text = try await fetchAndStore(book: book, source: source, chapter: chapter)
            recordSuccess(chapter: chapter)
            return text
        } catch {
            recordFailure(chapter: chapter, error: error)
            return nil
        }
    }

    private func worker() async {
        while let (bookUrl, chapter) = takeNext() {
            await process(bookUrl: bookUrl, chapter: chapter)
        }
    }

    /// Takes the first queued chapter of the first book that has work.
    private func takeNext() -> (String, BookChapter)? {
        for (bookUrl, task) in tasks {
            guard !task.stopped, let index = task.order.first else { continue }
            var current = task
            current.order.removeFirst()
            current.queued.remove(index)
            guard let chapter = (try? chapterLoader(bookUrl, index)) ?? nil else {
                // The row disappeared — drop it and look again.
                if current.order.isEmpty && current.downloading.isEmpty {
                    tasks.removeValue(forKey: bookUrl)
                } else {
                    tasks[bookUrl] = current
                }
                continue
            }
            current.downloading.insert(index)
            tasks[bookUrl] = current
            return (bookUrl, chapter)
        }
        return nil
    }

    private func process(bookUrl: String, chapter: BookChapter) async {
        guard let task = tasks[bookUrl] else { return }
        let book = task.book
        let source = task.source
        defer {
            if var current = tasks[bookUrl] {
                current.downloading.remove(Int(chapter.index))
                tasks[bookUrl] = current
                finishIfIdle(bookUrl: bookUrl)
            }
        }

        // A volume chapter has no content — upstream posts SAVE_CONTENT to
        // fix the download counters and moves on.
        if chapter.isVolume {
            recordSuccess(chapter: chapter)
            return
        }
        // Fully cached (text + every image).
        if storage.hasImageContent(book: book, chapter: chapter) {
            recordSuccess(chapter: chapter)
            return
        }
        // Text is cached but images are missing: only fetch the images.
        if storage.hasContent(book: book, chapter: chapter) {
            if configuration.cacheImages,
               let text = storage.content(book: book, chapter: chapter) {
                await saveImages(book: book, source: source, chapter: chapter, content: text)
            }
            recordSuccess(chapter: chapter)
            return
        }

        var attempt = 0
        while true {
            do {
                let text = try await fetchAndStore(book: book, source: source, chapter: chapter)
                if configuration.cacheImages {
                    await saveImages(book: book, source: source, chapter: chapter, content: text)
                }
                recordSuccess(chapter: chapter)
                return
            } catch {
                let key = chapter.bookUrl + chapter.url
                let count = (failureCounts[key] ?? 0) + 1
                failureCounts[key] = count
                failures[key] = "\(error)"
                attempt += 1
                // Upstream re-queues while the failure count is below three.
                guard count < configuration.maxRetries,
                      attempt < configuration.maxRetries,
                      !(tasks[bookUrl]?.stopped ?? true) else {
                    return
                }
                if configuration.retryDelay > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(configuration.retryDelay * 1_000_000_000))
                }
                guard !(tasks[bookUrl]?.stopped ?? true) else { return }
            }
        }
    }

    private func fetchAndStore(
        book: Book,
        source: BookSource,
        chapter: BookChapter
    ) async throws -> String {
        let text = try await contentFetcher(source, book, chapter)
        try storage.saveText(book: book, chapter: chapter, content: text)
        return text
    }

    private func saveImages(
        book: Book,
        source: BookSource,
        chapter: BookChapter,
        content: String
    ) async {
        guard let imageFetcher else { return }
        let sources = BookCacheStorage.imageSources(in: content, chapterURL: chapter.url)
        for src in sources {
            if storage.hasImage(book: book, src: src) { continue }
            guard let data = try? await imageFetcher(source, src) else { continue }
            try? storage.saveImage(book: book, src: src, data: data)
        }
    }

    private func recordSuccess(chapter: BookChapter) {
        let key = chapter.bookUrl + chapter.url
        succeeded.insert(key)
        failureCounts.removeValue(forKey: key)
        failures.removeValue(forKey: key)
    }

    private func recordFailure(chapter: BookChapter, error: Error) {
        let key = chapter.bookUrl + chapter.url
        failureCounts[key] = (failureCounts[key] ?? 0) + 1
        failures[key] = "\(error)"
    }

    /// Upstream `onFinally`: a book with nothing queued and nothing in flight
    /// leaves the map.
    private func finishIfIdle(bookUrl: String) {
        guard let task = tasks[bookUrl] else { return }
        if task.order.isEmpty && task.downloading.isEmpty {
            tasks.removeValue(forKey: bookUrl)
        }
    }
}
