import Foundation
import LegadoCore

/// What a WebSocket endpoint sends back to the client.
public enum LegadoWebSocketOutgoing: Equatable, Sendable {
    /// A text frame.
    case text(String)
    /// A ping frame — upstream `BookSearchWebSocket.onOpen` pings every 30 s.
    case ping
    /// The close frame; the connection ends afterwards.
    case close
}

/// The handler of a WebSocket endpoint.
///
/// The handler receives the path of the endpoint, the message of the client
/// and a `send` closure it can call as often as it likes. The upstream debug
/// sockets stream one log line per message, so a single reply is not enough.
public typealias LegadoWebSocketHandler = @Sendable (
    _ path: String,
    _ message: String,
    _ send: @escaping @Sendable (LegadoWebSocketOutgoing) -> Void
) async -> Void

/// The mutable state of a WebSocket session (the close flag).
final class WebSocketSessionState: @unchecked Sendable {
    var isClosed = false
    /// Set when the session ends for any reason (the heartbeat stops).
    var isFinished = false
}

/// The three WebSocket endpoints of the upstream web service —
/// `web/WebSocketServer.kt`.
public enum LegadoWebSocketEndpoint: String, CaseIterable, Sendable {
    /// Debugs a book source.
    case bookSourceDebug = "/bookSourceDebug"
    /// Debugs an RSS source.
    case rssSourceDebug = "/rssSourceDebug"
    /// Searches the books of every enabled source.
    case searchBook = "/searchBook"

    /// The endpoint of a path.
    public static func endpoint(forPath path: String) -> LegadoWebSocketEndpoint? {
        LegadoWebSocketEndpoint(rawValue: path)
    }
}

/// The WebSocket service — the port of `web/socket/*`.
///
/// The protocol is the upstream one:
///
/// * `/bookSourceDebug` — the client sends `{"tag": "<sourceUrl>", "key": "<keyword>"}`;
///   the debug output is streamed back as text frames.
/// * `/rssSourceDebug` — the same with an RSS source.
/// * `/searchBook` — the client sends `{"key": "<keyword>"}`; the results of
///   every source are sent as they finish (one JSON array per source) and the
///   session is closed.
public final class LegadoWebSocketService: @unchecked Sendable {

    /// The message upstream sends when the payload is not JSON.
    public static let notJsonMessage = "数据必须为Json格式"
    /// The message upstream sends when a field is missing.
    public static let cannotBeEmptyMessage = "不能为空"
    /// The close reason of the debug sessions.
    public static let debugFinishReason = "调试结束"
    /// The close reason of the search sessions.
    public static let searchFinishReason = "Search finish"

    private let store: LegadoStore
    private let dependencies: AnalyzeUrlDependencies
    private let scriptEngine: RuleScriptEngine?

    /// Creates the service.
    public init(
        store: LegadoStore,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies(),
        scriptEngine: RuleScriptEngine? = nil
    ) {
        self.store = store
        self.dependencies = dependencies
        self.scriptEngine = scriptEngine
    }

    /// The handler to hand to `LegadoServer`.
    public func makeHandler() -> LegadoWebSocketHandler {
        { [weak self] path, message, send in
            guard let self else { return }
            await self.handle(path: path, message: message, send: send)
        }
    }

    /// Handles one message.
    public func handle(
        path: String,
        message: String,
        send: @escaping @Sendable (LegadoWebSocketOutgoing) -> Void
    ) async {
        guard let endpoint = LegadoWebSocketEndpoint.endpoint(forPath: path) else {
            send(.close)
            return
        }
        switch endpoint {
        case .bookSourceDebug:
            await handleBookSourceDebug(message: message, send: send)
        case .rssSourceDebug:
            await handleRssSourceDebug(message: message, send: send)
        case .searchBook:
            await handleSearch(message: message, send: send)
        }
    }

    // MARK: - The book source debug

    private func handleBookSourceDebug(
        message: String,
        send: @escaping @Sendable (LegadoWebSocketOutgoing) -> Void
    ) async {
        guard let payload = Self.parsePayload(message) else {
            send(.text(Self.notJsonMessage))
            send(.close)
            return
        }
        guard let tag = payload["tag"], !tag.isEmpty,
              let key = payload["key"], !key.isEmpty else {
            send(.text(Self.cannotBeEmptyMessage))
            send(.close)
            return
        }
        guard let source = try? store.source(url: tag) else {
            // Upstream: `appDb.bookSourceDao.getBookSource(tag)?.let { … }` — when
            // the source does not exist nothing happens and the socket stays open.
            return
        }
        let debugger = SourceDebugger()
        debugger.sink = ClosureDebugSink { state, text in
            guard !debugNotPrintedStates.contains(state) else { return }
            send(.text(text))
        }
        _ = await debugger.debugBookSource(source, key: key, dependencies: dependencies)
        send(.close)
    }

    // MARK: - The RSS source debug

    private func handleRssSourceDebug(
        message: String,
        send: @escaping @Sendable (LegadoWebSocketOutgoing) -> Void
    ) async {
        guard let payload = Self.parsePayload(message) else {
            send(.text(Self.notJsonMessage))
            send(.close)
            return
        }
        guard let tag = payload["tag"], !tag.isEmpty else {
            send(.text(Self.cannotBeEmptyMessage))
            send(.close)
            return
        }
        guard let source = try? store.allRssSources().first(where: { $0.sourceUrl == tag }) else {
            // Upstream behaves the same way when the source does not exist.
            return
        }
        let debugger = SourceDebugger()
        debugger.sink = ClosureDebugSink { state, text in
            guard !debugNotPrintedStates.contains(state) else { return }
            send(.text(text))
        }
        _ = await debugger.debugRssSource(
            source,
            dependencies: dependencies,
            scriptEngine: scriptEngine
        )
        send(.close)
    }

    // MARK: - The book search

    private func handleSearch(
        message: String,
        send: @escaping @Sendable (LegadoWebSocketOutgoing) -> Void
    ) async {
        guard let payload = Self.parsePayload(message) else {
            send(.text(Self.notJsonMessage))
            send(.close)
            return
        }
        guard let key = payload["key"], !key.isEmpty else {
            send(.text(Self.cannotBeEmptyMessage))
            send(.close)
            return
        }
        let sources = (try? store.enabledSources()) ?? []
        for source in sources {
            guard let books = try? await WebBook.searchBook(
                bookSource: source,
                key: key,
                dependencies: dependencies
            ) else {
                continue
            }
            // Upstream `BookSearchWebSocket.onSearchSuccess` sends the results
            // of every source as they finish:
            // `send(GSON.toJson(searchBooks))`.
            send(.text(SearchBookJSON.encode(books)))
        }
        send(.close)
    }

    // MARK: - Helpers

    /// Parses the JSON payload of a client message.
    ///
    /// Upstream expects a JSON object of strings; a malformed payload makes
    /// the socket answer "数据必须为Json格式".
    static func parsePayload(_ message: String) -> [String: String]? {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return nil }
        guard let value = try? JSONValue.parse(trimmed) else { return nil }
        guard case .object(let fields) = value else { return nil }
        var result: [String: String] = [:]
        for (key, item) in fields {
            switch item {
            case .string(let text): result[key] = text
            case .number(let number): result[key] = String(number)
            case .bool(let flag): result[key] = flag ? "true" : "false"
            default: result[key] = ""
            }
        }
        return result
    }
}

/// The JSON encoding of the search results — upstream `GSON.toJson(searchBooks)`.
public enum SearchBookJSON {

    /// Encodes the search results.
    public static func encode(_ books: [SearchBook]) -> String {
        let items = books.map { book -> JSONValue in
            .object([
                "name": .string(book.name),
                "author": .string(book.author),
                "kind": .string(book.kind ?? ""),
                "intro": .string(book.intro ?? ""),
                "lastChapter": .string(book.latestChapterTitle ?? ""),
                "bookUrl": .string(book.bookUrl),
                "coverUrl": .string(book.coverUrl ?? ""),
                "origin": .string(book.origin),
                "originName": .string(book.originName),
                "wordCount": .string(book.wordCount ?? ""),
                "updateTime": .number(Double(book.time)),
                "bookInfoHtml": .string(book.infoHtml ?? ""),
                "tocHtml": .string(book.tocHtml ?? "")
            ])
        }
        return JSONValue.array(items).jsonString
    }
}
