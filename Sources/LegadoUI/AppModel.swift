//
//  AppModel.swift
//  LegadoUI
//
//  The observable state of the application shell.
//
//  Upstream keeps this state in the Android view models
//  (`ui/main/bookshelf/BookShelfViewModel`,
//  `ui/book/info/BookInfoViewModel`, `ui/book/read/ReadBookActivity`).
//  The port folds them into one observable object so the SwiftUI views stay
//  thin and the whole shell can be driven from a test.
//
//  The file is compiled on every platform: the real SwiftUI on Apple, the
//  shim everywhere else (see `Sources/LegadoUIShim/View.swift`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore
import LegadoServer

#if canImport(UIKit)
import UIKit
#endif

/// The errors of the local web service.
public enum WebServiceError: Error, Equatable, LocalizedError {
    /// The file of a local book is missing — upstream `NoBooksDirException`.
    case localBookMissing

    public var errorDescription: String? {
        switch self {
        case .localBookMissing:
            return "找不到本地书籍文件"
        }
    }
}

/// A holder of a task, so that the cancel action of a notification (upstream
/// `IntentAction.stop`) can reach the running work.
public final class TaskHolder: @unchecked Sendable {

    /// The task.
    public var task: Task<Void, Never>?

    public init() {}

    /// Cancels the task.
    public func cancel() {
        task?.cancel()
        task = nil
    }
}

/// The counter of the books that wait for the update of their table of
/// contents — upstream `MainViewModel.postUpBooksLiveData`.
///
/// The counter is changed by the workers of the update, so it is thread safe.
final class BookUpdateCounter: @unchecked Sendable {

    private let lock = NSLock()
    private var storage: Int

    init(_ count: Int) {
        storage = count
    }

    /// The number of the books that still wait for the update.
    var remaining: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// Counts one updated book — the number of the books that wait decreases.
    @discardableResult
    func finishOne() -> Int {
        lock.lock()
        storage = max(0, storage - 1)
        let remaining = storage
        lock.unlock()
        return remaining
    }
}

/// A weak reference to the app model — the callbacks that run in a worker
/// thread publish their progress through it.
final class WeakAppModelBox: @unchecked Sendable {

    weak var model: LegadoAppModel?

    init(_ model: LegadoAppModel) {
        self.model = model
    }
}

/// The state of the application shell.
public final class LegadoAppModel: ObservableObject {

    /// The services.
    public let environment: AppEnvironment

    /// The local book importer — upstream `LocalBook.importFile`.
    public let localImporter: LocalBookImporter?

    /// The imported local books.
    @Published public var localBooks: [Book] = []

    /// The replace rules — upstream `ReplaceRuleDao.all`.
    @Published public var replaceRules: [ReplaceRule] = []

    /// The bookmarks — upstream `BookmarkDao.all`.
    @Published public var bookmarks: [Bookmark] = []

    /// The theme manager (upstream `ThemeConfig`).
    public let themeManager: ThemeManager

    /// Whether the system is in dark mode; the shell keeps it up to date.
    @Published public var isSystemDark = false {
        didSet {
            // The settings need it to know whether the night mode is used
            // (the welcome screen, the reader, the theme).
            environment.settings.isSystemDark = isSystemDark
        }
    }

    /// The visible book groups (upstream `BookGroupDao.show`).
    @Published public var groups: [BookGroup] = []
    /// The group the bookshelf shows.
    @Published public var selectedGroupId: Int64 = BookGroup.Id.all
    /// The books of the selected group.
    @Published public var books: [Book] = []
    /// The filter of the bookshelf (upstream `BookDao.flowSearch`).
    @Published public var bookFilter: String = ""
    /// The book sources.
    @Published public var sources: [BookSource] = []
    /// The RSS sources.
    @Published public var rssSources: [RssSource] = []
    /// The favourite articles — upstream `rssStars`.
    @Published public var rssStars: [RssStar] = []
    /// The read records — upstream `rssReadRecords`.
    @Published public var rssReadRecords: [RssReadRecord] = []
    /// Whether a long running action is in flight.
    @Published public var isLoading = false
    /// The last error, shown as an alert.
    @Published public var errorMessage: String?
    /// The last status message of a background action (the backup, the
    /// restore) — shown as an alert too.
    @Published public var backupMessage: String?
    /// The reader of the book that is being read (upstream `ReadBookActivity`).
    @Published public var reader: ReaderController?
    /// Whether the reader is presented.
    @Published public var isReaderPresented = false
    /// The book that the reader asks about when it is closed and the book is
    /// not on the shelf — upstream `ReadBookActivity.finish()`.
    @Published public var pendingShelfBook: Book?
    /// The manga reader (upstream `ReadMangaActivity`).
    @Published public var mangaReader: MangaReaderController?
    /// Whether the manga reader is presented.
    @Published public var isMangaPresented = false
    /// The source whose login dialog is presented (upstream `SourceLoginActivity`).
    ///
    /// The upstream opens the same dialog for the book sources and for the
    /// RSS sources (`SourceLoginActivity` with the type "rssSource"), so the
    /// port stores the protocol.
    @Published public var loginSource: LoginCapable?
    /// Whether the login dialog is presented.
    @Published public var isLoginPresented = false

    /// The tab of the shell that is shown — upstream `MainActivity.upHomePage()`
    /// and the `defaultHomePage` preference.
    @Published public var selectedTab: HomePage = .bookshelf {
        didSet { visitedTabs.insert(selectedTab) }
    }

    /// The tabs that were opened — the upstream keeps the fragments of the
    /// `BottomNavigationView` alive, so the port keeps their views too.
    @Published public var visitedTabs: Set<HomePage> = [.bookshelf]

    /// The cache queue of the books (upstream `CacheBook`).
    @Published public var cacheProgress: [String: CacheBookProgress] = [:]

    /// Starts caching a book (upstream `CacheBook.start`).
    public func startCaching(book: Book) async {
        guard let manager = cacheManager else { return }
        guard let source = try? environment.source(for: book) else { return }
        do {
            try await manager.start(book: book, source: source, start: 0, end: Int.max)
            await refreshCacheProgress(bookUrl: book.bookUrl)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Starts caching a range of chapters — upstream
    /// `CacheBook.start(activity, book, start, end)` (the chapters are
    /// 0-based; the upstream passes `Int.MAX_VALUE` for "the rest of the
    /// book").
    public func startCaching(book: Book, start: Int, end: Int) async {
        guard let manager = cacheManager else { return }
        guard let source = try? environment.source(for: book) else { return }
        do {
            try await manager.start(book: book, source: source, start: start, end: end)
            await refreshCacheProgress(bookUrl: book.bookUrl)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The export formats of the upstream `ExportBookService`.
    public enum BookExportFormat: String, CaseIterable, Identifiable, Sendable {
        case txt
        case epub

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .txt: return "TXT"
            case .epub: return "EPUB"
            }
        }
    }

    /// Exports a book — upstream `ExportBookService` (the TXT / EPUB export of
    /// the cache screen).
    ///
    /// The cached chapters are used when they exist, otherwise the content is
    /// fetched through the source.
    @discardableResult
    public func exportBook(
        book: Book,
        format: BookExportFormat,
        options: BookExportOptions = BookExportOptions()
    ) async throws -> ExportedFile {
        let chapters = try environment.chapters(of: book)
        let titleRules = (try? environment.store.replaceRulesForTitle(name: book.name, origin: book.origin)) ?? []
        let contentRules = (try? environment.store.replaceRulesForContent(name: book.name, origin: book.origin)) ?? []
        let dependencies = AnalyzeUrlDependencies(
            httpClient: environment.httpClient,
            cookieStore: environment.cookieStore,
            scriptEngine: environment.scriptEngine
        )
        let cache = environment.cacheStorage
        let source = try environment.source(for: book)
        let content: (BookChapter) async throws -> String? = { chapter in
            if let cached = cache?.content(book: book, chapter: chapter) {
                return cached
            }
            guard let source else { return nil }
            return try await WebBook.getContent(
                bookSource: source,
                book: book,
                bookChapter: chapter,
                dependencies: dependencies
            )
        }
        switch format {
        case .txt:
            let result = try await BookExporter.exportTxt(
                book: book,
                chapters: chapters,
                titleRules: titleRules,
                contentRules: contentRules,
                options: options,
                content: content
            )
            return result.file
        case .epub:
            return try await BookExporter.exportEpub(
                book: book,
                chapters: chapters,
                titleRules: titleRules,
                contentRules: contentRules,
                options: options,
                content: content
            )
        }
    }

    /// Exports a book and **writes it to disk** — upstream
    /// `ExportBookService.exportTxt` / `exportEpub`.
    ///
    /// The upstream writes the file into the folder the user picked and
    /// uploads it to the WebDAV `books/` folder when `AppConfig.exportToWebDav`
    /// is on; the port writes into the documents directory (visible in the
    /// Files app) and uploads the same way.
    @discardableResult
    public func exportBookToFile(
        book: Book,
        format: BookExportFormat,
        options: BookExportOptions = BookExportOptions(),
        directory: URL? = nil
    ) async throws -> WrittenExport {
        let settings = environment.settings
        let suffix = format == .txt ? "txt" : "epub"
        let template = settings.bookExportFileName
        let fileName = ExportFileName.name(
            book: book,
            suffix: suffix,
            template: template,
            engine: environment.scriptEngine
        )
        var options = options
        if options.fileName == nil || options.fileName?.isEmpty == true {
            options.fileName = fileName
        }

        // Upstream `ExportBookService.upExportNotification` — a resident
        // notification with the progress of the export.
        postExportNotification(message: "正在导出 \(book.name)")
        defer { postExportNotification(message: "导出完成") }

        let chapters = try environment.chapters(of: book)
        let titleRules = (try? environment.store.replaceRulesForTitle(name: book.name, origin: book.origin)) ?? []
        let contentRules = (try? environment.store.replaceRulesForContent(name: book.name, origin: book.origin)) ?? []
        let dependencies = AnalyzeUrlDependencies(
            httpClient: environment.httpClient,
            cookieStore: environment.cookieStore,
            scriptEngine: environment.scriptEngine
        )
        let cache = environment.cacheStorage
        let source = try environment.source(for: book)
        let content: (BookChapter) async throws -> String? = { chapter in
            if let cached = cache?.content(book: book, chapter: chapter) {
                return cached
            }
            guard let source else { return nil }
            return try await WebBook.getContent(
                bookSource: source,
                book: book,
                bookChapter: chapter,
                dependencies: dependencies
            )
        }

        // The images of the book — upstream `BookHelp.getImage`.
        let imageProvider: (String) -> Data? = { source in
            guard let cache else { return nil }
            if let data = cache.image(book: book, src: source) { return data }
            return nil
        }
        // The cover of the book — upstream `Book.getCoverUrl` / the cover cache.
        let coverProvider: (Book) -> Data? = { target in
            guard let cache else { return nil }
            return cache.image(book: target, src: target.coverUrl ?? "")
        }

        var written: WrittenExport
        let target = directory ?? exportDirectory()
        switch format {
        case .txt:
            let result = try await BookExporter.exportTxt(
                book: book,
                chapters: chapters,
                titleRules: titleRules,
                contentRules: contentRules,
                options: options,
                imageProvider: imageProvider,
                content: content
            )
            written = try BookExportFileWriter.write(
                file: result.file,
                images: result.images,
                to: target,
                charset: ExportCharset(rawValue: settings.exportCharset) ?? .utf8
            )
        case .epub:
            let file = try await BookExporter.exportEpub(
                book: book,
                chapters: chapters,
                titleRules: titleRules,
                contentRules: contentRules,
                options: options,
                imageProvider: imageProvider,
                coverProvider: coverProvider,
                content: content
            )
            written = try BookExportFileWriter.write(
                file: file,
                to: target
            )
        }

        // Upstream `AppWebDav.exportWebDav(bookDoc.uri, filename)`.
        if settings.exportToWebDav, let service = webDavService() {
            try? await service.uploadBook(
                data: try Data(contentsOf: written.url),
                fileName: written.fileName
            )
        }
        return written
    }

    /// Posts the progress of the export — upstream
    /// `ExportBookService.upExportNotification`.
    ///
    /// The notification is resident (it carries the fixed identifier
    /// `NotificationId.ExportBook`), so it replaces the previous one.
    public func postExportNotification(message: String, progress: Double? = nil) {
        NotificationService.shared.post(.exportBook(message: message, progress: progress))
    }

    /// Posts the progress of the source check — upstream
    /// `CheckSourceService.upNotification`.
    public func postCheckNotification(message: String, finished: Int, total: Int) {
        NotificationService.shared.post(
            .checkSource(message: message, finished: finished, total: total)
        )
    }

    /// The task of the source check — the 取消 action of the check
    /// notification cancels it (upstream `CheckSourceService.stop`).
    public let sourceCheckTask = TaskHolder()

    /// The task of the export — the 取消 action of the export notification
    /// cancels it (upstream `ExportBookService.stop`).
    public let exportTask = TaskHolder()
    /// The folder the exports are written into — upstream
    /// `CacheActivity.selectExportFolder` stores the folder under the
    /// `exportBookPath` key.
    public func exportDirectory() -> URL {
        let path = (try? environment.store.cache(
            "exportBookPath",
            now: Int64(Date().timeIntervalSince1970 * 1000)
        )) ?? ""
        return BookExportFileWriter.exportDirectory(configuredPath: path)
    }

    /// Stores the folder the exports are written into — upstream
    /// `ACache.get().put(exportBookPathKey, path)`.
    public func setExportDirectory(_ url: URL) {
        try? environment.store.putCache(
            "exportBookPath",
            value: url.path,
            deadline: 0
        )
    }

    /// Exports a book as several EPUB files — upstream
    /// `ExportBookService.CustomExporter.export`.
    ///
    /// The chapters of `scope` are split into groups of `splitSize`
    /// chapters; every group is written as its own EPUB file.
    @discardableResult
    public func exportBookParts(
        book: Book,
        options: BookExportOptions = BookExportOptions(),
        scope: Set<Int>,
        splitSize: Int = 1,
        directory: URL? = nil
    ) async throws -> [WrittenExport] {
        let settings = environment.settings
        let chapters = try environment.chapters(of: book)
        // Upstream `ExportBookService.upExportNotification`.
        postExportNotification(message: "正在导出 \(book.name)")
        defer { postExportNotification(message: "导出完成") }
        let titleRules = (try? environment.store.replaceRulesForTitle(name: book.name, origin: book.origin)) ?? []
        let contentRules = (try? environment.store.replaceRulesForContent(name: book.name, origin: book.origin)) ?? []
        let dependencies = AnalyzeUrlDependencies(
            httpClient: environment.httpClient,
            cookieStore: environment.cookieStore,
            scriptEngine: environment.scriptEngine
        )
        let cache = environment.cacheStorage
        let source = try environment.source(for: book)
        let content: (BookChapter) async throws -> String? = { chapter in
            if let cached = cache?.content(book: book, chapter: chapter) {
                return cached
            }
            guard let source else { return nil }
            return try await WebBook.getContent(
                bookSource: source,
                book: book,
                bookChapter: chapter,
                dependencies: dependencies
            )
        }
        let imageProvider: (String) -> Data? = { source in
            guard let cache else { return nil }
            return cache.image(book: book, src: source)
        }
        let coverProvider: (Book) -> Data? = { target in
            guard let cache else { return nil }
            return cache.image(book: target, src: target.coverUrl ?? "")
        }

        var partOptions = options
        partOptions.chapterIndexes = scope
        let files = try await BookExporter.exportEpubParts(
            book: book,
            chapters: chapters,
            titleRules: titleRules,
            contentRules: contentRules,
            options: partOptions,
            splitSize: splitSize,
            nameTemplate: settings.string(.episodeExportFileName),
            engine: environment.scriptEngine,
            imageProvider: imageProvider,
            coverProvider: coverProvider,
            content: content
        )
        let target = directory ?? exportDirectory()
        var written: [WrittenExport] = []
        for file in files {
            let result = try BookExportFileWriter.write(file: file, to: target)
            if settings.exportToWebDav, let service = webDavService() {
                try? await service.uploadBook(
                    data: try Data(contentsOf: result.url),
                    fileName: result.fileName
                )
            }
            written.append(result)
        }
        return written
    }

    /// The WebDAV client built from the settings — upstream `AppWebDav.upConfig`.
    public func webDavService() -> WebDavService? {
        let account = environment.settings.appWebDav
        guard account.isConfigured else { return nil }
        return WebDavService(
            configuration: account.serviceConfiguration,
            httpClient: environment.httpClient
        )
    }

    /// Stops caching a book.
    public func stopCaching(book: Book) async {
        await cacheManager?.stop(bookUrl: book.bookUrl)
        await refreshCacheProgress(bookUrl: book.bookUrl)
    }

    /// Reads the progress of a cached book.
    public func refreshCacheProgress(bookUrl: String) async {
        guard let manager = cacheManager else { return }
        let progress = await manager.progress(bookUrl: bookUrl)
        cacheProgress[bookUrl] = progress
    }

    /// Presents the login dialog of a source.
    public func presentLogin(for source: LoginCapable) {
        loginSource = source
        isLoginPresented = true
    }

    /// Presents the login dialog of a HTTP TTS engine — upstream
    /// `HttpTtsEditDialog.menu_login` (the type `httpTts`).
    public func presentHttpTTSLogin(_ engine: HttpTTS) {
        presentLogin(for: engine)
    }

    /// Dismisses the login dialog.
    public func dismissPresentedSheet() {
        isLoginPresented = false
        loginSource = nil
    }

    public init(
        environment: AppEnvironment,
        themeManager: ThemeManager = ThemeManager(),
        localImporter: LocalBookImporter? = nil,
        cacheManager: CacheBookManager? = nil,
        verification: SourceVerificationCoordinator? = nil,
        openURL: OpenURLCoordinator? = nil,
        downloadService: DownloadService? = nil
    ) {
        self.environment = environment
        self.themeManager = themeManager
        self.localImporter = localImporter
        self.cacheManager = cacheManager
        self.verification = verification
        self.openURL = openURL
        self.downloadService = downloadService
    }

    /// The cache queue (upstream `CacheBook`).
    public let cacheManager: CacheBookManager?

    /// The generic file downloader — upstream `service/DownloadService.kt`.
    ///
    /// The upstream is an Android service that owns the `DownloadManager`; the
    /// port is a queue that writes the files into the documents directory of
    /// the app and posts the notifications of the upstream.
    public let downloadService: DownloadService?

    /// The downloads of the queue — the list of the download management.
    @Published public var downloads: [DownloadInfo] = []

    /// Starts a file download — upstream `DownloadService.startDownload`.
    ///
    /// The upstream posts a notification that carries the 取消 action; the
    /// port does the same (the identifier of the notification is
    /// `NotificationId.Download + n`).
    ///
    /// - Returns: the identifier of the download, or `nil` when the address is
    ///   already in the list (the upstream toast "已在下载列表").
    @discardableResult
    public func startDownload(
        url: String,
        fileName: String? = nil,
        headers: [String: String] = [:]
    ) -> Int? {
        guard let service = downloadService else { return nil }
        let request = DownloadRequest(
            url: url,
            fileName: fileName ?? DownloadRequest.fileName(for: url),
            headers: headers
        )
        guard let identifier = service.start(request) else {
            // The upstream toast "已在下载列表".
            errorMessage = "已在下载列表"
            return nil
        }
        // The 取消 action of the notification of the download stops it
        // (upstream `DownloadService` + `IntentAction.stop`).
        let notificationId = NotificationId.download + identifier
        NotificationService.shared.notificationActionHandlers[notificationId] = { [weak service] _ in
            service?.cancel(id: identifier)
        }
        return identifier
    }

    /// The coordinator of the source verification (upstream
    /// `SourceVerificationHelp`). The rule scripts ask it for the captcha
    /// answer; the app shows the dialog and hands the answer back.
    public let verification: SourceVerificationCoordinator?

    /// The coordinator of the external links (upstream
    /// `OpenUrlConfirmActivity`). A rule script that calls `java.openUrl`
    /// waits for the user to confirm the jump.
    public let openURL: OpenURLCoordinator?

    /// The jump a rule script asked for — upstream the confirmation dialog of
    /// `OpenUrlConfirmDialog`.
    @Published public var pendingOpenURL: OpenURLRequest?

    /// The user accepted the jump — the link is opened.
    public func confirmOpenURL() {
        pendingOpenURL = nil
        openURL?.complete(true)
    }

    /// The user refused the jump (or closed the dialog).
    public func cancelOpenURL() {
        pendingOpenURL = nil
        openURL?.complete(false)
    }

    /// The verification the user has to solve — the captcha dialog or the
    /// anti-scraping page.
    @Published public var pendingVerification: SourceVerificationRequest?

    /// Hands the answer of the user back to the rule that asked for it.
    public func completeVerification(answer: String) {
        pendingVerification = nil
        verification?.complete(answer)
    }

    /// Aborts the verification — the rule gets the "验证结果为空" error.
    public func cancelVerification() {
        pendingVerification = nil
        verification?.cancel()
    }

    /// Whether the local password is being asked for (upstream
    /// `MainActivity.setLocalPassword`).
    @Published public var isLocalPasswordPresented = false

    /// Asks for the local password when the user has never set one.
    ///
    /// The upstream asks on every start until the user has chosen a password;
    /// declining stores an empty password, which stops the prompt.
    public func presentLocalPasswordIfNeeded() {
        guard environment.localConfig.password == nil else { return }
        isLocalPasswordPresented = true
    }

    /// Builds the default environment.
    ///
    /// On Apple platforms the database is a SQLite file in the documents
    /// directory (upstream `AppDatabase`); elsewhere the in-memory store is
    /// used, because there is no SQLite module in the Linux toolchain.
    public static func makeDefault() -> LegadoAppModel {
        #if canImport(SQLite3)
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("legado.db")
        let tables: TableStore
        if let url, let store = try? SQLiteTableStore(path: url.path) {
            tables = store
        } else {
            tables = MemoryTableStore()
        }
        #else
        let tables: TableStore = MemoryTableStore()
        #endif
        let store = LegadoStore(tables: tables)
        try? store.createSchema()
        // Upstream `DefaultData` fills the empty tables with the defaults
        // that ship with the app (the TXT table of contents rules, the
        // keyboard assists).
        try? DefaultData.importDefaults(store: store)
        let settings = AppSettings(store: UserDefaultsSettingsStore())
        let themeURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent(ThemeManager.configFileName)
        let mode = ThemeMode(rawValue: Int(settings.themeMode) ?? 0) ?? .followSystem
        let themeManager = ThemeManager(mode: mode, fileURL: themeURL)
        // The chapter cache (upstream `BookHelp.downloadDir`).
        let cacheRoot = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("book_cache", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("book_cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let cacheStorage = BookCacheStorage(layout: BookCacheLayout(root: cacheRoot))
        // The imported local books — upstream `AppConfig.defaultBookTreeUri`.
        // The preference holds the folder the user picked; the port falls
        // back to the documents directory when it is empty.
        let booksRoot = LegadoAppModel.booksRoot(for: settings)
        try? FileManager.default.createDirectory(at: booksRoot, withIntermediateDirectories: true)
        // The cookie jar of the app (upstream `CookieStore` keeps the cookies
        // in the shared preferences) and the login service of the sources.
        let cookieStore = CookieStore(persistence: UserDefaultsCookiePersistence())
        let loginService = SourceLoginService(store: store, cookieStore: cookieStore)
        // The JavaScript runtime of the rule scripts (upstream runs them in
        // Rhino). The file calls of a script are confined to the cache
        // directory, exactly like the upstream does.
        let httpClient = URLSessionHttpClient()
        // The verification of a source (upstream `SourceVerificationHelp`):
        // the rule scripts park until the user has solved the captcha.
        let verification = SourceVerificationCoordinator()
        // The confirmation of an external link (upstream
        // `OpenUrlConfirmActivity`): a rule script that calls `java.openUrl`
        // waits for the user.
        let openURL = OpenURLCoordinator()
        let scriptEngine = ScriptEngineFactory.make(
            login: loginService,
            cookieStore: cookieStore,
            httpClient: httpClient,
            userAgent: settings.userAgent,
            sandboxDirectory: cacheRoot.path,
            verification: verification,
            openURL: openURL
        )
        // The importer runs the JavaScript rule of the file names, so it needs
        // the script engine.
        let localImporter = LocalBookImporter(store: store, booksDirectory: booksRoot)
        localImporter.scriptEngine = scriptEngine
        let environment = AppEnvironment(
            store: store,
            settings: settings,
            localConfig: LocalConfig(store: UserDefaultsSettingsStore.localSuite()),
            scriptEngine: scriptEngine,
            httpClient: httpClient,
            cookieStore: cookieStore,
            cacheStorage: cacheStorage,
            loginService: loginService,
            // Upstream `LocalBook.getBookFile` — the file of a local book.
            localFileResolver: { book in localImporter.fileURL(for: book) }
        )
        // The download progress is posted as a notification — upstream
        // `CacheBookService.sendNotification`.
        let cacheManager = environment.makeCacheManager(
            storage: cacheStorage,
            notificationSink: NotificationService.shared
        )
        // The generic file downloader (upstream `service/DownloadService.kt`).
        // iOS has no public Download folder an app may write to, so the files
        // are written into the documents directory of the app.
        let downloadsRoot = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("downloads", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: downloadsRoot, withIntermediateDirectories: true)
        let downloadService = DownloadService(
            downloader: URLSessionFileDownloader(),
            destinationDirectory: downloadsRoot
        )
        let model = LegadoAppModel(
            environment: environment,
            themeManager: themeManager,
            localImporter: localImporter,
            cacheManager: cacheManager,
            verification: verification,
            openURL: openURL,
            downloadService: downloadService
        )
        // Every change of the queue posts the notification of the upstream
        // (`DownloadService.startDownload` → the notification with the 取消
        // action) and refreshes the list of the download management.
        downloadService.setChangeHandler { info in
            NotificationService.shared.post(
                .downloadFile(
                    fileName: info.request.fileName,
                    state: info.status.stateText,
                    identifier: NotificationId.download + info.id,
                    progress: info.status.progress
                )
            )
            DispatchQueue.main.async {
                model.downloads = downloadService.items
            }
        }
        // The 取消 action of the resident download notification stops the
        // offline cache — upstream `CacheBookService` + `IntentAction.stop`.
        NotificationService.shared.notificationActionHandlers[NotificationId.cacheBookService] = { _ in
            Task { await cacheManager.stopAll() }
        }
        // The 取消 action of the check notification stops the check — upstream
        // `CheckSourceService` + `IntentAction.stop`.
        NotificationService.shared.notificationActionHandlers[NotificationId.checkSourceService] = { [weak model] _ in
            model?.sourceCheckTask.cancel()
        }
        // The 取消 action of the export notification stops the export — upstream
        // `ExportBookService` + `IntentAction.stop`.
        NotificationService.shared.notificationActionHandlers[NotificationId.exportBook] = { [weak model] _ in
            model?.exportTask.cancel()
        }
        // The rule scripts park on a background thread; the request has to
        // reach the UI on the main thread.
        verification.onRequest = { request in
            DispatchQueue.main.async {
                model.pendingVerification = request
            }
        }
        // The same for the confirmation of an external link.
        openURL.onRequest = { request in
            DispatchQueue.main.async {
                model.pendingOpenURL = request
            }
        }
        return model
    }

    // MARK: - The book update

    /// Updates the table of contents of one book — upstream
    /// `MainViewModel.updateToc(bookUrl)`.
    @discardableResult
    public func updateBook(_ book: Book) async -> BookUpdateResult? {
        isLoading = true
        defer { isLoading = false }
        // Upstream `MainViewModel.upToc(books)` — the book waits in the queue
        // of the update, the badge of the bookshelf tab counts it.
        upBooksCount = 1
        let result = await BookUpdater.update(
            book: book,
            source: nil,
            store: environment.store,
            dependencies: environment.dependencies()
        )
        upBooksCount = 0
        if !result.isSuccess {
            errorMessage = result.message
        }
        reloadBookshelf()
        return result
    }

    /// Updates the table of contents of all the books of the shelf — upstream
    /// `MainViewModel.upAllBookToc()`.
    public func updateAllBooks() async -> [BookUpdateResult] {
        isLoading = true
        defer { isLoading = false }
        // Upstream `MainViewModel.postUpBooksLiveData` — the badge of the
        // bookshelf tab shows the number of the books that wait for the
        // update of their table of contents.
        let candidates = books.filter { !$0.isLocal && $0.canUpdate }
        let counter = BookUpdateCounter(candidates.count)
        let box = WeakAppModelBox(self)
        upBooksCount = candidates.count
        let results = await BookUpdater.updateAll(
            books: books,
            store: environment.store,
            dependencies: environment.dependencies(),
            threadCount: environment.settings.threadCount,
            onUpdate: { [box, counter] _ in
                let remaining = counter.finishOne()
                box.model?.upBooksCount = remaining
            }
        )
        upBooksCount = counter.remaining
        reloadBookshelf()
        return results
    }

    // MARK: - Loading

    /// Reloads the groups and the books of the selected group.
    public func reloadBookshelf() {
        do {
            groups = try environment.store.visibleGroups()
            books = try environment.books(inGroup: selectedGroupId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The keys of the books on the shelf — upstream
    /// `ui/book/search/SearchViewModel.bookshelf`: the "name-author", the name
    /// and the address of every book that is on the shelf.
    public func shelfBookKeys() -> Set<String> {
        let all = (try? environment.store.allBooks()) ?? []
        var keys = Set<String>()
        for book in all {
            keys.insert("\(book.name)-\(book.author)")
            keys.insert(book.name)
            keys.insert(book.bookUrl)
        }
        return keys
    }

    /// Whether the book is on the shelf — upstream
    /// `ui/book/search/SearchViewModel.isInBookShelf`.
    public func isOnShelf(_ book: SearchBook) -> Bool {
        let key = book.author.isEmpty ? book.name : "\(book.name)-\(book.author)"
        let keys = shelfBookKeys()
        return keys.contains(key) || keys.contains(book.bookUrl)
    }

    /// Reloads the book sources.
    public func reloadSources() {
        do {
            sources = try environment.sources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reloads the RSS sources, the favourites and the read records.
    public func reloadRSS() {
        do {
            rssSources = try environment.rssSources()
            rssStars = try environment.store.allRssStars()
            rssReadRecords = try environment.store.allRssReadRecords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reloads the imported local books.
    public func reloadLocalBooks() {
        guard let localImporter else { return }
        do {
            localBooks = try localImporter.localBooks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Imports a local book file — upstream `LocalBook.importFile`.
    public func importLocalBook(from url: URL) {
        guard let localImporter else {
            errorMessage = "本地书导入不可用"
            return
        }
        localImporter.fileNameRule = environment.settings.bookImportFileName
        do {
            _ = try localImporter.importBook(from: url)
            reloadLocalBooks()
            reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Imports several local books — upstream `LocalBook.importFiles`.
    ///
    /// The archives are unpacked and every book inside them is imported.
    ///
    /// - Returns: the number of the imported books.
    @discardableResult
    public func importLocalBooks(_ urls: [URL]) async -> Int {
        guard let localImporter else {
            errorMessage = "本地书导入不可用"
            return 0
        }
        localImporter.fileNameRule = environment.settings.bookImportFileName
        let count = (try? localImporter.importBooks(from: urls)) ?? 0
        reloadLocalBooks()
        reloadBookshelf()
        return count
    }

    /// Deletes an imported local book.
    public func deleteLocalBook(_ book: Book) {
        guard let localImporter else { return }
        do {
            try localImporter.removeBook(book)
            reloadLocalBooks()
            reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a book of the shelf — upstream
    /// `BookInfoViewModel.delBook` / `BookshelfManageViewModel.deleteBook`.
    ///
    /// The cache of the book is cleared and, for a local book, its file is
    /// deleted when `deleteOriginal` is set (upstream
    /// `LocalBook.deleteBook`).
    public func deleteBook(_ book: Book, deleteOriginal: Bool = false) {
        do {
            try environment.deleteBook(book, deleteOriginal: deleteOriginal)
        } catch {
            errorMessage = error.localizedDescription
        }
        reloadBookshelf()
        reloadLocalBooks()
    }

    /// The folder the imported books are copied into — upstream
    /// `AppConfig.defaultBookTreeUri`.
    public func localBookDirectory() -> URL {
        LegadoAppModel.booksRoot(for: environment.settings)
    }

    /// Stores the folder the imported books are copied into — upstream
    /// `BaseImportBookActivity.localBookTreeSelect`.
    public func setLocalBookDirectory(_ url: URL) {
        environment.settings.defaultBookTreeUri = url.path
        localImporter?.booksDirectory = url
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// The books directory of the settings — the folder the user picked, the
    /// documents directory when the preference is empty.
    static func booksRoot(for settings: AppSettings) -> URL {
        let configured = settings.defaultBookTreeUri
        if !configured.isEmpty {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: configured, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return URL(fileURLWithPath: configured, isDirectory: true)
            }
        }
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("books", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("books", isDirectory: true)
    }

    /// Imports the books of the WebDAV server — upstream
    /// `RemoteBookViewModel.addToBookshelf`.
    ///
    /// The book is downloaded, imported as a local book and its origin gets the
    /// WebDAV path, so that the book can be uploaded again later.
    public func importRemoteBooks(_ books: [RemoteBook], importer: RemoteBookImporter) async -> Int {
        guard let localImporter else {
            errorMessage = "本地书导入不可用"
            return 0
        }
        var imported = 0
        for remote in books {
            do {
                let data = try await importer.download(remote)
                let temporary = FileManager.default.temporaryDirectory
                    .appendingPathComponent(remote.filename)
                try data.write(to: temporary)
                defer { try? FileManager.default.removeItem(at: temporary) }
                var book = try localImporter.importBook(from: temporary)
                book.origin = importer.origin(for: remote)
                try environment.store.update(book)
                imported += 1
            } catch {
                errorMessage = "导入失败：\(error.localizedDescription)"
            }
        }
        reloadLocalBooks()
        reloadBookshelf()
        return imported
    }

    /// Marks the remote books that are already in the library — upstream
    /// `LocalBook.isOnBookShelf(webDavFile.displayName)`.
    ///
    /// The upstream uses the flag to decide whether a tap opens the book or
    /// selects it.
    public func markRemoteBooksOnShelf(_ books: [RemoteBook]) -> [RemoteBook] {
        let names = Set(((try? environment.store.allBooks()) ?? []).map { $0.originName })
        return books.map { book in
            var copy = book
            copy.isOnBookShelf = !book.isDir && names.contains(book.filename)
            return copy
        }
    }

    /// What tapping a remote book does — upstream
    /// `RemoteBookActivity.startRead`.
    ///
    /// - Returns: the action the browser has to carry out.
    public func remoteBookAction(for remote: RemoteBook) -> RemoteBookAction {        let onShelf = try? environment.store.book(originName: remote.filename)
        var archiveExists = false
        if RemoteBookActions.isArchive(remote), let importer = localImporter {
            let candidate = importer.booksDirectory
                .appendingPathComponent(RemoteBookActions.localFileName(remote))
            archiveExists = FileManager.default.fileExists(atPath: candidate.path)
        }
        return RemoteBookActions.startRead(
            remote: remote,
            bookOnShelf: onShelf,
            archiveExists: archiveExists
        )
    }

    /// Downloads a remote archive and imports the books inside it — the
    /// upstream's "压缩包没有找到" alert downloads the book and starts it
    /// again.
    ///
    /// - Returns: the number of the imported books.
    @discardableResult
    public func downloadRemoteArchive(
        _ remote: RemoteBook,
        importer: RemoteBookImporter
    ) async -> Int {
        guard let localImporter else {
            errorMessage = "本地书导入不可用"
            return 0
        }
        do {
            let data = try await importer.download(remote)
            let temporary = FileManager.default.temporaryDirectory
                .appendingPathComponent(remote.filename)
            try data.write(to: temporary)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let books = try localImporter.importArchive(from: temporary)
            for book in books {
                var stored = book
                stored.origin = importer.origin(for: remote)
                try environment.store.update(stored)
            }
            reloadLocalBooks()
            reloadBookshelf()
            return books.count
        } catch {
            errorMessage = "下载失败：\(error.localizedDescription)"
            return 0
        }
    }

    /// Unpacks an archive that is already in the local storage — upstream
    /// `onArchiveFileClick`.
    ///
    /// - Returns: the first imported book, so that the reader can open it.
    @discardableResult
    public func openLocalArchive(named fileName: String) -> Book? {
        guard let localImporter else {
            errorMessage = "本地书导入不可用"
            return nil
        }
        let url = localImporter.booksDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "压缩包没有找到"
            return nil
        }
        do {
            let books = try localImporter.importArchive(from: url)
            reloadLocalBooks()
            reloadBookshelf()
            return books.first
        } catch {
            errorMessage = "解压失败：\(error.localizedDescription)"
            return nil
        }
    }

    /// Downloads the file of a local book that lives on the WebDAV server —
    /// upstream `LocalBook.downloadRemoteBook`.
    ///
    /// The upstream downloads the file when the local copy is missing (the
    /// book keeps the address of the remote file in its origin).
    ///
    /// - Returns: the book with the local address, or `nil` when the file
    ///   could not be downloaded.
    @discardableResult
    public func downloadRemoteLocalBook(_ book: Book) async -> Book? {
        guard let localImporter else { return nil }
        guard let path = RemoteBookOrigin.remotePath(of: book) else { return nil }
        // The local copy is still there — nothing to do.
        if let url = localImporter.fileURL(for: book),
           FileManager.default.fileExists(atPath: url.path) {
            return book
        }
        guard let client = remoteBookClient(for: book) else { return nil }
        let name = RemoteBookOrigin.remoteFileName(of: book) ?? book.originName
        guard !name.isEmpty else { return nil }
        do {
            let data = try await client.download(path)
            try FileManager.default.createDirectory(
                at: localImporter.booksDirectory,
                withIntermediateDirectories: true
            )
            let destination = localImporter.booksDirectory.appendingPathComponent(name)
            try data.write(to: destination)
            // An archive is unpacked again — upstream `downloadRemoteBook`
            // replaces the book with the book of the archive.
            if localImporter.isArchive(destination),
               let imported = try localImporter.importArchive(from: destination).first {
                var unpacked = imported
                unpacked.origin = book.origin
                unpacked.originName = book.originName.isEmpty ? name : book.originName
                try? environment.store.update(unpacked)
                reloadLocalBooks()
                reloadBookshelf()
                return unpacked
            }
            var updated = book
            updated.bookUrl = destination.absoluteString
            if updated.originName.isEmpty {
                updated.originName = name
            }
            try environment.store.update(updated)
            return updated
        } catch {
            AppLog.shared.put("自动下载webDav书籍失败", error: error)
            return nil
        }
    }

    /// The client of the server a book lives on — the server of the origin's
    /// `serverID` attribute, otherwise the server of the remote browser.
    private func remoteBookClient(for book: Book) -> WebDavClient? {
        if let serverID = RemoteBookOrigin.serverID(of: book),
           let server = webDavServers.first(where: { $0.id == serverID }),
           let credentials = ServerManager.credentials(of: server) {
            let configuration = WebDavConfiguration(
                url: credentials.url,
                username: credentials.username,
                password: credentials.password,
                backupDirectory: "",
                bookProgressDirectory: "bookProgress/",
                booksDirectory: "",
                backgroundDirectory: "background/"
            )
            return WebDavClient(configuration: configuration, httpClient: environment.httpClient)
        }
        return remoteBookImporter()?.client
    }

    // MARK: - The books of a download service

    /// The files that can be downloaded for a book — upstream
    /// `BookInfoViewModel.loadWebFile`.
    ///
    /// A source of the type "file" (only a download service) fills the
    /// `downloadUrls` of the book with the addresses of the files.
    public func webFiles(for book: Book) -> [WebFile] {
        guard let urls = book.downloadUrls, !urls.isEmpty else { return [] }
        return WebFileBook.files(book: book, urls: urls)
    }

    /// Downloads a file of a book and imports it — upstream
    /// `BookInfoViewModel.importOrDownloadWebFile`.
    ///
    /// A file the port can read is imported as a local book; an archive is
    /// unpacked and its books are imported.
    ///
    /// - Returns: the imported book (the first one of an archive).
    @discardableResult
    public func importWebFile(_ file: WebFile, book: Book) async -> Book? {
        guard let localImporter else {
            errorMessage = "本地书导入不可用"
            return nil
        }
        do {
            let response = try await environment.httpClient.send(
                HttpRequest(url: file.url, method: "GET")
            )
            guard let data = response.data, !data.isEmpty else {
                errorMessage = "下载失败：\(file.name)"
                return nil
            }
            try FileManager.default.createDirectory(
                at: localImporter.booksDirectory,
                withIntermediateDirectories: true
            )
            let destination = localImporter.booksDirectory.appendingPathComponent(file.name)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try data.write(to: destination)
            if file.isSupportDecompress {
                let books = try localImporter.importArchive(from: destination)
                reloadLocalBooks()
                reloadBookshelf()
                return books.first
            }
            let imported = try localImporter.importBook(from: destination)
            // The information of the online book wins — upstream
            // `LocalBook.mergeBook(localBook, onLineBook)`.
            let merged = LocalBookMerge.merge(local: imported, online: book)
            if merged != imported {
                try environment.store.update(merged)
            }
            reloadLocalBooks()
            reloadBookshelf()
            return merged
        } catch {
            errorMessage = "导入失败：\(error.localizedDescription)"
            AppLog.shared.put("ImportWebFileError\n\(error.localizedDescription)", error: error)
            return nil
        }
    }

    // MARK: - The WebDAV servers

    /// The synchronisation servers — upstream `ServersDialog`.
    @Published public var webDavServers: [Server] = []

    /// Reloads the synchronisation servers.
    public func reloadWebDavServers() {
        do {
            webDavServers = ServerManager.sorted(try environment.store.allServers())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves a synchronisation server — upstream `ServersViewModel.save`.
    public func saveWebDavServer(_ server: Server) {
        do {
            try environment.store.insert(server)
            reloadWebDavServers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a synchronisation server — upstream `ServersViewModel.delete`.
    public func deleteWebDavServer(_ server: Server) {
        do {
            try environment.store.deleteServer(server)
            if selectedRemoteServerId == server.id {
                setSelectedRemoteServerId(ServerManager.defaultServerId)
            }
            reloadWebDavServers()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The id of the server the remote-book browser uses — upstream
    /// `AppConfig.remoteServerId`.
    public var selectedRemoteServerId: Int64 {
        ServerManager.selectedServerId(environment.settings)
    }

    /// Picks the server the remote-book browser uses.
    public func setSelectedRemoteServerId(_ id: Int64) {
        ServerManager.selectServer(id, settings: environment.settings)
        objectWillChange.send()
    }

    /// The credentials of the remote-book browser — upstream
    /// `RemoteBookViewModel.initData`.
    public func remoteBookCredentials() -> WebDavCredentials? {
        ServerManager.bookCredentials(settings: environment.settings, servers: webDavServers)
    }

    /// The client of the remote-book browser — upstream
    /// `RemoteBookViewModel.remoteBookWebDav`.
    public func remoteBookImporter() -> RemoteBookImporter? {
        guard let credentials = remoteBookCredentials() else { return nil }
        let configuration = WebDavConfiguration(
            url: credentials.url,
            username: credentials.username,
            password: credentials.password,
            backupDirectory: "",
            bookProgressDirectory: "bookProgress/",
            booksDirectory: "books/",
            backgroundDirectory: "background/"
        )
        let client = WebDavClient(configuration: configuration, httpClient: environment.httpClient)
        let isDefault = selectedRemoteServerId == ServerManager.defaultServerId
        let serverID: Int64? = isDefault ? nil : selectedRemoteServerId
        return RemoteBookImporter(
            client: client,
            rootPath: ServerManager.booksRoot(isDefault: isDefault),
            serverID: serverID
        )
    }

    // MARK: - The replace rules

    /// Reloads the replace rules.
    public func reloadReplaceRules() {
        do {
            replaceRules = try environment.store.allReplaceRules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves a replace rule.
    public func saveReplaceRule(_ rule: ReplaceRule) {
        do {
            try environment.store.insert(rule)
            reloadReplaceRules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a replace rule.
    public func deleteReplaceRule(_ rule: ReplaceRule) {
        do {
            try environment.store.deleteReplaceRule(id: rule.id)
            reloadReplaceRules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - The bookmarks

    /// Reloads the bookmarks.
    public func reloadBookmarks() {
        do {
            bookmarks = try environment.store.allBookmarks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a bookmark.
    public func deleteBookmark(_ bookmark: Bookmark) {
        do {
            try environment.store.deleteBookmark(bookmark)
            reloadBookmarks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Inserts or updates a bookmark — upstream `BookmarkDao.insert`.
    public func saveBookmark(_ bookmark: Bookmark) {
        do {
            try environment.store.insert(bookmark)
            reloadBookmarks()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - The book groups

    /// Deletes a user group — upstream `BookGroupDao.delete`.
    public func deleteGroup(_ group: BookGroup) {
        guard group.groupId > 0 else { return }
        do {
            try environment.store.delete(groupId: group.groupId)
            reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The number of books in a group.
    public func bookCount(inGroup groupId: Int64) -> Int {
        (try? environment.store.books(inGroup: groupId).count) ?? 0
    }

    /// Adds or removes the favourite of an article — upstream
    /// `ReadRssActivity.updateFavorite`.
    public func toggleStar(_ article: RssArticle) {
        let result = RssLibrary.toggleStar(article: article, in: rssStars)
        do {
            if let star = result.star {
                try environment.store.insert(star)
            } else {
                try environment.store.deleteRssStar(link: article.link)
            }
            rssStars = try environment.store.allRssStars()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Adds the favourite of an article — upstream
    /// `ReadRssViewModel.addFavorite`.
    @discardableResult
    public func addStar(
        _ article: RssArticle,
        group: String = RssLibrary.defaultGroup
    ) -> RssStar? {
        if let existing = RssLibrary.star(of: article, in: rssStars) {
            return existing
        }
        let star = RssLibrary.makeStar(article: article, group: group)
        do {
            try environment.store.insert(star)
            rssStars = try environment.store.allRssStars()
        } catch {
            errorMessage = error.localizedDescription
        }
        return star
    }

    /// Updates a favourite — upstream `ReadRssViewModel.updateFavorite`.
    public func updateStar(_ star: RssStar) {
        do {
            try environment.store.insert(star)
            rssStars = try environment.store.allRssStars()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a favourite — upstream `ReadRssViewModel.delFavorite`.
    public func deleteStar(_ star: RssStar) {
        do {
            try environment.store.deleteRssStar(link: star.link)
            rssStars = try environment.store.allRssStars()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Marks an article as read — upstream `RssReadRecordDao`.
    public func markRead(_ article: RssArticle) {
        do {
            let result = RssLibrary.markRead(article: article, in: rssReadRecords)
            try environment.store.insert(result.record)
            rssReadRecords = try environment.store.allRssReadRecords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Whether an article is a favourite.
    public func isStarred(_ article: RssArticle) -> Bool {
        RssLibrary.star(of: article, in: rssStars) != nil
    }

    /// Deletes the articles of an RSS source — upstream
    /// `RssSortViewModel.clearArticles`.
    public func clearRssArticles(source: RssSource) {
        do {
            try environment.store.deleteRssArticles(origin: source.sourceUrl)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes every RSS read record — upstream
    /// `RssSortViewModel.deleteAllRecord`.
    public func deleteAllRssReadRecords() {
        do {
            try environment.store.deleteAllRssReadRecords()
            rssReadRecords = try environment.store.allRssReadRecords()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reloads everything.
    public func reloadAll() {
        reloadBookshelf()
        reloadSources()
        reloadRSS()
    }

    // MARK: - The automatic backup check

    /// The name of the backup on the WebDAV server that is newer than the
    /// last local one — upstream `MainActivity.backupSync()`.
    @Published public var pendingWebDavBackup: String?

    /// Checks whether the WebDAV server holds a backup that is newer than the
    /// last one this device knows about — upstream
    /// `MainActivity.backupSync()`.
    ///
    /// The upstream compares the modification time of the newest backup with
    /// `LocalConfig.lastBackup` and asks the user whether it should be
    /// restored; the time is remembered either way.
    public func checkNewBackup() async {
        guard environment.settings.autoCheckNewBackup else { return }
        let account = environment.settings.appWebDav
        guard account.isConfigured else { return }
        let service = WebDavService(
            configuration: account.serviceConfiguration,
            httpClient: environment.httpClient
        )
        guard let files = try? await service.backupNames(),
              let last = files.first,
              let modified = last.lastModified else { return }
        let known = environment.localConfig.lastBackup ?? .distantPast
        guard modified > known else { return }
        environment.localConfig.lastBackup = modified
        pendingWebDavBackup = last.name
    }

    /// Restores the backup the app found on the server — upstream
    /// `viewModel.restoreWebDav(name)`.
    public func restorePendingWebDavBackup() async {
        guard let name = pendingWebDavBackup else { return }
        pendingWebDavBackup = nil
        let account = environment.settings.appWebDav
        guard account.isConfigured else { return }
        let service = WebDavService(
            configuration: account.serviceConfiguration,
            httpClient: environment.httpClient
        )
        do {
            let data = try await service.downloadBackup(named: name)
            let settings = BackupSettings(
                password: environment.localConfig.password,
                deviceName: environment.settings.webDavDeviceName,
                onlyLatestBackup: environment.settings.onlyLatestBackup,
                ignoreLocalBook: false
            )
            let summary = try LegadoBackup.restore(
                zipData: data,
                store: environment.store.tableStore,
                settings: settings
            )
            if let files = try? BackupConfigFiles.files(inZipData: data) {
                applyBackupConfigFiles(files)
            }
            environment.localConfig.lastBackup = Date()
            reloadAll()
            errorMessage = nil
            backupMessage = "已恢复 \(summary.restoredRows) 条记录"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The daily automatic backup — upstream `Backup.autoBack()`.
    ///
    /// The upstream makes the backup when the main activity is destroyed —
    /// that is, when the app is closed. The port does it when the app goes to
    /// the background, which is the iOS equivalent of closing the app.
    ///
    /// The backup only happens once a day (`Backup.shouldBackup()`) and only
    /// when the server does not hold a backup with today's name yet
    /// (`AppWebDav.hasBackUp`). The reader background images go up with it
    /// (`AppWebDav.upBgs`).
    public func autoBackup() async {
        guard AutoBackup.shouldBackup(lastBackup: environment.localConfig.lastBackup) else { return }
        guard let service = webDavService() else { return }
        do {
            let settings = BackupSettings(
                password: environment.localConfig.password,
                deviceName: environment.settings.webDavDeviceName,
                onlyLatestBackup: environment.settings.onlyLatestBackup,
                ignoreLocalBook: false
            )
            let archive = try LegadoBackup.make(
                store: environment.store.tableStore,
                settings: settings,
                preferences: backupPreferences(),
                extraFiles: backupConfigFiles()
            )
            // Upstream `AppWebDav.hasBackUp(backupZipFileName)` — when the
            // server already holds today's backup only the time moves on.
            if try await service.hasBackup(named: archive.fileName) {
                environment.localConfig.lastBackup = Date()
                return
            }
            try await service.uploadBackup(archive)
            environment.localConfig.lastBackup = Date()
            // The reader background images are uploaded with the backup.
            let files = backgroundImageFiles()
            if !files.isEmpty {
                let remote = (try? await service.backgroundFiles().map { $0.name }) ?? []
                let pending = AutoBackup.pendingBackgrounds(local: files, remote: remote)
                if !pending.isEmpty {
                    try await service.uploadBackgrounds(pending)
                }
            }
        } catch {
            AppLog.shared.put("自动备份失败\n\(error.localizedDescription)", error: error)
        }
    }

    /// The cleanup that runs when the app starts — upstream `App.onCreate`
    /// (the "清除过期数据" block) and `DefaultData.upVersion`.
    ///
    /// The upstream runs it in a background thread when the process is
    /// created; the port runs it when the root view appears.
    public func runStartupMaintenance() async {
        // The default data of a new version — upstream `DefaultData.upVersion`.
        do {
            let imported = try AppMaintenance.importDefaultsAfterUpgrade(
                store: environment.store,
                localConfig: environment.localConfig
            )
            if !imported.isEmpty {
                AppLog.shared.put("导入默认数据：\(imported.joined(separator: ", "))")
            }
        } catch {
            AppLog.shared.put("导入默认数据失败\n\(error.localizedDescription)", error: error)
        }
        // The expired data — upstream `App.kt:101-122`.
        do {
            let report = try AppMaintenance.cleanUp(
                store: environment.store,
                settings: environment.settings,
                cacheStorage: environment.cacheStorage
            )
            if report.clearedBookCaches > 0 {
                AppLog.shared.put("清理失效缓存：\(report.clearedBookCaches) 个")
            }
        } catch {
            AppLog.shared.put("清理过期数据失败\n\(error.localizedDescription)", error: error)
        }
        // The reading progress of the WebDAV server — upstream
        // `AppWebDav.downloadAllBookProgress()`.
        if environment.settings.syncBookProgress, let service = webDavService() {
            do {
                let updated = try await AppMaintenance.downloadAllBookProgress(
                    store: environment.store,
                    service: service
                )
                if updated > 0 {
                    AppLog.shared.put("同步阅读进度：\(updated) 本")
                }
            } catch {
                AppLog.shared.put("同步阅读进度失败\n\(error.localizedDescription)", error: error)
            }
        }
    }

    /// The preferences that go into `config.xml` — the flat key/value pairs
    /// of the settings store.
    private func backupPreferences() -> [String: String] {
        var result: [String: String] = [:]
        for key in SettingsKey.allCases {
            if let value = environment.settings.string(key) {
                result[key.rawValue] = value
            }
        }
        return result
    }

    /// The reader background images of the presets — upstream
    /// `ReadBookConfig.getAllPicBgStr()` plus the file lookup of
    /// `Backup.backup()`.
    private func backgroundImageFiles() -> [(name: String, data: Data)] {
        guard let root = try? LocalFileStore.documentsDirectory() else { return [] }
        return AutoBackup.backgroundFiles(
            presets: environment.backgroundManager.presets,
            root: root
        )
    }

    // MARK: - The configuration files of a backup

    /// The configuration files that go into a backup beside the table dumps —
    /// upstream `Backup.backup()` writes `readConfig.json`,
    /// `themeConfig.json`, `coverRule.json` and `directLinkUploadRule.json`.
    public func backupConfigFiles() -> [BackupFile] {
        let readerConfig = environment.backgroundManager.configFileURL
            .flatMap { try? Data(contentsOf: $0) }
        let themeConfig = themeManager.configFileURL
            .flatMap { try? Data(contentsOf: $0) }
        let coverRule = BookCoverService.config(store: environment.store).jsonString
        let directLinkUpload = environment.settings.settingsStore.string(
            forKey: DirectLinkUpload.ruleKey
        )
        return BackupConfigFiles.files(
            readerConfig: readerConfig,
            themeConfig: themeConfig,
            coverRule: coverRule,
            directLinkUpload: directLinkUpload
        )
    }

    /// Applies the configuration files of a backup — upstream
    /// `Restore.restoreLocked` restores every configuration file into its own
    /// place.
    ///
    /// - Parameter files: the configuration files of the backup, by name.
    /// - Returns: the number of the applied files.
    @discardableResult
    public func applyBackupConfigFiles(_ files: [String: BackupFile]) -> Int {
        var applied = 0
        // The reader configuration — the background presets.
        if let file = files[BackupConfigFiles.readerConfigFileName],
           let url = environment.backgroundManager.configFileURL {
            if writeBackupFile(file, to: url) {
                environment.backgroundManager.reload()
                applied += 1
            }
        }
        // The themes.
        if let file = files[BackupConfigFiles.themeConfigFileName],
           let url = themeManager.configFileURL {
            if writeBackupFile(file, to: url) {
                themeManager.reload()
                applied += 1
            }
        }
        // The cover rule — upstream `BookCover.saveCoverRule(json)`.
        if let file = files[BackupConfigFiles.coverRuleFileName],
           let rule = CoverRule.parse(file.string) {
            try? BookCoverService.save(rule, store: environment.store)
            applied += 1
        }
        // The direct link upload rules — upstream `DirectLinkUpload.putConfig`.
        if let file = files[BackupConfigFiles.directLinkUploadFileName],
           let rule = try? JSONDecoder().decode(
               DirectLinkUploadRule.self,
               from: Data(file.string.utf8)
           ) {
            DirectLinkUpload.putConfig(rule, store: environment.settings.settingsStore)
            applied += 1
        }
        return applied
    }

    /// Writes a file of a backup into the application container.
    private func writeBackupFile(_ file: BackupFile, to url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try file.data.write(to: url)
            return true
        } catch {
            AppLog.shared.put("恢复配置文件失败\n\(error.localizedDescription)", error: error)
            return false
        }
    }

    // MARK: - Bookshelf

    /// Selects another group.
    public func select(groupId: Int64) {
        selectedGroupId = groupId
        reloadBookshelf()
    }

    /// The books of the current group, filtered by the search field.
    ///
    /// Upstream `BookShelfViewModel` keeps the filter in the search view
    /// model; the port applies it on top of the group query.
    public var visibleBooks: [Book] {
        let keyword = bookFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return books }
        return books.filter {
            $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.author.localizedCaseInsensitiveContains(keyword)
        }
    }

    /// The groups the user created — upstream `BookGroupDao.all` without the
    /// well known groups (`BookGroup.Id.allIds`).
    public var userGroups: [BookGroup] {
        groups.filter { !BookGroup.Id.allIds.contains($0.groupId) }
    }

    /// The number of the books of a group whose update failed — upstream
    /// `MainViewModel.postUpBooksLiveData` shows the number of the books that
    /// wait for an update on the bottom navigation.
    public func waitingUpdateCount(inGroup groupId: Int64) -> Int {
        books.filter { book in
            guard BookType.contains(book.type, BookType.updateError) else { return false }
            if groupId == BookGroup.Id.all || groupId == BookGroup.Id.root { return true }
            if groupId == BookGroup.Id.updateError { return true }
            guard groupId > 0 else { return false }
            return (book.group & groupId) > 0
        }.count
    }

    /// Adds a group — upstream `BookGroupDialog` (the name must be unique).
    public func addGroup(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            guard try environment.store.canAddGroup() else {
                errorMessage = "分组数量已达上限"
                return
            }
            let groupId = try environment.store.unusedGroupId()
            let order = (try environment.store.allGroups().last?.order ?? 0) + 1
            let group = BookGroup(
                groupId: groupId,
                groupName: trimmed,
                cover: nil,
                order: order,
                enableRefresh: false,
                show: true,
                bookSort: 0
            )
            try environment.store.insert(group)
            reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Renames a group — upstream `BookGroupDialog`.
    public func renameGroup(_ group: BookGroup, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var updated = group
        updated.groupName = trimmed
        do {
            try environment.store.insert(updated)
            reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Shows or hides a group — upstream `BookGroupDao.updateShow`.
    public func setGroup(_ group: BookGroup, show: Bool) {
        var updated = group
        updated.show = show
        do {
            try environment.store.insert(updated)
            reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Turns the automatic update of a group on or off — upstream
    /// `BookGroupDao.updateEnableRefresh`.
    public func setGroup(_ group: BookGroup, enableRefresh: Bool) {
        var updated = group
        updated.enableRefresh = enableRefresh
        do {
            try environment.store.insert(updated)
            reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sets the cover of a group — upstream `GroupEditDialog` (the `ivCover`
    /// image picker) and `BookGroupDao.update`.
    ///
    /// The path is the copy the app made of the picked image — upstream
    /// `externalFiles/covers/<md5>.<suffix>`.
    public func setGroupCover(_ group: BookGroup, cover: String?) {
        var updated = group
        updated.cover = cover
        do {
            try environment.store.insert(updated)
            reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sets the sort order of a group — upstream `GroupEditDialog` (the
    /// `spSort` spinner) and `BookGroupDao.updateBookSort`.
    ///
    /// The value is the upstream `bookSort`: -1 follows the global sort of the
    /// bookshelf, 0…5 are the six sorts of `BookshelfSort`.
    public func setGroupSort(_ group: BookGroup, sort: Int) {
        var updated = group
        updated.bookSort = Int64(sort)
        do {
            try environment.store.insert(updated)
            reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Reorders the groups — upstream `BookGroupDao.updateOrder`.
    public func moveGroups(from source: IndexSet, to destination: Int) {
        var all = groups
        guard let first = source.first, first >= 0, first < all.count else { return }
        let moved = all.remove(at: first)
        let target = min(max(destination, 0), all.count)
        all.insert(moved, at: target)
        for (index, group) in all.enumerated() {
            var updated = group
            updated.order = Int64(index)
            try? environment.store.insert(updated)
        }
        reloadBookshelf()
    }

    /// Adds the books of the addresses — upstream
    /// `BookshelfViewModel.addBookByUrl`.
    ///
    /// The address is matched against the sources that have a `bookUrlPattern`;
    /// the book is fetched, its chapters are loaded and it is put on the shelf.
    public func addBooksByUrl(_ text: String) async -> String {
        let urls = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !urls.isEmpty else { return "地址为空" }
        var added = 0
        for url in urls {
            if (try? environment.store.book(url: url)) != nil {
                added += 1
                continue
            }
            guard let source = sourceForBookUrl(url) else { continue }
            var book = Book(bookUrl: url, origin: source.bookSourceUrl, originName: source.bookSourceName)
            do {
                book = try await environment.loadBookInfo(book: book, source: source)
                let chapters = try await environment.loadChapterList(book: book, source: source)
                try environment.store.insert(book)
                try environment.store.insert(chapters.chapters)
                added += 1
            } catch {
                continue
            }
        }
        reloadBookshelf()
        return added > 0 ? "成功添加 \(added) 本书" : "添加网址失败"
    }

    /// The source that can open the address of a book — upstream
    /// `BookSourceDao.getBookSourceAddBook` and `hasBookUrlPattern`.
    private func sourceForBookUrl(_ url: String) -> BookSource? {
        let all = (try? environment.sources()) ?? []
        if let host = NetworkUtils.baseUrl(url), let exact = all.first(where: {
            NetworkUtils.baseUrl($0.bookSourceUrl) == host
        }) {
            return exact
        }
        return all.first { source in
            guard let pattern = source.bookUrlPattern, !pattern.isEmpty else { return false }
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            let range = NSRange(url.startIndex..<url.endIndex, in: url)
            return regex.firstMatch(in: url, options: [], range: range) != nil
        }
    }

    /// Imports a shelf — upstream `BookshelfViewModel.importBookshelf`.
    ///
    /// The text is either an absolute address (the document is fetched) or a
    /// JSON array of `{name, author, intro}` objects; the books that are
    /// already on the shelf are skipped.
    public func importBookshelf(_ text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "内容为空" }
        var json = trimmed
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            do {
                let response = try await environment.httpClient.send(HttpRequest(url: trimmed))
                json = response.body ?? ""
            } catch {
                return "下载失败：\(error.localizedDescription)"
            }
        }
        let rows = BookshelfExport.parse(json)
        guard !rows.isEmpty else { return "格式不对" }
        var added = 0
        for row in rows {
            if bookExists(name: row.name, author: row.author) { continue }
            guard let source = matchingSource(name: row.name, author: row.author) else { continue }
            var book = Book(
                bookUrl: "\(source.bookSourceUrl)#\(row.name)#\(row.author)",
                origin: source.bookSourceUrl,
                originName: source.bookSourceName
            )
            book.name = row.name
            book.author = row.author
            book.intro = row.intro
            do {
                book = try await environment.loadBookInfo(book: book, source: source)
                let chapters = try await environment.loadChapterList(book: book, source: source)
                try environment.store.insert(book)
                try environment.store.insert(chapters.chapters)
                added += 1
            } catch {
                continue
            }
        }
        reloadBookshelf()
        return added > 0 ? "成功导入 \(added) 本书" : "没有导入任何书籍"
    }

    /// Whether a book with that name and author is already on the shelf.
    private func bookExists(name: String, author: String) -> Bool {
        books.contains { $0.name == name && $0.author == author }
    }

    /// The source that knows a book — upstream `BookshelfViewModel` looks the
    /// book up with the search of every source.
    private func matchingSource(name: String, author: String) -> BookSource? {
        let all = (try? environment.sources()) ?? []
        for source in all {
            guard source.enabled else { continue }
            let results = awaitSearch(source: source, keyword: name)
            if results.contains(where: { $0.name == name && $0.author == author }) {
                return source
            }
        }
        return nil
    }

    /// Searches a source and swallows the errors — the helper of
    /// `matchingSource(name:author:)`.
    private func awaitSearch(source: BookSource, keyword: String) -> [SearchBook] {
        let semaphore = DispatchSemaphore(value: 0)
        var result: [SearchBook] = []
        Task {
            result = (try? await environment.search(source: source, keyword: keyword)) ?? []
            semaphore.signal()
        }
        semaphore.wait()
        return result
    }

    /// Removes a book from the shelf.
    public func removeFromShelf(_ book: Book) {
        do {
            try environment.deleteBook(book)
            reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Adds a book to the shelf.
    public func addToShelf(_ book: Book, groupId: Int64? = nil) {
        do {
            try environment.saveToShelf(book, groupId: groupId)
            reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Sources

    /// Imports the sources of a JSON document.
    public func importSources(json: String) {
        do {
            let count = try environment.importSources(json: json)
            reloadSources()
            errorMessage = nil
            _ = count
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The sources as a JSON document.
    public func exportedSources() -> String {
        (try? environment.exportSources()) ?? "[]"
    }

    /// Enables or disables a source (upstream `SourceManager.enableBookSource`).
    public func setSource(_ source: BookSource, enabled: Bool) {
        var updated = source
        updated.enabled = enabled
        do {
            try environment.store.insert(updated)
            reloadSources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a source.
    public func deleteSource(_ source: BookSource) {
        do {
            try environment.store.deleteSources(urls: [source.bookSourceUrl])
            reloadSources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves an edited source (upstream `EditBookSourceViewModel.saveSource`).
    public func saveSource(_ source: BookSource) {
        do {
            try environment.store.insert(source)
            reloadSources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Moves a source to the top or to the bottom — upstream
    /// `ChangeBookSourceViewModel.topSource` / `bottomSource`.
    public func moveSource(_ source: BookSource, toTop: Bool) {
        do {
            let all = try environment.sources()
            var updated = source
            updated.customOrder = toTop
                ? SourceOrdering.topOrder(of: all)
                : SourceOrdering.bottomOrder(of: all)
            try environment.store.insert(updated)
            reloadSources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The user score of a book in a source — upstream
    /// `SourceConfig.getBookScore`.
    public func bookScore(origin: String, name: String, author: String) -> Int {
        SourceConfig.load(store: environment.store)
            .bookScore(origin: origin, name: name, author: author)
    }

    /// Sets the user score of a book in a source — upstream
    /// `SourceConfig.setBookScore`.
    public func setBookScore(origin: String, name: String, author: String, score: Int) {
        var config = SourceConfig.load(store: environment.store)
        config.setBookScore(origin: origin, name: name, author: author, score: score)
        SourceConfig.save(config, store: environment.store)
    }

    /// Enables or disables several sources at once — upstream
    /// `SourceManagerViewModel.enableBookSource` with a multi-selection.
    public func setSources(_ sources: [BookSource], enabled: Bool) {
        for source in sources {
            var updated = source
            updated.enabled = enabled
            try? environment.store.insert(updated)
        }
        reloadSources()
    }

    /// Deletes several sources at once — upstream
    /// `SourceManagerViewModel.deleteBookSource` with a multi-selection.
    public func deleteSources(_ sources: [BookSource]) {
        let urls = sources.map(\.bookSourceUrl)
        guard !urls.isEmpty else { return }
        do {
            try environment.store.deleteSources(urls: urls)
            reloadSources()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - The "我的" screens

    /// Saves a TXT table of contents rule — upstream `TxtTocRuleDao.insert`.
    public func saveTxtTocRule(_ rule: TxtTocRule) {
        do {
            try environment.store.insert(rule)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves a dictionary rule — upstream `DictRuleDao.insert`.
    public func saveDictRule(_ rule: DictRule) {
        do {
            try environment.store.insert(rule)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes the dictionary rules — upstream `DictRuleViewModel.delete`.
    public func deleteDictRules(_ rules: [DictRule]) {
        do {
            try environment.store.deleteDictRules(rules)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Enables or disables the dictionary rules — upstream
    /// `DictRuleViewModel.enableSelection` / `disableSelection`.
    public func setDictRulesEnabled(_ rules: [DictRule], enabled: Bool) {
        do {
            try environment.store.updateDictRules(
                DictRuleManager.settingEnabled(rules, enabled)
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Writes the order of the dictionary rules — upstream
    /// `DictRuleViewModel.upSortNumber`.
    public func saveDictRuleOrder(_ rules: [DictRule]) {
        do {
            try environment.store.updateDictRules(DictRuleManager.renumbered(rules))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Imports the dictionary rules of a document — upstream
    /// `DictRuleActivity.menu_import_local` / `menu_import_onLine` /
    /// `menu_import_qr`.
    @discardableResult
    public func importDictRules(_ text: String) -> Int {
        do {
            let rules = try DictRuleManager.parse(text)
            try environment.store.updateDictRules(rules)
            return rules.count
        } catch {
            errorMessage = error.localizedDescription
            return 0
        }
    }

    /// Saves a HTTP TTS engine — upstream `HttpTTSDao.insert`.
    public func saveHttpTTS(_ engine: HttpTTS) {
        do {
            try environment.store.insert(engine)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Saves a RSS source — upstream `RssSourceDao.insert`.
    public func saveRssSource(_ source: RssSource) {
        do {
            try environment.store.insert(source)
            reloadRSS()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deletes a RSS source — upstream `RssSourceDao.delete`.
    public func deleteRssSource(_ source: RssSource) {
        do {
            try environment.store.deleteRssSources(urls: [source.sourceUrl])
            reloadRSS()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The groups of the book sources — upstream `BookSourceGroupDao.all`.
    public func sourceGroups() -> [String] {
        var seen: [String] = []
        for source in sources {
            let group = source.bookSourceGroup ?? ""
            if group.isEmpty { continue }
            for name in group.split(separator: ",").map(String.init) {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty && !seen.contains(trimmed) {
                    seen.append(trimmed)
                }
            }
        }
        return seen.sorted()
    }

    /// Removes a group from every source — upstream
    /// `BookSourceDao.removeGroup`.
    public func removeSourceGroup(_ group: String) {
        for var source in sources {
            guard source.hasGroup(group) else { continue }
            source.removeGroup(group)
            saveSource(source)
        }
    }

    // MARK: - Reader

    /// Opens the reader for a book (upstream `ReadBookActivity`).
    ///
    /// The chapter list is taken from the store; when the book has no chapters
    /// yet they are loaded from the source first.
    ///
    /// An image book (a comic) opens the manga reader when the pref
    /// `showMangaUi` is on — upstream `ContextExtensions.kt:64-78`.
    public func openReader(for book: Book, chapterIndex: Int? = nil, chapterPos: Int? = nil) async {
        do {
            var book = book
            // The local copy of a book that lives on the WebDAV server may be
            // missing — upstream `LocalBook.getBookInputStream` downloads it.
            if book.isLocal, LocalBookReader.fileURL(for: book) == nil,
               let downloaded = await downloadRemoteLocalBook(book) {
                book = downloaded
            }
            var chapters = try environment.chapters(of: book)
            if chapters.isEmpty, let source = try environment.source(for: book) {
                chapters = try await environment.loadChapterList(book: book, source: source).chapters
            }
            guard !chapters.isEmpty else {
                errorMessage = "没有章节"
                return
            }
            if book.isImage, environment.settings.bool(SettingsKey.showMangaUi, default: true) {
                let controller = MangaReaderController(
                    environment: environment,
                    book: book,
                    chapters: chapters
                )
                controller.model = self
                mangaReader = controller
                isMangaPresented = true
                return
            }
            let controller = ReaderController(
                environment: environment,
                book: book,
                chapters: chapters
            )
            controller.model = self
            controller.startChapterIndex = chapterIndex
            controller.startChapterPos = chapterPos
            reader = controller
            isReaderPresented = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Opens the last-read book when the preference `defaultToRead` is on.
    ///
    /// Upstream `ui/welcome/WelcomeActivity.startMainActivity` opens the
    /// reader directly after the splash when the user enabled it.
    public func openDefaultRead() async {
        guard environment.settings.bool(.defaultToRead, default: false) else { return }
        guard let book = try? environment.bookshelf().lastReadBook() else { return }
        await openReader(for: book)
    }

    // MARK: - The tabs of the shell

    /// Shows a tab of the shell.
    ///
    /// Upstream the bottom navigation of `MainActivity` only shows the
    /// explore and the RSS tab when their preference is on
    /// (`MainActivity.upHomePage()`).
    public func selectTab(_ tab: HomePage) {
        guard tab.isVisible(
            showDiscovery: environment.settings.showDiscovery,
            showRSS: environment.settings.showRSS
        ) else { return }
        selectedTab = tab
    }

    /// The moment the last tap on a tab happened — upstream `MainActivity`
    /// remembers it in `bookshelfReselected` / `exploreReselected`.
    private var lastTabTap: [HomePage: Date] = [:]

    /// Handles a tap on the tab that is already active — upstream
    /// `MainActivity.onNavigationItemReselected`.
    ///
    /// The upstream scrolls the list of the tab to the top when the tab is
    /// tapped twice within 300 ms: the bookshelf jumps to its first book
    /// (`BooksFragment.gotoTop`) and the discovery collapses the expanded
    /// source (`ExploreFragment.compressExplore`).
    public func tabReselected(_ tab: HomePage) {
        let now = Date()
        if let last = lastTabTap[tab], now.timeIntervalSince(last) < 0.3 {
            lastTabTap[tab] = nil
            switch tab {
            case .bookshelf:
                scrollToTopToken += 1
            case .explore:
                collapseExploreToken += 1
            default:
                break
            }
        } else {
            lastTabTap[tab] = now
        }
    }

    /// The request to scroll the list of the current tab to the top — the
    /// second tap on the tab (upstream `BooksFragment.gotoTop`).
    @Published public var scrollToTopToken = 0

    /// The request to collapse the discovery — the second tap on the
    /// discovery tab (upstream `ExploreFragment.compressExplore`).
    @Published public var collapseExploreToken = 0

    /// The number of the books that wait for the update of their table of
    /// contents — the badge of the bookshelf tab (upstream
    /// `MainViewModel.postUpBooksLiveData`).
    @Published public var upBooksCount = 0

    /// Shows the tab of the `defaultHomePage` preference — upstream
    /// `MainActivity.upHomePage()` (`MainActivity.kt:385-398`).
    public func applyDefaultHomePage() {
        selectTab(environment.settings.homePage)
    }

    // MARK: - The shortcuts of the home screen

    /// The keyword of a search that a link asked for — upstream
    /// `SearchActivity.start(this, text)` (the shared text of the
    /// `SharedReceiverActivity`).
    @Published public var pendingSearchKeyword: String?

    /// Searches for a keyword.
    ///
    /// Upstream the shared text that is not an address is searched for in
    /// `SearchActivity`; the port opens the same screen through the discover
    /// tab.
    public func search(_ keyword: String) {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingSearchKeyword = trimmed
        selectTab(.explore)
    }

    /// Opens the book that was read last.
    ///
    /// Upstream the shortcut `buildReadBookShortCutInfo` of `api/ShortCuts.kt`
    /// opens the `ReadBookActivity` of the last book.
    public func openLastRead() async {
        guard let book = try? environment.bookshelf().lastReadBook() else {
            errorMessage = "没有最近阅读的书籍"
            return
        }
        await openReader(for: book)
    }

    /// Reads the book that was read last aloud.
    ///
    /// Upstream the shortcut `buildReadAloudShortCutInfo` of
    /// `api/ShortCuts.kt` starts the read aloud service of the last book.
    public func startLastReadAloud() async {
        guard let book = try? environment.bookshelf().lastReadBook() else {
            errorMessage = "没有最近阅读的书籍"
            return
        }
        await openReader(for: book)
        await reader?.startReadAloud()
    }

    // MARK: - The shelf question of the reader

    /// Asks whether the book that was read should be put on the shelf.
    ///
    /// Upstream `ReadBookActivity.finish()` (`ReadBookActivity.kt:1592-1613`):
    /// when the reader is closed and the book is not on the shelf, the app
    /// asks "是否将《书名》加入书架？"; the answer "no" removes the book
    /// again (`ReadBookViewModel.removeFromBookshelf` → `book.delete()`).
    /// The preference `showAddToShelfAlert` skips the question.
    public func readerDidClose() {
        guard let book = reader?.book, !book.isOnShelf else { return }
        if environment.settings.showAddToShelfAlert {
            pendingShelfBook = book
        } else {
            try? environment.deleteBook(book)
            reloadBookshelf()
        }
    }

    /// The user accepted the question of the reader — the book goes on the
    /// shelf (upstream: the `notShelf` flag is cleared and the book is
    /// saved).
    public func addPendingBookToShelf() {
        guard let book = pendingShelfBook else { return }
        pendingShelfBook = nil
        try? environment.saveToShelf(book)
        reloadBookshelf()
    }

    /// The user declined the question of the reader — the book is removed.
    public func declinePendingBook() {
        guard let book = pendingShelfBook else { return }
        pendingShelfBook = nil
        try? environment.deleteBook(book)
        reloadBookshelf()
    }

    // MARK: - Settings

    /// The bookshelf sort of the current group.
    public var bookshelfSort: BookshelfSort {
        BookshelfSort(rawValue: environment.settings.bookshelfSort) ?? .byDuration
    }

    /// The theme that is currently applied.
    public var currentTheme: AppTheme {
        themeManager.currentTheme(isSystemDark: isSystemDark)
    }

    /// The theme mode.
    public var themeMode: ThemeMode {
        themeManager.mode
    }

    /// Switches the theme mode (upstream `AppConfig.themeMode`).
    public func setThemeMode(_ mode: ThemeMode) {
        themeManager.mode = mode
        environment.settings.themeMode = String(mode.rawValue)
        themeManager.save()
    }

    /// Selects another theme of the list.
    ///
    /// Upstream `ThemeConfig.applyConfig` — the colours of the theme are
    /// copied into the day or the night preferences.
    public func selectTheme(index: Int) {
        themeManager.select(index: index)
        themeManager.save()
        if themeManager.themes.indices.contains(index) {
            themeManager.applyConfig(themeManager.themes[index], to: environment.settings)
        }
    }

    /// Applies a reader style archive — upstream
    /// `OnLineImportViewModel.importReadConfig` and `ReadBookConfig.import`.
    ///
    /// The font of the archive is copied into the font folder of the app and
    /// the configuration is written into the reader preferences.
    public func applyReaderStyleArchive(_ payload: ReaderConfigArchive.Payload) throws {
        if let font = payload.font {
            let directory = readerFontDirectory()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let destination = directory.appendingPathComponent(font.name)
            try font.data.write(to: destination)
            environment.settings.set(destination.path, for: .fontFolder)
        }
        ReaderConfigStore(settings: environment.settings).save(payload.config)
    }

    /// Where the fonts of the reader are stored — upstream `<externalFiles>/font`.
    public func readerFontDirectory() -> URL {
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("font", isDirectory: true)
    }

    // MARK: - The shared layout

    /// The shared layout — upstream `ReadBookConfig.shareConfig`.
    public func shareReaderConfig() -> ReaderConfig {
        ReaderConfigStore(settings: environment.settings).loadShare()
    }

    /// Saves the shared layout — upstream `ReadBookConfig.save()` writes the
    /// share configuration next to the current one.
    public func saveShareReaderConfig(_ config: ReaderConfig) {
        ReaderConfigStore(settings: environment.settings).saveShare(config)
    }

    /// Whether the shared layout is used — upstream `ReadBookConfig.shareLayout`.
    public var shareLayoutEnabled: Bool {
        environment.settings.shareLayout
    }

    /// Turns the shared layout on or off — upstream `ReadBookConfig.shareLayout`.
    public func setShareLayout(_ enabled: Bool) {
        environment.settings.shareLayout = enabled
    }

    /// The layout that the reader uses — upstream
    /// `ReadBookConfig.config get() = if (shareLayout) shareConfig else durConfig`.
    public func effectiveReaderConfig() -> ReaderConfig {
        ShareLayout.effective(
            current: ReaderConfigStore(settings: environment.settings).load(),
            share: shareReaderConfig(),
            enabled: shareLayoutEnabled
        )
    }

    // MARK: - The startup sequence

    /// The phase of the startup sequence — upstream
    /// `MainActivity.onPostCreate()`.
    public enum StartupPhase: Equatable {
        /// Nothing to do.
        case idle
        /// The privacy policy has to be accepted.
        case privacyPolicy
        /// The help of the app or the changelog has to be shown.
        case document(StartupDocument)
        /// The reader crashed and the user should be offered the crash log.
        case crashPrompt
        /// The startup sequence is finished.
        case done
    }

    /// The phase of the startup sequence.
    @Published public var startupPhase: StartupPhase = .idle

    /// Whether the crash log is shown — upstream `CrashLogsDialog`.
    @Published public var isCrashLogPresented = false

    /// Whether the startup sequence already ran.
    private var hasStartedStartup = false

    /// Runs the startup sequence — upstream `MainActivity.onPostCreate()`.
    ///
    /// The privacy policy comes first: while it has not been accepted the app
    /// must not be used, so the sequence stops there and continues when the
    /// user agrees.
    public func runStartup() async {
        guard !hasStartedStartup else { return }
        hasStartedStartup = true
        // The local web service — upstream `WebService.start(context)` is
        // called when the preference is on.
        if environment.settings.webServiceEnabled {
            startWebService()
        }
        if StartupService.needsPrivacyPolicy(localConfig: environment.localConfig) {
            startupPhase = .privacyPolicy
            return
        }
        await continueStartup()
    }

    /// The user accepted the privacy policy.
    public func acceptPrivacyPolicy() {
        environment.localConfig.privacyPolicyAccepted = true
        startupPhase = .idle
        Task { await continueStartup() }
    }

    /// The user refused the privacy policy.
    ///
    /// The upstream closes the app (`MainActivity.privacyPolicy()`); an iOS
    /// app must never close itself, so the gate stays.
    public func refusePrivacyPolicy() {
        startupPhase = .privacyPolicy
    }

    /// The startup document was read.
    public func dismissStartupDocument() {
        startupPhase = .idle
        Task { await continueStartup() }
    }

    /// The user answered the crash question.
    public func answerCrashPrompt(showLogs: Bool) {
        startupPhase = .done
        if showLogs {
            isCrashLogPresented = true
        }
        finishStartup()
    }

    private func continueStartup() async {
        // The version check — the help of the app on the first run, the
        // changelog after an update.
        if let document = StartupService.startupDocument(
            localConfig: environment.localConfig,
            versionCode: Self.appVersionCode
        ) {
            startupPhase = .document(document)
            return
        }
        // A crash of the reader is reported.
        if StartupService.needsCrashPrompt(localConfig: environment.localConfig) {
            startupPhase = .crashPrompt
            return
        }
        startupPhase = .done
        finishStartup()
    }

    /// The last steps of the startup sequence — the automatic update of the
    /// books (upstream `viewModel.upAllBookToc()`) and the start page
    /// (upstream `MainActivity.upHomePage()`).
    private func finishStartup() {
        applyDefaultHomePage()
        guard environment.settings.autoRefreshBook else { return }
        Task { await updateAllBooks() }
    }

    /// The version code of the app — upstream `appInfo.versionCode`.
    static var appVersionCode: Int {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
           let code = Int(version) {
            return code
        }
        return 1
    }

    // MARK: - The local web service

    /// The state of the local web service — upstream `WebService.isRun`.
    @Published public var webServiceStatus: LegadoServer.Status?

    /// The running server.
    private var webService: LegadoServer?

    /// The address of the local web service — upstream `WebService.hostAddress`.
    ///
    /// The loopback address comes first so that the user can open it on the
    /// device itself.
    public var webServiceAddress: String? {
        webServiceStatus?.addresses.first
    }

    /// Starts the local web service — upstream `WebService.start(context)`.
    ///
    /// The upstream starts it when the preference changes
    /// (`MyFragment.onSharedPreferenceChanged`) and stops it when the
    /// preference is switched off.
    public func startWebService() {
        guard webService == nil else {
            webServiceStatus = webService?.status
            return
        }
        let configuration = LegadoAPIConfiguration(
            token: environment.localConfig.webServiceToken,
            port: environment.settings.webPort,
            bookshelfSort: environment.settings.bookshelfSort
        )
        let server = LegadoServer(configuration: configuration)
        // The API works on the real database, not on an in-memory one.
        server.sharedStore = environment.store
        server.contentProvider = { [weak self] book, chapter in
            guard let self else { return nil }
            return await self.webServiceContent(book: book, chapter: chapter)
        }
        server.chapterListProvider = { [weak self] source, book in
            guard let self else { return [] }
            let result = try? await WebBook.getChapterList(
                bookSource: source,
                book: book,
                dependencies: self.environment.dependencies()
            )
            return result?.chapters ?? []
        }
        // Upstream `BookController.refreshToc` reads the table of contents of
        // a local book with `LocalBook.getChapterList(book)`.
        server.localChapterListProvider = { [weak self] book in
            guard let self else { return [] }
            return try await self.webServiceLocalChapterList(book: book)
        }
        server.imageProvider = { [weak self] url, width in
            guard let self else { return nil }
            return await self.webServiceImage(url: url, width: width)
        }
        // Upstream `BookController.saveBook` / `saveBookProgress` upload the
        // progress to the WebDAV.
        server.progressUploader = { [weak self] book in
            await self?.webServiceUploadProgress(book: book)
        }
        do {
            try server.start()
            webService = server
            webServiceStatus = server.status
            // The upstream posts a notification when the service starts
            // (`WebService.kt:196-213`).
            if let address = server.status.addresses.first {
                NotificationService.shared.post(
                    NotificationContent.webService(address: address, port: server.status.httpPort)
                )
            }
        } catch {
            webService = nil
            webServiceStatus = nil
            errorMessage = "本地服务启动失败：\(error.localizedDescription)"
        }
    }

    /// Stops the local web service — upstream `WebService.stop(context)`.
    public func stopWebService() {
        webService?.stop()
        webService = nil
        webServiceStatus = nil
    }

    /// Starts or stops the service when the preference changes.
    public func setWebServiceEnabled(_ enabled: Bool) {
        environment.settings.webServiceEnabled = enabled
        if enabled {
            startWebService()
        } else {
            stopWebService()
        }
    }

    /// Restarts the service when it is running — the port changed.
    public func restartWebServiceIfRunning() {
        guard webService != nil else { return }
        stopWebService()
        startWebService()
    }

    /// The content of a chapter for the local API — upstream
    /// `BookController.getBookContent`.
    ///
    /// The upstream runs the content through the processor:
    /// `ContentProcessor.get(book.name, book.origin)
    /// .getContent(book, chapter, content, includeTitle = false)`.
    private func webServiceContent(book: Book, chapter: BookChapter) async -> String? {
        // The cached content comes first — the upstream serves the cache too.
        if let cached = environment.cacheStorage?.content(book: book, chapter: chapter), !cached.isEmpty {
            return processedWebServiceContent(book: book, chapter: chapter, raw: cached)
        }
        guard let source = try? environment.source(for: book) else { return nil }
        let dependencies = environment.dependencies()
        guard let raw = try? await WebBook.getContent(
            bookSource: source,
            book: book,
            bookChapter: chapter,
            dependencies: dependencies
        ) else {
            return nil
        }
        return processedWebServiceContent(book: book, chapter: chapter, raw: raw)
    }

    /// The content processor of the local API — upstream
    /// `ContentProcessor.getContent(book, chapter, content, includeTitle = false)`.
    ///
    /// The duplicated title is removed, the replace rules and the Chinese
    /// conversion are applied.
    private func processedWebServiceContent(book: Book, chapter: BookChapter, raw: String) -> String {
        let titleRules = (try? environment.store.replaceRulesForTitle(name: book.name, origin: book.origin)) ?? []
        let contentRules = (try? environment.store.replaceRulesForContent(name: book.name, origin: book.origin)) ?? []
        let mode = ChineseConversionMode(rawValue: environment.settings.chineseConverterType) ?? .off
        let processed = (try? ReplaceRuleEngine.processContent(
            book: book,
            chapter: chapter,
            content: raw,
            includeTitle: false,
            useReplace: book.useReplaceRule,
            chineseConvert: mode != .off,
            reSegment: true,
            titleRules: titleRules,
            contentRules: contentRules,
            conversionMode: mode,
            converter: DefaultChineseConverter(),
            scriptEngine: environment.scriptEngine
        ))?.contents.joined(separator: "\n") ?? raw
        return processed
    }

    /// The table of contents of a local book — upstream
    /// `LocalBook.getChapterList(book)`.
    private func webServiceLocalChapterList(book: Book) async throws -> [BookChapter] {
        let importer = localImporter
        guard let importer, let file = importer.fileURL(for: book) else {
            throw WebServiceError.localBookMissing
        }
        let rules = (try? environment.store.enabledTxtTocRules()) ?? []
        let imported = try LocalBook.importFile(
            fileURL: file,
            bookUrl: book.bookUrl,
            tocRules: rules
        )
        return imported.chapters
    }

    /// Uploads the reading progress to the WebDAV — upstream
    /// `AppWebDav.uploadBookProgress`.
    private func webServiceUploadProgress(book: Book) async {
        guard environment.settings.appWebDav.isConfigured else { return }
        guard let service = webDavService() else { return }
        do {
            try await service.uploadProgress(BookProgress(book: book))
        } catch {
            AppLog.shared.put("上传阅读进度失败", error: error)
        }
    }

    /// The bytes of an image for the local API — upstream
    /// `BookController.getCover` / `getImage`.
    ///
    /// The upstream scales the image to the requested width
    /// (`ImageProvider.getImage(book, src, width)`) and sends a PNG
    /// (`web/HttpServer.kt:103-114`).
    private func webServiceImage(url: String, width: Int?) async -> Data? {
        guard let absolute = URL(string: url), absolute.scheme != nil else { return nil }
        let response = try? await environment.httpClient.send(HttpRequest(url: url, method: "GET"))
        guard let data = response?.data, !data.isEmpty else { return nil }
        return scaledWebServiceImage(data, width: width)
    }

    /// Scales an image to the width and converts it into a PNG.
    ///
    /// On the platforms without UIKit the original bytes are returned; the
    /// server derives the content type from the bytes themselves.
    private func scaledWebServiceImage(_ data: Data, width: Int?) -> Data {
        #if canImport(UIKit)
        guard let image = UIImage(data: data) else { return data }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return data }
        let targetWidth = CGFloat(width ?? Int(size.width))
        guard targetWidth > 0, targetWidth < size.width else {
            return image.pngData() ?? data
        }
        let target = CGSize(width: targetWidth, height: size.height * targetWidth / size.width)
        let renderer = UIGraphicsImageRenderer(size: target)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return scaled.pngData() ?? data
        #else
        return data
        #endif
    }
}
