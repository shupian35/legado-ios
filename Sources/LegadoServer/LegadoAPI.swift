import Foundation
import LegadoCore

/// The local book API — the port of `app/src/main/java/io/legado/app/web/HttpServer.kt`
/// and `api/controller/*` (BookController, BookSourceController, …).
///
/// ## Deliberate deviation: authentication
///
/// The Android server has **no authentication at all**: it binds to every
/// interface, reflects the `Origin` header for CORS and executes any `POST` it
/// receives (`web/HttpServer.kt:39-46`, `:134`). That means any web page the
/// user visits can read the whole bookshelf and rewrite book sources. The port
/// keeps the same routes and payloads but requires a bearer token, never
/// reflects an arbitrary origin, and can be bound to loopback only.
public struct LegadoAPIConfiguration: Equatable, Sendable {
    /// The token a client must present. `nil` disables authentication, which
    /// is only sensible when bound to loopback.
    public var token: String?
    /// The single origin allowed by CORS. `nil` disables CORS headers.
    public var allowedOrigin: String?
    /// `AppConfig.bookExportFileName`-style exports are not needed here, but
    /// the web UI asks for this to decide whether to show the proxy helpers.
    public var port: Int
    /// The bookshelf sort of the upstream `AppConfig.bookshelfSort`:
    /// 0 = the reading time, 1 = the latest chapter, 2 = the name, 3 = the
    /// order. It decides the order of `/getBookshelf`.
    public var bookshelfSort: Int

    public init(
        token: String? = nil,
        allowedOrigin: String? = nil,
        port: Int = 1122,
        bookshelfSort: Int = 0
    ) {
        self.token = token
        self.allowedOrigin = allowedOrigin
        self.port = port
        self.bookshelfSort = bookshelfSort
    }
}

/// The routes of the local API.
public enum LegadoAPI {

    /// The API surface: method, path and handler.
    public struct Route: Sendable {
        public let method: String
        public let path: String
        public let handler: @Sendable (HTTPRequestHead, LegadoAPIRequestContext) async -> HTTPResponseMessage

        public init(
            method: String,
            path: String,
            handler: @escaping @Sendable (HTTPRequestHead, LegadoAPIRequestContext) async -> HTTPResponseMessage
        ) {
            self.method = method
            self.path = path
            self.handler = handler
        }
    }

    /// Everything a handler needs.
    public final class LegadoAPIRequestContext: @unchecked Sendable {
        public let store: LegadoStore
        public let configuration: LegadoAPIConfiguration
        /// Loads the content of a chapter. The port has no global `WebBook`
        /// singleton, so the app injects this.
        public let contentProvider: (@Sendable (Book, BookChapter) async throws -> String?)?
        /// Reloads the table of contents of a book (upstream `refreshToc`).
        public let chapterListProvider: (@Sendable (BookSource, Book) async throws -> [BookChapter])?
        /// Returns the bytes of an image (the cover or a chapter image).
        public let imageProvider: (@Sendable (String) async throws -> Data?)?
        /// Stores a local book file and imports it.
        public let localBookImporter: (@Sendable (String, Data) async throws -> Bool)?

        public init(
            store: LegadoStore,
            configuration: LegadoAPIConfiguration,
            contentProvider: (@Sendable (Book, BookChapter) async throws -> String?)? = nil,
            chapterListProvider: (@Sendable (BookSource, Book) async throws -> [BookChapter])? = nil,
            imageProvider: (@Sendable (String) async throws -> Data?)? = nil,
            localBookImporter: (@Sendable (String, Data) async throws -> Bool)? = nil
        ) {
            self.store = store
            self.configuration = configuration
            self.contentProvider = contentProvider
            self.chapterListProvider = chapterListProvider
            self.imageProvider = imageProvider
            self.localBookImporter = localBookImporter
        }
    }

    // MARK: - Routes

    public static func routes() -> [Route] {
        [
            Route(method: "GET", path: "/getBookshelf") { request, context in
                await handle(request, context) { _ in
                    let books = try context.store.allBooks()
                    // Upstream `BookController.bookshelf`: an empty shelf is an
                    // error message, the books are sorted by the bookshelf
                    // sort of the settings.
                    guard !books.isEmpty else {
                        return .apiError("还没有添加小说")
                    }
                    let sorted = books.sorted { lhs, rhs in
                        switch context.configuration.bookshelfSort {
                        case 1: return lhs.latestChapterTime > rhs.latestChapterTime
                        case 2: return TextComparison.isOrderedBefore(lhs.name, rhs.name)
                        case 3: return lhs.order < rhs.order
                        default: return lhs.durChapterTime > rhs.durChapterTime
                        }
                    }
                    return .api(JSONValue.array(sorted.map(bookJSON)))
                }
            },
            Route(method: "GET", path: "/getChapterList") { request, context in
                await handle(request, context) { request in
                    guard let url = request.query("url"), !url.isEmpty else {
                        return .apiError("参数url不能为空，请指定书籍地址")
                    }
                    var chapters = try context.store.chapters(bookUrl: url)
                    if chapters.isEmpty, let provider = context.chapterListProvider,
                       let book = try context.store.book(url: url),
                       let source = try context.store.source(url: book.origin) {
                        // Upstream `BookController.getChapterList` refreshes
                        // the table of contents when it is empty.
                        chapters = (try? await provider(source, book)) ?? chapters
                    }
                    return .api(JSONValue.array(chapters.map(chapterJSON)))
                }
            },
            Route(method: "GET", path: "/getBookContent") { request, context in
                await handle(request, context) { request in
                    guard let url = request.query("url"), !url.isEmpty else {
                        return .apiError("参数url不能为空，请指定书籍地址")
                    }
                    guard let index = request.query("index").flatMap(Int64.init) else {
                        return .apiError("参数index不能为空, 请指定目录序号")
                    }
                    guard let book = try context.store.book(url: url) else {
                        return .apiError("未找到")
                    }
                    guard let chapter = try context.store.chapters(bookUrl: url)
                        .first(where: { $0.index == index }) else {
                        return .apiError("未找到")
                    }
                    guard let provider = context.contentProvider else {
                        return .apiError("未找到书源")
                    }
                    let content = try await provider(book, chapter) ?? ""
                    // Upstream returns the JSON-encoded string.
                    return .api(JSONValue.string(content))
                }
            },
            Route(method: "GET", path: "/getBookSources") { _, context in
                await handle(nil, context) { _ in
                    let sources = try context.store.allSources()
                    guard !sources.isEmpty else {
                        return .apiError("设备源列表为空")
                    }
                    return .api(JSONValue.array(sources.map(sourceJSON)))
                }
            },
            Route(method: "GET", path: "/getBookSource") { request, context in
                await handle(request, context) { request in
                    guard let url = request.query("url"), !url.isEmpty else {
                        return .apiError("参数url不能为空，请指定源地址")
                    }
                    guard let source = try context.store.source(url: url) else {
                        return .apiError("未找到源，请检查书源地址")
                    }
                    return .api(sourceJSON(source))
                }
            },
            Route(method: "POST", path: "/saveBookSource") { request, context in
                await handle(request, context) { request in
                    guard let source = try sourceFromBody(request.body) else {
                        return .apiError("转换源失败")
                    }
                    guard !source.bookSourceName.isEmpty, !source.bookSourceUrl.isEmpty else {
                        return .apiError("源名称和URL不能为空")
                    }
                    try context.store.insert(source)
                    return .api(JSONValue.string(""))
                }
            },
            Route(method: "POST", path: "/saveBookSources") { request, context in
                await handle(request, context) { request in
                    let sources = try sourcesFromBody(request.body)
                    guard !sources.isEmpty else { return .apiError("转换源失败") }
                    var saved: [BookSource] = []
                    for source in sources where !source.bookSourceName.isEmpty && !source.bookSourceUrl.isEmpty {
                        try context.store.insert(source)
                        saved.append(source)
                    }
                    return .api(JSONValue.array(saved.map(sourceJSON)))
                }
            },
            Route(method: "POST", path: "/deleteBookSources") { request, context in
                await handle(request, context) { request in
                    let urls = try urlsFromBody(request.body)
                    try context.store.deleteSources(urls: urls)
                    return .api(JSONValue.string("已执行"))
                }
            },
            Route(method: "POST", path: "/saveBook") { request, context in
                await handle(request, context) { request in
                    guard let book = try bookFromBody(request.body) else {
                        return .apiError("格式不对")
                    }
                    if try context.store.book(url: book.bookUrl) != nil {
                        try context.store.update(book)
                    } else {
                        try context.store.insert(book)
                    }
                    return .api(JSONValue.string(""))
                }
            },
            Route(method: "POST", path: "/deleteBook") { request, context in
                await handle(request, context) { request in
                    let urls = try urlsFromBody(request.body)
                    for url in urls { try context.store.delete(bookUrl: url) }
                    return .api(JSONValue.string(""))
                }
            },
            Route(method: "POST", path: "/saveBookProgress") { request, context in
                await handle(request, context) { request in
                    guard let progress = try progressFromBody(request.body) else {
                        return .apiError("格式不对")
                    }
                    guard var book = try context.store.allBooks()
                        .first(where: { $0.name == progress.name && $0.author == progress.author })
                    else {
                        return .apiError("格式不对")
                    }
                    book.durChapterIndex = Int64(progress.durChapterIndex)
                    book.durChapterPos = Int64(progress.durChapterPos)
                    book.durChapterTime = progress.durChapterTime
                    if let title = progress.durChapterTitle { book.durChapterTitle = title }
                    try context.store.updateProgress(book: book)
                    return .api(JSONValue.string(""))
                }
            },
            Route(method: "GET", path: "/getReplaceRules") { _, context in
                await handle(nil, context) { _ in
                    let rules = try context.store.allReplaceRules()
                    return .api(JSONValue.array(rules.map(replaceRuleJSON)))
                }
            }
        ] + extraRoutes()
    }

    // MARK: - Auth + wrapping

    /// Wraps a handler with authentication and error handling.
    static func handle(
        _ request: HTTPRequestHead?,
        _ context: LegadoAPIRequestContext,
        _ body: (HTTPRequestHead) async throws -> HTTPResponseMessage
    ) async -> HTTPResponseMessage {
        if let token = context.configuration.token, !token.isEmpty {
            let presented = request.flatMap { request -> String? in
                if let header = request.header("Authorization"), header.hasPrefix("Bearer ") {
                    return String(header.dropFirst("Bearer ".count))
                }
                return request.query("token")
            }
            guard presented == token else {
                return .error("unauthorized", code: 401)
            }
        }
        // The handlers below always have a request; the `nil` case only exists
        // because the GET routes without parameters do not need one.
        let request = request ?? HTTPRequestHead(method: "GET", target: "/")
        do {
            var response = try await body(request)
            if let origin = context.configuration.allowedOrigin {
                response.headers["Access-Control-Allow-Origin"] = origin
                response.headers["Vary"] = "Origin"
            }
            return response
        } catch {
            return .error(String(describing: error), code: 500)
        }
    }

    // MARK: - Decoding helpers

    static func sourceFromBody(_ body: Data) throws -> BookSource? {
        try sourcesFromBody(body).first
    }

    static func sourcesFromBody(_ body: Data) throws -> [BookSource] {
        let text = String(decoding: body, as: UTF8.self)
        guard !text.isEmpty else { return [] }
        let json = try JSONValue.parse(text)
        let items: [JSONValue]
        if case let .array(values) = json {
            items = values
        } else if case let .object(object) = json {
            if case let .array(values)? = object["bookSources"] {
                items = values
            } else {
                items = [json]
            }
        } else {
            return []
        }
        return items.compactMap { BookSourceJSON.decode($0) }
    }

    static func bookFromBody(_ body: Data) throws -> Book? {
        let json = try JSONValue.parse(String(decoding: body, as: UTF8.self))
        return BookJSON.decode(json)
    }

    static func urlsFromBody(_ body: Data) throws -> [String] {
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        if text.hasPrefix("[") {
            let json = try JSONValue.parse(text)
            if case let .array(values) = json {
                return values.compactMap {
                    if case let .string(value) = $0 { return value }
                    if case let .object(object) = $0, case let .string(url)? = object["bookSourceUrl"] ?? object["bookUrl"] {
                        return url
                    }
                    return nil
                }
            }
        }
        if text.hasPrefix("{") {
            let json = try JSONValue.parse(text)
            if case let .object(object) = json {
                if case let .string(url)? = object["bookSourceUrl"] ?? object["bookUrl"] ?? object["url"] {
                    return [url]
                }
                if case let .array(values)? = object["urls"] {
                    return values.compactMap { value in
                        if case let .string(url) = value { return url }
                        return nil
                    }
                }
            }
            return []
        }
        if text.hasPrefix("\"") {
            let json = try JSONValue.parse(text)
            if case let .string(url) = json { return [url] }
            return []
        }
        return text.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
    }

    /// Decodes a reading progress document leniently — the missing numbers
    /// default to zero instead of failing the whole request, which is what
    /// the web UI needs when it only knows the book and the chapter.
    static func progressFromBody(_ body: Data) throws -> BookProgress? {
        let text = String(decoding: body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let json = try JSONValue.parse(text)
        guard case let .object(object) = json else { return nil }
        guard let name = object["name"]?.textValue, let author = object["author"]?.textValue else {
            return nil
        }
        return BookProgress(
            name: name,
            author: author,
            durChapterIndex: Int(object["durChapterIndex"]?.intValue ?? 0),
            durChapterPos: Int(object["durChapterPos"]?.intValue ?? 0),
            durChapterTime: object["durChapterTime"]?.intValue ?? 0,
            durChapterTitle: object["durChapterTitle"]?.textValue
        )
    }

    // MARK: - Encoding helpers

    static func bookJSON(_ book: Book) -> JSONValue {
        var object: [String: JSONValue] = [:]
        object["bookUrl"] = .string(book.bookUrl)
        object["tocUrl"] = .string(book.tocUrl)
        object["origin"] = .string(book.origin)
        object["originName"] = .string(book.originName)
        object["name"] = .string(book.name)
        object["author"] = .string(book.author)
        object["kind"] = book.kind.map(JSONValue.string) ?? .null
        object["customTag"] = book.customTag.map(JSONValue.string) ?? .null
        object["coverUrl"] = book.coverUrl.map(JSONValue.string) ?? .null
        object["customCoverUrl"] = book.customCoverUrl.map(JSONValue.string) ?? .null
        object["intro"] = book.intro.map(JSONValue.string) ?? .null
        object["customIntro"] = book.customIntro.map(JSONValue.string) ?? .null
        object["charset"] = book.charset.map(JSONValue.string) ?? .null
        object["type"] = .number(Double(book.type))
        object["group"] = .number(Double(book.group))
        object["latestChapterTitle"] = book.latestChapterTitle.map(JSONValue.string) ?? .null
        object["latestChapterTime"] = .number(Double(book.latestChapterTime))
        object["lastCheckTime"] = .number(Double(book.lastCheckTime))
        object["lastCheckCount"] = .number(Double(book.lastCheckCount))
        object["totalChapterNum"] = .number(Double(book.totalChapterNum))
        object["durChapterTitle"] = book.durChapterTitle.map(JSONValue.string) ?? .null
        object["durChapterIndex"] = .number(Double(book.durChapterIndex))
        object["durChapterPos"] = .number(Double(book.durChapterPos))
        object["durChapterTime"] = .number(Double(book.durChapterTime))
        object["wordCount"] = book.wordCount.map(JSONValue.string) ?? .null
        object["canUpdate"] = .bool(book.canUpdate)
        object["order"] = .number(Double(book.order))
        object["originOrder"] = .number(Double(book.originOrder))
        object["variable"] = book.variable.map(JSONValue.string) ?? .null
        object["readConfig"] = book.readConfig.map(JSONValue.string) ?? .null
        object["syncTime"] = .number(Double(book.syncTime))
        object["infoHtml"] = book.infoHtml.map(JSONValue.string) ?? .null
        object["tocHtml"] = book.tocHtml.map(JSONValue.string) ?? .null
        return .object(object)
    }

    static func groupJSON(_ group: BookGroup) -> JSONValue {
        .object([
            "groupId": .number(Double(group.groupId)),
            "groupName": .string(group.groupName),
            "order": .number(Double(group.order)),
            "enableRefresh": .bool(group.enableRefresh),
            "show": .bool(group.show),
            "bookSort": .number(Double(group.bookSort))
        ])
    }

    static func chapterJSON(_ chapter: BookChapter) -> JSONValue {
        var object: [String: JSONValue] = [
            "url": .string(chapter.url),
            "title": .string(chapter.title),
            "isVolume": .bool(chapter.isVolume),
            "bookUrl": .string(chapter.bookUrl),
            "index": .number(Double(chapter.index))
        ]
        object["baseUrl"] = .string(chapter.baseUrl)
        object["isVip"] = .bool(chapter.isVip)
        object["isPay"] = .bool(chapter.isPay)
        if let wordCount = chapter.wordCount { object["wordCount"] = .string(wordCount) }
        return .object(object)
    }

    static func sourceJSON(_ source: BookSource) -> JSONValue {
        BookSourceJSON.encode(source)
    }

    static func replaceRuleJSON(_ rule: ReplaceRule) -> JSONValue {
        .object([
            "id": .number(Double(rule.id)),
            "name": .string(rule.name),
            "group": .string(rule.group ?? ""),
            "pattern": .string(rule.pattern),
            "replacement": .string(rule.replacement),
            "isRegex": .bool(rule.isRegex),
            "isEnabled": .bool(rule.isEnabled),
            "scope": rule.scope.map(JSONValue.string) ?? .null,
            "scopeTitle": .bool(rule.scopeTitle),
            "scopeContent": .bool(rule.scopeContent),
            "timeoutMillisecond": .number(Double(rule.timeoutMillisecond)),
            "sortOrder": .number(Double(rule.sortOrder)),
            "excludeScope": rule.excludeScope.map(JSONValue.string) ?? .null
        ])
    }
}

