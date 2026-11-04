//
//  AppEnvironment.swift
//  LegadoCore
//
//  The service layer of the application shell.
//
//  The SwiftUI views are deliberately thin: they call into this object, which
//  owns the store, the settings and the network stack. Everything here is
//  platform independent, so it can be unit tested on Linux.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/main/ (MainActivity, bookshelf, book info)
//  app/src/main/java/io/legado/app/help/ (BookHelp, AppConfig, SourceManager)
//

import Foundation

/// The services the application shell needs.
///
/// Upstream spreads these over `AppContext`, `AppConfig`, `BookHelp`,
/// `SourceManager` and a couple of singletons. The port keeps them together in
/// one injectable object so the UI can be exercised without a device.
public final class AppEnvironment {

    /// The database.
    public let store: LegadoStore
    /// The user settings.
    public let settings: AppSettings
    /// The device-local preferences (upstream `LocalConfig`) — the password
    /// that encrypts the sensitive parts of a backup stays here and is never
    /// written into the app preferences.
    public let localConfig: LocalConfig
    /// The JavaScript engine used by the rules.
    public let scriptEngine: RuleScriptEngine?
    /// The HTTP client.
    public let httpClient: HttpClient
    /// The cookie jar.
    public let cookieStore: CookieStore
    /// The download/cache queue.
    public let cacheManager: CacheBookManager?
    /// The on-disk cache of the downloaded chapters (upstream `BookHelp`).
    public let cacheStorage: BookCacheStorage?
    /// The login service of the sources (upstream `BaseSource` + the login dialog).
    public let loginService: SourceLoginService
    /// The reader background presets (upstream `ReadBookConfig`).
    public let backgroundManager: ReaderBackgroundManager

    public init(
        store: LegadoStore,
        settings: AppSettings,
        localConfig: LocalConfig? = nil,
        scriptEngine: RuleScriptEngine? = nil,
        httpClient: HttpClient = URLSessionHttpClient(),
        cookieStore: CookieStore = CookieStore(),
        cacheManager: CacheBookManager? = nil,
        cacheStorage: BookCacheStorage? = nil,
        backgroundManager: ReaderBackgroundManager = ReaderBackgroundManager(),
        loginService: SourceLoginService? = nil
    ) {
        self.store = store
        self.settings = settings
        self.localConfig = localConfig ?? LocalConfig(store: InMemorySettingsStore())
        self.scriptEngine = scriptEngine
        self.httpClient = httpClient
        self.cookieStore = cookieStore
        self.cacheManager = cacheManager
        self.cacheStorage = cacheStorage
        self.backgroundManager = backgroundManager
        self.loginService = loginService
            ?? SourceLoginService(
                store: store,
                cookieStore: cookieStore,
                scriptEngine: scriptEngine
            )
    }

    // MARK: - Dependencies

    /// Loads the chapters of a book from the store — the loader the cache
    /// queue needs (upstream `CacheBookModel` reads the chapter list from the
    /// database).
    final class StoreChapterLoader: @unchecked Sendable {
        private let store: LegadoStore

        init(store: LegadoStore) {
            self.store = store
        }

        func chapter(bookUrl: String, index: Int) throws -> BookChapter? {
            try store.chapters(bookUrl: bookUrl).first { Int($0.index) == index }
        }
    }

    /// Creates the download/cache queue (upstream `CacheBook`).
    ///
    /// The queue needs a chapter loader that reads the chapter list from the
    /// store, so it is created here instead of in the initialiser.
    public func makeCacheManager(storage: BookCacheStorage) -> CacheBookManager {
        let loader = StoreChapterLoader(store: store)
        return CacheBookManager(
            storage: storage,
            configuration: CacheBookManager.Configuration(
                threadCount: max(1, min(settings.threadCount, 16))
            ),
            chapterLoader: { bookUrl, index in
                try loader.chapter(bookUrl: bookUrl, index: index)
            }
        )
    }

    /// The dependency bundle handed to the rule engine.
    ///
    /// The user agent comes from the settings, so a change takes effect on the
    /// next request without restarting the app (upstream `AppConfig.userAgent`
    /// is read the same way).
    public func dependencies() -> AnalyzeUrlDependencies {
        AnalyzeUrlDependencies(
            httpClient: httpClient,
            cookieStore: cookieStore,
            scriptEngine: scriptEngine,
            userAgent: settings.userAgent
        )
    }

    // MARK: - Bookshelf

    /// The bookshelf model.
    public func bookshelf() -> BookshelfModel {
        BookshelfModel(store: store)
    }

    /// The books of a group, sorted the way the upstream bookshelf sorts them.
    public func books(inGroup groupId: Int64) throws -> [Book] {
        let sort = BookshelfSort(rawValue: settings.bookshelfSort) ?? .byDuration
        return try bookshelf().books(inGroup: groupId, sort: sort)
    }

    // MARK: - Sources

    /// All book sources.
    public func sources(enabledOnly: Bool = false) throws -> [BookSource] {
        enabledOnly ? try store.enabledSources() : try store.allSources()
    }

    /// The source a book came from.
    public func source(for book: Book) throws -> BookSource? {
        try store.source(url: book.origin)
    }

    /// Imports book sources from a JSON array (upstream `SourceManager.importBookSource`).
    ///
    /// - Returns: the number of imported sources.
    @discardableResult
    public func importSources(json: String) throws -> Int {
        let value = try JSONValue.parse(json)
        let array: [JSONValue]
        switch value {
        case .array(let items): array = items
        case .object: array = [value]
        default: throw AppEnvironmentError.notAnArray
        }
        var sources: [BookSource] = []
        for item in array {
            if let source = BookSourceJSONBridge.decode(item) { sources.append(source) }
        }
        guard !sources.isEmpty else { throw AppEnvironmentError.noValidSource }
        try store.insert(sources)
        return sources.count
    }

    /// Exports the book sources as a JSON array (upstream `SourceManager.exportBookSource`).
    public func exportSources(onlyEnabled: Bool = false) throws -> String {
        let sources = try sources(enabledOnly: onlyEnabled)
        let array = JSONValue.array(sources.map { BookSourceJSONBridge.encode($0) })
        return array.jsonString
    }

    // MARK: - Search and discovery

    /// Searches one source (upstream `WebBook.searchBook`).
    public func search(source: BookSource, keyword: String) async throws -> [SearchBook] {
        try await WebBook.searchBook(
            bookSource: source,
            key: keyword,
            dependencies: dependencies()
        )
    }

    /// Searches many sources at once — upstream `SearchModel.startSearch`.
    ///
    /// The sources are searched concurrently (upstream `mapParallelSafe`),
    /// the results are merged and the exact matches come first (upstream
    /// `SearchModel.mergeItems`).
    ///
    /// - Parameters:
    ///   - precision: only the books whose name or author contain the
    ///     keyword are kept (upstream `PreferKey.precisionSearch`).
    ///   - page: the page of the search (upstream `SearchModel.searchPage`).
    ///   - threadCount: how many sources are searched at the same time.
    public func search(
        sources: [BookSource],
        keyword: String,
        precision: Bool = false,
        page: Int = 1,
        threadCount: Int = 4
    ) async -> [SearchBook] {
        guard !sources.isEmpty, !keyword.isEmpty else { return [] }
        let limit = max(1, min(threadCount, 8))
        let dependencies = dependencies()
        var collected: [SearchBook] = []
        await withTaskGroup(of: [SearchBook].self) { group in
            var iterator = sources.makeIterator()
            for _ in 0..<limit {
                guard let source = iterator.next() else { break }
                group.addTask {
                    await Self.searchOne(
                        source: source,
                        keyword: keyword,
                        precision: precision,
                        page: page,
                        dependencies: dependencies
                    )
                }
            }
            while let result = await group.next() {
                collected.append(contentsOf: result)
                if let source = iterator.next() {
                    group.addTask {
                        await Self.searchOne(
                            source: source,
                            keyword: keyword,
                            precision: precision,
                            page: page,
                            dependencies: dependencies
                        )
                    }
                }
            }
        }
        return SearchResultMerge.merge(collected, keyword: keyword, precision: precision)
    }

    /// Searches one source of a multi-source search — upstream
    /// `SearchModel.startSearch` (`WebBook.searchBookAwait` with the filter).
    private static func searchOne(
        source: BookSource,
        keyword: String,
        precision: Bool,
        page: Int = 1,
        dependencies: AnalyzeUrlDependencies
    ) async -> [SearchBook] {
        do {
            return try await WebBook.searchBook(
                bookSource: source,
                key: keyword,
                page: page,
                filter: { name, author in
                    !precision || name.contains(keyword) || author.contains(keyword)
                },
                dependencies: dependencies
            )
        } catch {
            // Upstream `SearchModel.startSearch` catches the error of a
            // source and continues with the next one.
            return []
        }
    }

    /// Lists the categories of a source (upstream `WebBook.exploreBook`).
    ///
    /// The page is the upstream `ExploreShowViewModel.page` — it is put into
    /// the address by `AnalyzeUrl` (the `<page>` placeholder).
    public func explore(source: BookSource, url: String, page: Int = 1) async throws -> [SearchBook] {
        try await WebBook.exploreBook(
            bookSource: source,
            url: url,
            page: page,
            dependencies: dependencies()
        )
    }

    /// The explore categories of a source.
    ///
    /// Upstream `BookSource.exploreKinds()` reads the `exploreUrl` field: it is
    /// either a JSON array of `ExploreKind` objects (`{"title":…,"url":…}`) or
    /// a list of `分类::网址` pairs separated by `(&&|\n)+`.
    public func exploreCategories(source: BookSource) -> [ExploreCategory] {
        ExploreKinds.parse(source.exploreUrl).map {
            ExploreCategory(name: $0.title, url: $0.url ?? "")
        }
    }

    // MARK: - Books

    /// Loads the detail page of a book (upstream `WebBook.getBookInfo`).
    public func loadBookInfo(book: Book, source: BookSource) async throws -> Book {
        try await WebBook.getBookInfo(
            bookSource: source,
            book: book,
            dependencies: dependencies()
        )
    }

    /// Loads the chapter list of a book (upstream `WebBook.getChapterList`).
    public func loadChapterList(book: Book, source: BookSource) async throws -> ChapterListResult {
        try await WebBook.getChapterList(
            bookSource: source,
            book: book,
            dependencies: dependencies()
        )
    }

    /// Loads the text of one chapter (upstream `WebBook.getContent`).
    public func loadContent(book: Book, chapter: BookChapter, source: BookSource) async throws -> String {
        try await WebBook.getContent(
            bookSource: source,
            book: book,
            bookChapter: chapter,
            dependencies: dependencies()
        )
    }

    /// Puts a book on the shelf.
    ///
    /// Upstream `BookShelf`/`BookDao.insert` sets the group bit mask and
    /// clears the "not on shelf" flag.
    public func saveToShelf(_ book: Book, groupId: Int64? = nil) throws {
        var book = book
        book.type = book.type & ~BookType.notShelf
        if let groupId {
            book.group = book.group | groupId
        }
        try store.insert(book)
    }

    /// Removes a book from the shelf and deletes its chapters.
    public func deleteBook(_ book: Book) throws {
        try store.delete(bookUrl: book.bookUrl)
        try store.deleteChapters(bookUrl: book.bookUrl)
    }

    /// The chapters of a book.
    public func chapters(of book: Book) throws -> [BookChapter] {
        try store.chapters(bookUrl: book.bookUrl)
    }

    /// The batch change of the source — upstream
    /// `BookshelfManageViewModel.changeSource` (`BookshelfManageViewModel.kt:83-119`).
    ///
    /// For every book of the selection the local books and the books of that
    /// very source are skipped, the book is searched in the new source, the
    /// detail page is loaded when the chapter URL is missing, the chapter
    /// list is loaded and the reading progress is migrated onto the new book
    /// (`Book.migrateTo`). The books are separated by `delaySeconds`
    /// (`AppConfig.batchChangeSourceDelay`).
    ///
    /// The progress closure receives the index of the book (1-based) and the
    /// number of the books — the upstream posts it as "${index + 1} / ${size}".
    @discardableResult
    public func batchChangeSource(
        books: [Book],
        source: BookSource,
        delaySeconds: Int = 0,
        progress: ((Int, Int) -> Void)? = nil
    ) async -> Int {
        var changed = 0
        let total = books.count
        for (index, book) in books.enumerated() {
            progress?(index + 1, total)
            if BookType.contains(book.type, BookType.local) { continue }
            if book.origin == source.bookSourceUrl { continue }
            guard var newBook = try? await WebBook.preciseSearch(
                bookSource: source,
                name: book.name,
                author: book.author,
                dependencies: dependencies()
            ) else { continue }
            if newBook.tocUrl.isEmpty {
                guard let info = try? await loadBookInfo(book: newBook, source: source) else {
                    continue
                }
                newBook = info
            }
            guard let result = try? await loadChapterList(book: newBook, source: source) else {
                continue
            }
            let toc = result.chapters
            let rules = (try? store.replaceRulesForTitle(
                name: newBook.name,
                origin: newBook.origin
            )) ?? nil
            let migrated = ChangeSourceService.switchSource(
                oldBook: book,
                newBook: newBook,
                toc: toc,
                replaceRules: rules
            )
            try? store.insert(migrated)
            try? store.insert(toc)
            changed += 1
            if delaySeconds > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            }
        }
        return changed
    }

    // MARK: - RSS

    /// The RSS sources.
    public func rssSources() throws -> [RssSource] {
        try store.allRssSources()
    }

    /// Loads the articles of an RSS source (upstream `Rss.getArticles`).
    ///
    /// Upstream returns the articles *and* the URL of the next page
    /// (`Rss.getArticlesAwait` returns a `Pair`); the port keeps both in
    /// `RssArticlePage`.
    public func rssArticles(source: RssSource, page: Int = 1) async throws -> RssArticlePage {
        try await rssArticles(source: source, sort: nil, page: page, url: nil)
    }

    /// Loads the articles of one sort of an RSS source — upstream
    /// `Rss.getArticles(sortName, sortUrl, rssSource, page)`.
    public func rssArticles(source: RssSource, sort: RssSort, page: Int = 1) async throws -> RssArticlePage {
        try await rssArticles(source: source, sort: sort, page: page, url: nil)
    }

    /// Loads one page of the articles of an RSS source.
    ///
    /// - Parameters:
    ///   - sort: the sort the articles belong to — `nil` uses the source.
    ///   - page: the page number (upstream `RssArticlesViewModel.page`).
    ///   - url: the URL of the page; the "load more" button passes the URL
    ///     the previous page returned (upstream
    ///     `RssArticlesViewModel.loadMore`).
    public func rssArticles(
        source: RssSource,
        sort: RssSort?,
        page: Int,
        url: String?
    ) async throws -> RssArticlePage {
        let sortName = sort?.name ?? source.sourceName
        let sortUrl = url ?? sort?.url ?? source.sortUrl ?? source.sourceUrl
        return try await Rss.articles(
            sortName: sortName,
            sortUrl: sortUrl,
            rssSource: source,
            page: page,
            dependencies: dependencies(),
            scriptEngine: scriptEngine
        )
    }

    /// Loads the full text of an article (upstream `Rss.content`).
    public func rssContent(article: RssArticle, source: RssSource) async throws -> String {
        try await Rss.content(
            article: article,
            ruleContent: source.ruleContent ?? "",
            rssSource: source,
            dependencies: dependencies(),
            scriptEngine: scriptEngine
        )
    }

    /// Imports the RSS sources of a JSON document — upstream
    /// `ImportRssSourceViewModel.importSourceAwait`.
    ///
    /// - Returns: the number of imported sources.
    @discardableResult
    public func importRssSources(json: String) throws -> Int {
        let sources = try RssSourceImport.sources(json: json)
        for source in sources {
            try store.insert(source)
        }
        return sources.count
    }

    /// Imports the RSS sources of a URL — upstream
    /// `ImportRssSourceViewModel.importSourceUrl`.
    ///
    /// A document with a `sourceUrls` member is followed: every URL is
    /// downloaded and imported.
    @discardableResult
    public func importRssSources(url: String) async throws -> Int {
        let body = try await download(url: url)
        let urls = (try? RssSourceImport.sourceURLs(json: body)) ?? []
        if !urls.isEmpty {
            var count = 0
            for sourceURL in urls {
                count += try await importRssSources(url: sourceURL)
            }
            return count
        }
        return try importRssSources(json: body)
    }

    /// The preview of an RSS source import — upstream
    /// `ImportRssSourceViewModel.comparisonSource`.
    ///
    /// Every imported source is compared with the local ones: a source that
    /// is not on the device is "新增", a source that is newer than the local
    /// one is "更新" and the others are "已有".
    public func rssImportPreview(_ sources: [RssSource]) throws -> [RssSourceImport.Item] {
        RssSourceImport.items(sources, local: try store.allRssSources())
    }

    /// The RSS sources of an import document — upstream
    /// `ImportRssSourceViewModel.importSourceAwait`.
    ///
    /// The document holds the sources themselves or a list of urls
    /// (`sourceUrls`); every url of the list is downloaded and imported.
    public func rssSourcesOfImport(json: String) async throws -> [RssSource] {
        let urls = (try? RssSourceImport.sourceURLs(json: json)) ?? []
        if !urls.isEmpty {
            var sources: [RssSource] = []
            for url in urls {
                sources += try await rssSourcesOfImport(url: url)
            }
            return sources
        }
        return try RssSourceImport.sources(json: json)
    }

    /// The RSS sources of an import url — upstream
    /// `ImportRssSourceViewModel.importSourceUrl`.
    public func rssSourcesOfImport(url: String) async throws -> [RssSource] {
        let body = try await download(url: url)
        return try await rssSourcesOfImport(json: body)
    }

    /// Inserts the RSS sources — upstream `SourceHelp.insertRssSource`.
    ///
    /// - Returns: the number of inserted sources.
    @discardableResult
    public func insertRssSources(_ sources: [RssSource]) throws -> Int {
        for source in sources {
            try store.insert(source)
        }
        return sources.count
    }

    /// Exports the RSS sources as a JSON array — upstream
    /// `RssSourceViewModel.saveToFile`.
    public func exportRssSources(onlyEnabled: Bool = false) throws -> String {
        var sources = try store.allRssSources()
        if onlyEnabled {
            sources = sources.filter { $0.enabled }
        }
        return JSONValue.array(sources.map { RssSourceJSONBridge.encode($0) }).jsonString
    }

    /// Downloads a text document.
    private func download(url: String) async throws -> String {
        let response = try await httpClient.send(HttpRequest(url: url))
        guard let body = response.body, !body.isEmpty else {
            throw AppEnvironmentError.emptyResponse
        }
        return body
    }

    // MARK: - Errors
}

/// Errors of the service layer.
public enum AppEnvironmentError: Error, Equatable {
    case notAnArray
    case noValidSource
    case bookNotFound(String)
    case sourceNotFound(String)
    case emptyResponse
}

// MARK: - JSON bridge for the book sources

/// Converts book sources to and from JSON.
///
/// Upstream `BookSource` is a Room entity with `@Parcelize`; the rule fields
/// are plain strings that hold JSON, so the conversion is a flat mapping.
public enum BookSourceJSONBridge {

    /// Decodes a book source from a JSON object.
    public static func decode(_ value: JSONValue) -> BookSource? {
        guard case .object(let object) = value else { return nil }
        guard let url = object["bookSourceUrl"]?.textValue, !url.isEmpty else { return nil }
        var source = BookSource(bookSourceUrl: url)
        source.bookSourceName = object["bookSourceName"]?.textValue ?? ""
        source.bookSourceGroup = object["bookSourceGroup"]?.textValue
        source.bookSourceType = object["bookSourceType"]?.intValue ?? BookSourceType.default
        source.bookUrlPattern = object["bookUrlPattern"]?.textValue
        source.customOrder = object["customOrder"]?.intValue ?? 0
        source.enabled = object["enabled"]?.boolValue ?? true
        source.enabledExplore = object["enabledExplore"]?.boolValue ?? true
        source.jsLib = object["jsLib"]?.textValue
        source.enabledCookieJar = object["enabledCookieJar"]?.boolValue ?? false
        source.concurrentRate = object["concurrentRate"]?.textValue
        source.header = object["header"]?.textValue
        source.loginUrl = object["loginUrl"]?.textValue
        source.loginUi = object["loginUi"]?.textValue
        source.loginCheckJs = object["loginCheckJs"]?.textValue
        source.coverDecodeJs = object["coverDecodeJs"]?.textValue
        source.bookSourceComment = object["bookSourceComment"]?.textValue
        source.variableComment = object["variableComment"]?.textValue
        source.lastUpdateTime = object["lastUpdateTime"]?.intValue ?? 0
        source.respondTime = object["respondTime"]?.intValue ?? 180_000
        source.weight = object["weight"]?.intValue ?? 0
        source.exploreUrl = object["exploreUrl"]?.textValue
        source.exploreScreen = object["exploreScreen"]?.textValue
        source.ruleExplore = object["ruleExplore"]?.textValue
        source.searchUrl = object["searchUrl"]?.textValue
        source.ruleSearch = object["ruleSearch"]?.textValue
        source.ruleBookInfo = object["ruleBookInfo"]?.textValue
        source.ruleToc = object["ruleToc"]?.textValue
        source.ruleContent = object["ruleContent"]?.textValue
        source.ruleReview = object["ruleReview"]?.textValue
        return source
    }

    /// Encodes a book source as a JSON object.
    public static func encode(_ source: BookSource) -> JSONValue {
        var object: [String: JSONValue] = [:]
        object["bookSourceUrl"] = .string(source.bookSourceUrl)
        object["bookSourceName"] = .string(source.bookSourceName)
        if let group = source.bookSourceGroup { object["bookSourceGroup"] = .string(group) }
        object["bookSourceType"] = .number(Double(source.bookSourceType))
        if let pattern = source.bookUrlPattern { object["bookUrlPattern"] = .string(pattern) }
        object["customOrder"] = .number(Double(source.customOrder))
        object["enabled"] = .bool(source.enabled)
        object["enabledExplore"] = .bool(source.enabledExplore)
        if let jsLib = source.jsLib { object["jsLib"] = .string(jsLib) }
        object["enabledCookieJar"] = .bool(source.enabledCookieJar)
        if let rate = source.concurrentRate { object["concurrentRate"] = .string(rate) }
        if let header = source.header { object["header"] = .string(header) }
        if let loginUrl = source.loginUrl { object["loginUrl"] = .string(loginUrl) }
        if let loginUi = source.loginUi { object["loginUi"] = .string(loginUi) }
        if let loginCheckJs = source.loginCheckJs { object["loginCheckJs"] = .string(loginCheckJs) }
        if let coverDecodeJs = source.coverDecodeJs { object["coverDecodeJs"] = .string(coverDecodeJs) }
        if let comment = source.bookSourceComment { object["bookSourceComment"] = .string(comment) }
        if let comment = source.variableComment { object["variableComment"] = .string(comment) }
        object["lastUpdateTime"] = .number(Double(source.lastUpdateTime))
        object["respondTime"] = .number(Double(source.respondTime))
        object["weight"] = .number(Double(source.weight))
        if let exploreUrl = source.exploreUrl { object["exploreUrl"] = .string(exploreUrl) }
        if let exploreScreen = source.exploreScreen { object["exploreScreen"] = .string(exploreScreen) }
        if let rule = source.ruleExplore { object["ruleExplore"] = .string(rule) }
        if let url = source.searchUrl { object["searchUrl"] = .string(url) }
        if let rule = source.ruleSearch { object["ruleSearch"] = .string(rule) }
        if let rule = source.ruleBookInfo { object["ruleBookInfo"] = .string(rule) }
        if let rule = source.ruleToc { object["ruleToc"] = .string(rule) }
        if let rule = source.ruleContent { object["ruleContent"] = .string(rule) }
        if let rule = source.ruleReview { object["ruleReview"] = .string(rule) }
        return .object(object)
    }
}
