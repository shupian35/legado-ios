import XCTest
@testable import LegadoServer
import LegadoCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

final class HTTPParserTests: XCTestCase {

    func testParsesSimpleGet() throws {
        let raw = "GET /getBookshelf HTTP/1.1\r\nHost: 127.0.0.1:1122\r\nAccept: */*\r\n\r\n"
        let (request, consumed) = try HTTPParser.parseRequest(Data(raw.utf8))
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/getBookshelf")
        XCTAssertEqual(request.target, "/getBookshelf")
        XCTAssertEqual(request.header("host"), "127.0.0.1:1122")
        XCTAssertEqual(request.header("ACCEPT"), "*/*")
        XCTAssertTrue(request.body.isEmpty)
        XCTAssertEqual(consumed, Data(raw.utf8).count)
    }

    func testParsesQueryAndDecodesPercentEscapes() throws {
        let raw = "GET /getChapterList?url=https%3A%2F%2Fa.com%2Fb&index=3 HTTP/1.1\r\n\r\n"
        let (request, _) = try HTTPParser.parseRequest(Data(raw.utf8))
        XCTAssertEqual(request.path, "/getChapterList")
        XCTAssertEqual(request.query("url"), "https://a.com/b")
        XCTAssertEqual(request.query("index"), "3")
        XCTAssertEqual(request.query("missing"), nil)
    }

    func testPlusIsDecodedAsSpace() throws {
        let (request, _) = try HTTPParser.parseRequest(Data("GET /x?name=%E4%B9%A6+name HTTP/1.1\r\n\r\n".utf8))
        XCTAssertEqual(request.query("name"), "书 name")
    }

    func testParsesPostWithBody() throws {
        let body = "{\"bookUrl\":\"https://a.com/b\"}"
        let raw = "POST /saveBook HTTP/1.1\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
        let (request, consumed) = try HTTPParser.parseRequest(Data(raw.utf8))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.bodyText, body)
        XCTAssertEqual(consumed, Data(raw.utf8).count)
    }

    func testIncompleteRequestThrowsIncomplete() {
        XCTAssertThrowsError(try HTTPParser.parseRequest(Data("GET /x HTTP/1.1\r\nHost: a\r\n".utf8))) { error in
            XCTAssertEqual(error as? HTTPParseError, .incomplete)
        }
    }

    func testIncompleteBodyThrowsIncomplete() {
        let raw = "POST /x HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc"
        XCTAssertThrowsError(try HTTPParser.parseRequest(Data(raw.utf8))) { error in
            XCTAssertEqual(error as? HTTPParseError, .incomplete)
        }
    }

    func testTwoPipelinedRequestsConsumeOnlyTheFirst() throws {
        let first = "GET /a HTTP/1.1\r\n\r\n"
        let second = "GET /b HTTP/1.1\r\n\r\n"
        let data = Data((first + second).utf8)
        let (request, consumed) = try HTTPParser.parseRequest(data)
        XCTAssertEqual(request.path, "/a")
        XCTAssertEqual(consumed, Data(first.utf8).count)
        let (next, _) = try HTTPParser.parseRequest(data.subdata(in: consumed..<data.count))
        XCTAssertEqual(next.path, "/b")
    }

    func testMalformedFirstLineThrows() {
        XCTAssertThrowsError(try HTTPParser.parseRequest(Data("GARBAGE\r\n\r\n".utf8))) { error in
            guard case .malformed = (error as? HTTPParseError) else {
                return XCTFail("expected malformed, got \(error)")
            }
        }
    }

    func testResponseSerialization() {
        let response = HTTPResponseMessage.json(JSONValue.object(["ok": .bool(true)]).jsonString)
        let text = String(decoding: response.serialized(keepAlive: true), as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        XCTAssertTrue(text.contains("Content-Type: application/json"))
        XCTAssertTrue(text.hasSuffix("{\"ok\":true}"))
    }

    func testErrorResponseCarriesMessage() {
        let response = HTTPResponseMessage.error("boom", code: 400)
        XCTAssertEqual(response.code, 400)
        XCTAssertTrue(String(decoding: response.body, as: UTF8.self).contains("boom"))
    }
}

final class WebSocketTests: XCTestCase {

    private func upgradeRequest(key: String = "dGhlIHNhbXBsZSBub25jZQ==") -> HTTPRequestHead {
        HTTPRequestHead(
            method: "GET",
            target: "/bookSourceDebug",
            headers: [
                "Host": "127.0.0.1:1123",
                "Upgrade": "websocket",
                "Connection": "Upgrade",
                "Sec-WebSocket-Key": key,
                "Sec-WebSocket-Version": "13"
            ],
            body: Data()
        )
    }

    func testAcceptTokenMatchesRFC6455Example() {
        XCTAssertEqual(WebSocket.acceptToken(for: "dGhlIHNhbXBsZSBub25jZQ=="), "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    func testSHA1() {
        XCTAssertEqual(SHA1.hex(Array("abc".utf8)), "a9993e364706816aba3e25717850c26c9cd0d89d")
        XCTAssertEqual(SHA1.hex([]), "da39a3ee5e6b4b0d3255bfef95601890afd80709")
    }

    func testIsUpgradeRequest() {
        XCTAssertTrue(WebSocket.isUpgradeRequest(upgradeRequest()))
        let plain = HTTPRequestHead(method: "GET", target: "/")
        XCTAssertFalse(WebSocket.isUpgradeRequest(plain))
    }

    func testHandshakeResponse() {
        let response = WebSocket.handshakeResponse(for: upgradeRequest())
        XCTAssertEqual(response.code, 101)
        XCTAssertEqual(response.headers["Upgrade"], "websocket")
        XCTAssertEqual(response.headers["Connection"], "Upgrade")
        XCTAssertEqual(response.headers["Sec-WebSocket-Accept"], "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
    }

    func testTextFrameRoundTrip() throws {
        let frame = WebSocket.Frame(opcode: .text, payload: Data("hello".utf8))
        let encoded = WebSocket.encode(frame)
        // The server never masks; the client does. Build a masked client frame
        // by hand and decode it back.
        var masked = Data([0x81])
        masked.append(0x80 | UInt8(frame.payload.count))
        let mask = Data([0x37, 0xfa, 0x21, 0x3d])
        masked.append(mask)
        masked.append(contentsOf: frame.payload.enumerated().map { $0.element ^ mask[$0.offset % mask.count] })
        let decoded = try WebSocket.decode(masked)
        XCTAssertEqual(decoded?.frame.opcode, .text)
        XCTAssertEqual(decoded?.frame.text, "hello")
        XCTAssertEqual(decoded?.consumed, masked.count)

        // An unmasked frame (as sent by a server) also decodes.
        let serverSide = try WebSocket.decode(encoded)
        XCTAssertEqual(serverSide?.frame.text, "hello")
    }

    func testPingPongOpcodes() {
        XCTAssertEqual(WebSocket.encode(.init(opcode: .ping, payload: Data("p".utf8))).first, 0x89)
        XCTAssertEqual(WebSocket.encode(.init(opcode: .pong, payload: Data("p".utf8))).first, 0x8A)
        XCTAssertEqual(WebSocket.encode(.init(opcode: .close)).first, 0x88)
    }

    func testIncompleteFrameReturnsNil() {
        let encoded = WebSocket.encode(.init(opcode: .text, payload: Data("hello".utf8)))
        XCTAssertNil(try WebSocket.decode(encoded.prefix(3)))
    }

    func testFrameTooLargeThrows() {
        var huge = Data([0x81, 0x80 | 127])
        withUnsafeBytes(of: UInt64.max.bigEndian) { huge.append(contentsOf: $0) }
        XCTAssertThrowsError(try WebSocket.decode(huge)) { error in
            XCTAssertEqual(error as? WebSocketError, .frameTooLarge)
        }
    }
}

final class LegadoAPITests: XCTestCase {

    private var store: LegadoStore!
    private var configuration: LegadoAPIConfiguration!
    private var server: LegadoServer!

    override func setUp() {
        super.setUp()
        store = LegadoStore(tables: MemoryTableStore())
        configuration = LegadoAPIConfiguration(token: nil, allowedOrigin: nil, port: 1122)
        server = LegadoServer(configuration: configuration, routes: LegadoAPI.routes(), bindAddress: "127.0.0.1")
        server.sharedStore = store
    }

    private func get(_ path: String, query: [(String, String)] = [], headers: [String: String] = [:]) -> HTTPResponseMessage {
        let target = query.isEmpty
            ? path
            : path + "?" + query.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        var all = headers
        all["Host"] = "127.0.0.1:1122"
        return server.respond(to: HTTPRequestHead(method: "GET", target: target, headers: all))
    }

    private func post(_ path: String, body: JSONValue, headers: [String: String] = [:]) -> HTTPResponseMessage {
        var all = headers
        all["Content-Type"] = "application/json"
        let data = Data(body.jsonString.utf8)
        return server.respond(to: HTTPRequestHead(method: "POST", target: path, headers: all, body: data))
    }

    /// The payload of the upstream envelope (`data`) — upstream `ReturnData`.
    private func json(_ response: HTTPResponseMessage) throws -> JSONValue {
        let envelope = try JSONValue.parse(String(decoding: response.body, as: UTF8.self))
        guard case let .object(object) = envelope else { return envelope }
        return object["data"] ?? envelope
    }

    /// The whole envelope.
    private func envelope(_ response: HTTPResponseMessage) throws -> JSONValue {
        try JSONValue.parse(String(decoding: response.body, as: UTF8.self))
    }

    /// The error message of the envelope.
    private func errorMessage(_ response: HTTPResponseMessage) throws -> String {
        try envelope(response)["errorMsg"]?.textValue ?? ""
    }

    private func arrayCount(_ value: JSONValue) -> Int? {
        if case let .array(items) = value { return items.count }
        return nil
    }

    private func makeSource(_ url: String = "https://source.example") -> BookSource {
        var source = BookSource(bookSourceUrl: url, bookSourceName: "Source")
        source.searchUrl = "https://source.example/search?key={{key}}"
        source.ruleSearch = "{\"bookList\":\"class.item\"}"
        return source
    }

    private func makeBook(_ url: String = "https://book.example/1", name: String = "Book") -> Book {
        Book(bookUrl: url, origin: "https://source.example", name: name, author: "Author", intro: "Intro")
    }

    func testGetBookshelfReturnsTheBooks() throws {
        try store.insert(makeBook())
        try store.insert(BookGroup(groupId: -1, groupName: "全部", order: 1, enableRefresh: true, show: true))
        let response = get("/getBookshelf")
        XCTAssertEqual(response.code, 200)
        let body = try json(response)
        XCTAssertEqual(arrayCount(body), 1)
        // The upstream envelope.
        XCTAssertEqual(try envelope(response)["isSuccess"]?.boolValue, true)
    }

    func testAnEmptyBookshelfIsAnErrorMessage() throws {
        let response = get("/getBookshelf")
        // Upstream `BookController.bookshelf`: an empty shelf is an error in
        // the envelope, the HTTP status stays 200.
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(try errorMessage(response), "还没有添加小说")
    }

    func testGetChapterListRequiresUrl() throws {
        let response = get("/getChapterList")
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(try errorMessage(response), "参数url不能为空，请指定书籍地址")
    }

    func testGetChapterListReturnsChapters() throws {
        let book = makeBook()
        try store.insert(book)
        try store.insert([
            BookChapter(url: "c1", title: "One", bookUrl: book.bookUrl, index: 0),
            BookChapter(url: "c2", title: "Two", bookUrl: book.bookUrl, index: 1)
        ])
        let body = try json(get("/getChapterList", query: [("url", book.bookUrl)]))
        XCTAssertEqual(arrayCount(body), 2)
    }

    func testGetBookSources() throws {
        try store.insert(makeSource())
        let body = try json(get("/getBookSources"))
        XCTAssertEqual(arrayCount(body), 1)
    }

    func testGetBookSourceByUrl() throws {
        try store.insert(makeSource())
        let one = try json(get("/getBookSource", query: [("url", "https://source.example")]))
        XCTAssertEqual(one["bookSourceName"]?.textValue, "Source")
        let missing = get("/getBookSource", query: [("url", "https://nope")])
        XCTAssertEqual(missing.code, 200)
        XCTAssertEqual(try errorMessage(missing), "未找到源，请检查书源地址")
    }

    func testSaveAndDeleteBookSource() throws {
        let payload = BookSourceJSON.encode(makeSource())
        XCTAssertEqual(post("/saveBookSource", body: payload).code, 200)
        XCTAssertEqual(try store.allSources().count, 1)

        let deleted = post("/deleteBookSources", body: .array([.string("https://source.example")]))
        XCTAssertEqual(deleted.code, 200)
        XCTAssertEqual(try store.allSources().count, 0)
    }

    func testSaveBookSourcesTakesArray() throws {
        let payload = JSONValue.array([BookSourceJSON.encode(makeSource("https://a")), BookSourceJSON.encode(makeSource("https://b"))])
        XCTAssertEqual(post("/saveBookSources", body: payload).code, 200)
        XCTAssertEqual(try store.allSources().count, 2)
    }

    func testSaveBookAndDeleteBook() throws {
        let payload = BookSourceJSON.encode(makeSource()) // wrong shape on purpose
        let wrong = post("/saveBook", body: payload)
        XCTAssertEqual(wrong.code, 200)
        XCTAssertEqual(try errorMessage(wrong), "格式不对")

        var object: [String: JSONValue] = [
            "bookUrl": .string("https://book.example/9"),
            "name": .string("Nine"),
            "author": .string("A"),
            "origin": .string("https://source.example")
        ]
        object["durChapterIndex"] = .number(2)
        XCTAssertEqual(post("/saveBook", body: .object(object)).code, 200)
        XCTAssertEqual(try store.allBooks().count, 1)

        XCTAssertEqual(post("/deleteBook", body: .object(["bookUrl": .string("https://book.example/9")])).code, 200)
        XCTAssertEqual(try store.allBooks().count, 0)
    }

    func testSaveBookProgressUpdatesBook() throws {
        try store.insert(makeBook())
        let payload = JSONValue.object([
            "name": .string("Book"),
            "author": .string("Author"),
            "durChapterIndex": .number(4),
            "durChapterPos": .number(17),
            "durChapterTime": .number(1_700_000_000),
            "durChapterTitle": .string("Chapter Five")
        ])
        XCTAssertEqual(post("/saveBookProgress", body: payload).code, 200)
        let book = try store.book(url: "https://book.example/1")
        XCTAssertEqual(book?.durChapterIndex, 4)
        XCTAssertEqual(book?.durChapterPos, 17)
        XCTAssertEqual(book?.durChapterTitle, "Chapter Five")
    }

    func testSaveBookProgressForUnknownBookIs404() throws {
        let payload = JSONValue.object([
            "name": .string("Ghost"),
            "author": .string("Nobody"),
            "durChapterIndex": .number(1)
        ])
        let response = post("/saveBookProgress", body: payload)
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(try errorMessage(response), "格式不对")
    }

    func testTokenIsRequiredWhenConfigured() throws {
        server = LegadoServer(
            configuration: LegadoAPIConfiguration(token: "s3cret", allowedOrigin: "http://localhost:8080", port: 1122),
            routes: LegadoAPI.routes(),
            bindAddress: "127.0.0.1"
        )
        server.sharedStore = store

        XCTAssertEqual(get("/getBookshelf").code, 401)
        XCTAssertEqual(get("/getBookshelf", headers: ["Authorization": "Bearer wrong"]).code, 401)
        let ok = get("/getBookshelf", headers: ["Authorization": "Bearer s3cret"])
        XCTAssertEqual(ok.code, 200)
        XCTAssertEqual(ok.headers["Access-Control-Allow-Origin"], "http://localhost:8080")

        XCTAssertEqual(get("/getBookshelf", query: [("token", "s3cret")]).code, 200)
    }

    func testUnknownRouteFallsBack() {
        let response = get("/nope")
        XCTAssertEqual(response.code, 404)
    }

    func testOptionsRequest() {
        let response = server.respond(to: HTTPRequestHead(method: "OPTIONS", target: "/getBookshelf"))
        XCTAssertEqual(response.code, 204)
        XCTAssertEqual(response.headers["Allow"], "GET, POST, OPTIONS")
    }

    func testBookJSONRoundTrip() throws {
        let book = makeBook()
        let decoded = BookJSON.decode(LegadoAPI.bookJSON(book))
        XCTAssertEqual(decoded?.bookUrl, book.bookUrl)
        XCTAssertEqual(decoded?.name, book.name)
    }

    func testSourceJSONRoundTrip() throws {
        let source = makeSource()
        let decoded = BookSourceJSON.decode(LegadoAPI.sourceJSON(source))
        XCTAssertEqual(decoded?.bookSourceUrl, source.bookSourceUrl)
        XCTAssertEqual(decoded?.ruleSearch, source.ruleSearch)
    }
}

final class LegadoServerSocketTests: XCTestCase {

    func testServerServesOverTheLoopbackSocket() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.insert(Book(bookUrl: "https://book.example/42", origin: "https://s", name: "Socket Book", author: "A"))
        let server = LegadoServer(
            configuration: LegadoAPIConfiguration(token: nil, allowedOrigin: nil, port: 61_122),
            routes: LegadoAPI.routes(),
            bindAddress: "127.0.0.1"
        )
        server.sharedStore = store
        let port = try server.start()
        defer { server.stop() }

        let response = try sendRaw("GET /getBookshelf HTTP/1.1\r\nHost: 127.0.0.1\r\nConnection: close\r\n\r\n", port: port)
        XCTAssertTrue(response.hasPrefix("HTTP/1.1 200"), response)
        XCTAssertTrue(response.contains("Socket Book"), response)
        XCTAssertEqual(server.status.isRunning, true)
    }

    private func sendRaw(_ request: String, port: Int) throws -> String {
        var collected = Data()
        let semaphore = DispatchSemaphore(value: 0)
        let thread = Thread {
            defer { semaphore.signal() }
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = Int32(SOCK_STREAM.rawValue)
            var info: UnsafeMutablePointer<addrinfo>?
            guard getaddrinfo("127.0.0.1", "\(port)", &hints, &info) == 0, let target = info else { return }
            defer { freeaddrinfo(info) }
            let fd = socket(target.pointee.ai_family, target.pointee.ai_socktype, target.pointee.ai_protocol)
            guard fd >= 0 else { return }
            defer { close(fd) }
            guard connect(fd, target.pointee.ai_addr, target.pointee.ai_addrlen) == 0 else { return }
            let payload = Array(request.utf8)
            payload.withUnsafeBufferPointer { buffer in
                _ = send(fd, buffer.baseAddress!, payload.count, 0)
            }
            var chunk = [UInt8](repeating: 0, count: 4096)
            while true {
                let read = recv(fd, &chunk, chunk.count, 0)
                if read <= 0 { break }
                collected.append(contentsOf: chunk[0..<read])
            }
        }
        thread.start()
        _ = semaphore.wait(timeout: .now() + 10)
        return String(decoding: collected, as: UTF8.self)
    }
}







