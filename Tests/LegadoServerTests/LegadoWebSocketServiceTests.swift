import XCTest
@testable import LegadoServer
import LegadoCore

/// An `HttpClient` that answers from a closure.
final class WebSocketStubHttpClient: HttpClient, @unchecked Sendable {
    private let handler: @Sendable (HttpRequest) -> HttpResponse

    init(handler: @escaping @Sendable (HttpRequest) -> HttpResponse) {
        self.handler = handler
    }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        handler(request)
    }
}

/// The tests of the three WebSocket endpoints — the port of `web/socket/*`.
final class LegadoWebSocketServiceTests: XCTestCase {

    private var store: LegadoStore!

    override func setUp() {
        super.setUp()
        store = LegadoStore(tables: MemoryTableStore())
        try? store.createSchema()
    }

    override func tearDown() {
        store = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeService(
        body: @escaping @Sendable (HttpRequest) -> String
    ) -> LegadoWebSocketService {
        let client = WebSocketStubHttpClient { request in
            HttpResponse(url: request.url, body: body(request))
        }
        return LegadoWebSocketService(
            store: store,
            dependencies: AnalyzeUrlDependencies(httpClient: client)
        )
    }

    private func collect(
        _ service: LegadoWebSocketService,
        path: String,
        message: String
    ) async -> [LegadoWebSocketOutgoing] {
        let box = OutgoingBox()
        await service.handle(path: path, message: message) { outgoing in
            box.append(outgoing)
        }
        return box.items
    }

    final class OutgoingBox: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [LegadoWebSocketOutgoing] = []

        func append(_ outgoing: LegadoWebSocketOutgoing) {
            lock.lock()
            storage.append(outgoing)
            lock.unlock()
        }

        var items: [LegadoWebSocketOutgoing] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    private func texts(_ outgoing: [LegadoWebSocketOutgoing]) -> [String] {
        outgoing.compactMap {
            if case .text(let value) = $0 { return value }
            return nil
        }
    }

    // MARK: - The tests

    func testAPayloadThatIsNotJsonIsRejected() async {
        let service = makeService { _ in "" }
        let outgoing = await collect(service, path: "/bookSourceDebug", message: "not json")
        XCTAssertEqual(texts(outgoing), [LegadoWebSocketService.notJsonMessage])
        XCTAssertTrue(outgoing.contains(.close))
    }

    func testAnEmptyTagIsRejected() async {
        let service = makeService { _ in "" }
        let outgoing = await collect(service, path: "/bookSourceDebug", message: "{\"tag\":\"\",\"key\":\"k\"}")
        XCTAssertEqual(texts(outgoing), [LegadoWebSocketService.cannotBeEmptyMessage])
        XCTAssertTrue(outgoing.contains(.close))
    }

    func testAnUnknownPathClosesTheSession() async {
        let service = makeService { _ in "" }
        let outgoing = await collect(service, path: "/nope", message: "{}")
        XCTAssertEqual(outgoing, [.close])
    }

    func testTheBookSourceDebugStreamsTheLogLines() async throws {
        var source = BookSource(bookSourceUrl: "https://source.example", bookSourceName: "Source")
        source.searchUrl = "https://source.example/search?key={{key}}"
        source.ruleSearch = "{\"bookList\":\"div.item\",\"name\":\"a.name@text\",\"bookUrl\":\"a@href\"}"
        try store.insert(source)

        let service = makeService { request in
            if request.url.contains("/search") {
                return "<div class=\"item\"><a class=\"name\" href=\"/book/1\">书名</a></div>"
            }
            return "<html></html>"
        }
        let outgoing = await collect(
            service,
            path: "/bookSourceDebug",
            message: "{\"tag\":\"https://source.example\",\"key\":\"关键字\"}"
        )
        let messages = texts(outgoing)
        XCTAssertTrue(messages.contains { $0.contains("⇒开始搜索关键字:关键字") }, "\(messages)")
        XCTAssertTrue(messages.contains { $0.contains("︾开始解析搜索页") }, "\(messages)")
        XCTAssertTrue(outgoing.contains(.close))
    }

    func testTheSearchReturnsTheResultsAsJson() async throws {
        var source = BookSource(bookSourceUrl: "https://source.example", bookSourceName: "Source")
        source.enabled = true
        source.searchUrl = "https://source.example/search?key={{key}}"
        source.ruleSearch = "{\"bookList\":\"div.item\",\"name\":\"a.name@text\",\"author\":\"span.author@text\",\"bookUrl\":\"a@href\"}"
        try store.insert(source)

        let service = makeService { request in
            if request.url.contains("/search") {
                return """
                <div class="item"><a class="name" href="/book/1">书名</a><span class="author">作者</span></div>
                """
            }
            return "<html></html>"
        }
        let outgoing = await collect(service, path: "/searchBook", message: "{\"key\":\"关键字\"}")
        let messages = texts(outgoing)
        XCTAssertEqual(messages.count, 1, "\(messages)")
        let value = try JSONValue.parse(messages[0])
        guard case let .array(items) = value else {
            return XCTFail("expected an array, got \(value)")
        }
        XCTAssertEqual(items.count, 1)
        XCTAssertTrue(outgoing.contains(.close))
    }

    func testTheSearchWithoutAKeyIsRejected() async {
        let service = makeService { _ in "" }
        let outgoing = await collect(service, path: "/searchBook", message: "{\"key\":\"\"}")
        XCTAssertEqual(texts(outgoing), [LegadoWebSocketService.cannotBeEmptyMessage])
        XCTAssertTrue(outgoing.contains(.close))
    }
}
