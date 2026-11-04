//
//  DeepLinkActions.swift
//  LegadoCore
//
//  The deep links that do not import a JSON document — upstream
//  `OnLineImportActivity.kt:74-101`:
//
//  * `/theme`          → the theme of the reader (`ImportThemeDialog`)
//  * `/readConfig`     → the reader style archive `readConfig.zip`
//                        (`OnLineImportViewModel.importReadConfig`)
//  * `/addToBookshelf` → a book is added to the bookshelf
//                        (`AddToBookshelfDialog`)
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/association/OnLineImportActivity.kt
//  app/src/main/java/io/legado/app/ui/association/OnLineImportViewModel.kt
//  app/src/main/java/io/legado/app/ui/association/AddToBookshelfDialog.kt
//

import Foundation

// MARK: - The action of a link

/// What a deep link does.
public enum DeepLinkAction: Equatable, Sendable {
    /// The link imports a JSON document of the given kind.
    case importJSON(ImportKind)
    /// The link imports a theme.
    case importTheme
    /// The link imports a reader style archive (`readConfig.zip`).
    case importReadConfig
    /// The link adds a book to the bookshelf.
    case addToBookshelf
}

/// The errors of the deep link imports.
public enum DeepLinkActionError: Error, Equatable {
    /// The book is already on the shelf — upstream "X 已在书架".
    case alreadyOnShelf(String)
    /// The book url cannot be used — upstream "书籍地址格式不对".
    case malformedBookUrl
    /// No source matched the book url — upstream "未找到匹配书源".
    case noMatchingSource
    /// The theme document cannot be read.
    case invalidTheme
    /// The archive cannot be read.
    case invalidReadConfig
}

// MARK: - The service

/// The deep links that do not import a JSON document.
public enum DeepLinkService {

    /// The action of a link path — upstream `OnLineImportActivity.importOnLine`.
    ///
    /// The `/importonline` path with the hosts `booksource`, `rsssource` and
    /// `replace` selects a JSON import; every other host falls back to the
    /// detection of the JSON keys.
    public static func action(forPath path: String, host: String?) -> DeepLinkAction? {
        switch path {
        case "/bookSource": return .importJSON(.bookSource)
        case "/rssSource": return .importJSON(.rssSource)
        case "/replaceRule": return .importJSON(.replaceRule)
        case "/textTocRule": return .importJSON(.txtRule)
        case "/httpTTS": return .importJSON(.httpTts)
        case "/dictRule": return .importJSON(.dictRule)
        case "/theme": return .importTheme
        case "/readConfig": return .importReadConfig
        case "/addToBookshelf": return .addToBookshelf
        default: break
        }
        if path == "/importonline" || path == "/" {
            switch host {
            case "booksource": return .importJSON(.bookSource)
            case "rsssource": return .importJSON(.rssSource)
            case "replace": return .importJSON(.replaceRule)
            default: return nil
            }
        }
        return nil
    }

    // MARK: - The download

    /// Downloads the data of a link.
    ///
    /// The upstream sends the literal user agent `null` when the link ends
    /// with `#requestWithoutUA` (`OnLineImportViewModel.getText`).
    public static func download(
        from request: DeepLinkRequest,
        httpClient: HttpClient,
        userAgent: String = AppSettings.defaultUserAgent
    ) async throws -> Data {
        var url = request.source
        var headers: [String: String] = [:]
        if url.hasSuffix(DeepLink.requestWithoutUserAgent) {
            url = String(url.dropLast(DeepLink.requestWithoutUserAgent.count))
            headers["User-Agent"] = "null"
        } else {
            headers["User-Agent"] = userAgent
        }
        let response = try await httpClient.send(HttpRequest(url: url, headers: headers))
        guard response.isSuccessful else {
            throw DeepLinkError.downloadFailed("HTTP \(response.code)")
        }
        if let data = response.data {
            return data
        }
        guard let body = response.body else {
            throw DeepLinkError.downloadFailed("空的响应")
        }
        return Data(body.utf8)
    }

    // MARK: - The theme

    /// Imports a theme — upstream `ImportThemeDialog`.
    ///
    /// The upstream shows a preview of the theme before it is added; the port
    /// returns the theme, so the caller can ask the user first.
    public static func importTheme(
        from request: DeepLinkRequest,
        httpClient: HttpClient,
        userAgent: String = AppSettings.defaultUserAgent
    ) async throws -> AppTheme {
        let data = try await download(from: request, httpClient: httpClient, userAgent: userAgent)
        let text = String(decoding: data, as: UTF8.self)
        guard let theme = ThemeManager.importJSON(text) else {
            throw DeepLinkActionError.invalidTheme
        }
        return theme
    }

    // MARK: - The reader style

    /// Imports the reader style archive — upstream
    /// `OnLineImportViewModel.importReadConfig`.
    public static func importReadConfig(
        from request: DeepLinkRequest,
        httpClient: HttpClient,
        userAgent: String = AppSettings.defaultUserAgent
    ) async throws -> ReaderConfigArchive.Payload {
        let data = try await download(from: request, httpClient: httpClient, userAgent: userAgent)
        do {
            return try ReaderConfigArchive.read(data)
        } catch {
            throw DeepLinkActionError.invalidReadConfig
        }
    }

    // MARK: - The bookshelf

    /// The result of the "add to the bookshelf" link.
    public struct AddToBookshelfResult: Equatable, Sendable {
        /// The book that was found.
        public var book: Book
        /// The source the book belongs to.
        public var source: BookSource

        public init(book: Book, source: BookSource) {
            self.book = book
            self.source = source
        }
    }

    /// Adds a book to the bookshelf — upstream `AddToBookshelfDialog`.
    ///
    /// The upstream tries the sources in this order:
    ///
    /// 1. the source of the `UrlOption` embedded in the url
    ///    (`bookSourceUrl`),
    /// 2. the enabled source whose `bookSourceUrl` is the base url of the book
    ///    url,
    /// 3. every enabled source whose `bookUrlPattern` matches the book url.
    ///
    /// The book is written to the search books (upstream `saveSearchBook`), the
    /// user adds it to the shelf in the book information.
    public static func addToBookshelf(
        bookUrl: String,
        store: LegadoStore,
        sources: [BookSource],
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async throws -> AddToBookshelfResult {
        if let existing = try store.book(url: bookUrl) {
            throw DeepLinkActionError.alreadyOnShelf(existing.name)
        }
        guard let baseUrl = NetworkUtils.baseUrl(bookUrl) else {
            throw DeepLinkActionError.malformedBookUrl
        }
        let enabled = sources.filter { $0.enabled }

        // 1. The source of the option block of the url.
        if let origin = AnalyzeUrl.option(of: bookUrl)?.origin,
           let source = enabled.first(where: { $0.bookSourceUrl == origin }),
           let result = await bookInfo(bookUrl: bookUrl, source: source, dependencies: dependencies) {
            return result
        }

        // 2. The source whose url is the base url of the book url.
        if let source = enabled.first(where: { $0.bookSourceUrl == baseUrl }),
           let result = await bookInfo(bookUrl: bookUrl, source: source, dependencies: dependencies) {
            return result
        }

        // 3. The sources with a `bookUrlPattern` that matches the url.
        for source in enabled {
            guard let pattern = source.bookUrlPattern else { continue }
            let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "NONE" else { continue }
            guard bookUrl.matches(trimmed) else { continue }
            if let result = await bookInfo(bookUrl: bookUrl, source: source, dependencies: dependencies) {
                return result
            }
        }
        throw DeepLinkActionError.noMatchingSource
    }

    /// Reads the information of the book — upstream
    /// `AddToBookshelfDialog.getBookInfo`.
    private static func bookInfo(
        bookUrl: String,
        source: BookSource,
        dependencies: AnalyzeUrlDependencies
    ) async -> AddToBookshelfResult? {
        let book = Book(
            bookUrl: bookUrl,
            origin: source.bookSourceUrl,
            originName: source.bookSourceName
        )
        guard let parsed = try? await WebBook.getBookInfo(
            bookSource: source,
            book: book,
            dependencies: dependencies
        ) else {
            return nil
        }
        return AddToBookshelfResult(book: parsed, source: source)
    }
}
