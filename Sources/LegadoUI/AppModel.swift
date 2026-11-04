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
        options: BookExportOptions = BookExportOptions()
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
                to: BookExportFileWriter.exportDirectory(),
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
                to: BookExportFileWriter.exportDirectory()
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
        verification: SourceVerificationCoordinator? = nil
    ) {
        self.environment = environment
        self.themeManager = themeManager
        self.localImporter = localImporter
        self.cacheManager = cacheManager
        self.verification = verification
    }

    /// The cache queue (upstream `CacheBook`).
    public let cacheManager: CacheBookManager?

    /// The coordinator of the source verification (upstream
    /// `SourceVerificationHelp`). The rule scripts ask it for the captcha
    /// answer; the app shows the dialog and hands the answer back.
    public let verification: SourceVerificationCoordinator?

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
        // The imported local books (upstream `BookHelp.downloadDir` sibling).
        let booksRoot = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("books", isDirectory: true)
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("books", isDirectory: true)
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
        let scriptEngine = ScriptEngineFactory.make(
            login: loginService,
            cookieStore: cookieStore,
            httpClient: httpClient,
            userAgent: settings.userAgent,
            sandboxDirectory: cacheRoot.path,
            verification: verification
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
            loginService: loginService
        )
        let model = LegadoAppModel(
            environment: environment,
            themeManager: themeManager,
            localImporter: localImporter,
            // The download progress is posted as a notification — upstream
            // `CacheBookService.sendNotification`.
            cacheManager: environment.makeCacheManager(
                storage: cacheStorage,
                notificationSink: NotificationService.shared
            ),
            verification: verification
        )
        // The rule scripts park on a background thread; the request has to
        // reach the UI on the main thread.
        verification.onRequest = { request in
            DispatchQueue.main.async {
                model.pendingVerification = request
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
        let result = await BookUpdater.update(
            book: book,
            source: nil,
            store: environment.store,
            dependencies: environment.dependencies()
        )
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
        let results = await BookUpdater.updateAll(
            books: books,
            store: environment.store,
            dependencies: environment.dependencies(),
            threadCount: environment.settings.threadCount
        )
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
            environment.localConfig.lastBackup = Date()
            reloadAll()
            errorMessage = nil
            backupMessage = "已恢复 \(summary.restoredRows) 条记录"
        } catch {
            errorMessage = error.localizedDescription
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
            guard let results = try? awaitSearch(source: source, keyword: name) else { continue }
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
    /// books (upstream `viewModel.upAllBookToc()`).
    private func finishStartup() {
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
        server.imageProvider = { [weak self] url in
            guard let self else { return nil }
            return await self.webServiceImage(url: url)
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
    private func webServiceContent(book: Book, chapter: BookChapter) async -> String? {
        // The cached content comes first — the upstream serves the cache too.
        if let cached = environment.cacheStorage?.content(book: book, chapter: chapter), !cached.isEmpty {
            return cached
        }
        guard let source = try? environment.source(for: book) else { return nil }
        let dependencies = environment.dependencies()
        return try? await WebBook.getContent(
            bookSource: source,
            book: book,
            bookChapter: chapter,
            dependencies: dependencies
        )
    }

    /// The bytes of an image for the local API — upstream
    /// `BookController.getCover` / `getImage`.
    private func webServiceImage(url: String) async -> Data? {
        guard let absolute = URL(string: url), absolute.scheme != nil else { return nil }
        let response = try? await environment.httpClient.send(HttpRequest(url: url, method: "GET"))
        return response?.data
    }
}
