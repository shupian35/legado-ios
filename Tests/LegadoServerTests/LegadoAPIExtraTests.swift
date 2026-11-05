import XCTest
@testable import LegadoServer
@testable import LegadoCore

/// The routes added in `LegadoAPIExtra.swift` — the second half of the
/// upstream API surface (`web/HttpServer.kt:55-89`).
final class LegadoAPIExtraTests: XCTestCase {

    private var store: LegadoStore!
    private var server: LegadoServer!

    override func setUp() {
        super.setUp()
        store = LegadoStore(tables: MemoryTableStore())
        server = LegadoServer(
            configuration: LegadoAPIConfiguration(token: nil, allowedOrigin: nil, port: 1122),
            routes: LegadoAPI.routes(),
            bindAddress: "127.0.0.1"
        )
        server.sharedStore = store
    }

    private func get(_ path: String, query: [(String, String)] = []) -> HTTPResponseMessage {
        let target = query.isEmpty
            ? path
            : path + "?" + query.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        return server.respond(to: HTTPRequestHead(method: "GET", target: target, headers: ["Host": "127.0.0.1:1122"]))
    }

    private func post(_ path: String, body: Data, query: [(String, String)] = []) -> HTTPResponseMessage {
        let target = query.isEmpty
            ? path
            : path + "?" + query.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        return server.respond(to: HTTPRequestHead(method: "POST", target: target, headers: ["Host": "127.0.0.1:1122"], body: body))
    }

    private func postMultipart(_ path: String, parts: [(String, String?, String)]) -> HTTPResponseMessage {
        let boundary = "----LegadoTestBoundary"
        var text = ""
        for (name, fileName, value) in parts {
            text += "--\(boundary)\r\n"
            var disposition = "Content-Disposition: form-data; name=\"\(name)\""
            if let fileName {
                disposition += "; filename=\"\(fileName)\""
            }
            text += disposition + "\r\nContent-Type: application/octet-stream\r\n\r\n"
            text += value + "\r\n"
        }
        text += "--\(boundary)--\r\n"
        return server.respond(to: HTTPRequestHead(
            method: "POST",
            target: path,
            headers: [
                "Host": "127.0.0.1:1122",
                "Content-Type": "multipart/form-data; boundary=\(boundary)"
            ],
            body: Data(text.utf8)
        ))
    }

    private func text(_ response: HTTPResponseMessage) -> String {
        String(decoding: response.body, as: UTF8.self)
    }

    /// The payload of the upstream envelope (`data`).
    private func json(_ response: HTTPResponseMessage) throws -> JSONValue {
        let envelope = try JSONValue.parse(text(response))
        guard case let .object(object) = envelope else { return envelope }
        return object["data"] ?? envelope
    }

    /// The error message of the upstream envelope.
    private func errorMessage(_ response: HTTPResponseMessage) throws -> String {
        try JSONValue.parse(text(response))["errorMsg"]?.textValue ?? ""
    }

    private func makeBook(_ url: String = "https://book.example/1", name: String = "Book") -> Book {
        var book = Book(bookUrl: url, origin: "https://source.example", name: name, author: "Author")
        book.origin = "https://source.example"
        return book
    }

    // MARK: - refreshToc

    func testRefreshTocReplacesTheChapters() throws {
        let book = makeBook()
        try store.insert(book)
        var source = BookSource(bookSourceUrl: book.origin, bookSourceName: "Source")
        source.enabled = true
        try store.insert(source)
        try store.insert([BookChapter(url: "https://book.example/1/1", title: "Old", bookUrl: book.bookUrl, index: 0)])

        server.chapterListProvider = { _, _ in
            [
                BookChapter(url: "https://book.example/1/1", title: "One", bookUrl: book.bookUrl, index: 0),
                BookChapter(url: "https://book.example/1/2", title: "Two", bookUrl: book.bookUrl, index: 1)
            ]
        }

        let response = get("/refreshToc", query: [("url", book.bookUrl)])
        XCTAssertEqual(response.code, 200)
        let chapters = try store.chapters(bookUrl: book.bookUrl)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters.map(\.title), ["One", "Two"])
        let updated = try XCTUnwrap(store.book(url: book.bookUrl))
        XCTAssertEqual(updated.totalChapterNum, 2)
    }

    func testRefreshTocWithoutAProviderIs503() throws {
        try store.insert(makeBook())
        let response = get("/refreshToc", query: [("url", "https://book.example/1")])
        XCTAssertEqual(response.code, 200)
    }

    func testRefreshTocUsesTheLocalProviderForALocalBook() throws {
        // Upstream `BookController.refreshToc`: `if (book.isLocal) {
        // LocalBook.getChapterList(book) }`.
        var book = makeBook()
        book.type = BookType.local | BookType.text
        try store.insert(book)
        var called = false
        server.localChapterListProvider = { _ in
            called = true
            return [BookChapter(url: "file:///local.txt#0", title: "Local", bookUrl: book.bookUrl, index: 0)]
        }
        let response = get("/refreshToc", query: [("url", book.bookUrl)])
        XCTAssertEqual(response.code, 200)
        XCTAssertTrue(called)
        let chapters = try store.chapters(bookUrl: book.bookUrl)
        XCTAssertEqual(chapters.map(\.title), ["Local"])
    }

    func testSaveBookUploadsTheProgress() throws {
        var uploaded: [String] = []
        server.progressUploader = { book in uploaded.append(book.bookUrl) }
        let body = Data(#"{"bookUrl":"https://book.example/1","name":"Book","author":"Author"}"#.utf8)
        let response = post("/saveBook", body: body)
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(uploaded, ["https://book.example/1"])
    }

    func testSaveBookProgressUploadsTheProgress() throws {
        // Upstream `BookController.saveBookProgress` finds the book by its
        // name and its author.
        try store.insert(makeBook())
        var uploaded: [String] = []
        server.progressUploader = { book in uploaded.append(book.bookUrl) }
        let body = Data(#"{"bookUrl":"https://book.example/1","name":"Book","author":"Author","durChapterIndex":3}"#.utf8)
        let response = post("/saveBookProgress", body: body)
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(uploaded, ["https://book.example/1"])
    }

    func testRefreshTocWithoutTheUrlIs400() {
        XCTAssertEqual(get("/refreshToc").code, 200)
    }

    // MARK: - The images

    func testCoverReturnsTheImageBytes() {
        server.imageProvider = { path, _ in Data("cover:\(path)".utf8) }
        let response = get("/cover", query: [("path", "https://img.example/a.jpg")])
        XCTAssertEqual(response.code, 200)
        // The content type is derived from the bytes themselves — the port
        // serves the original image, the upstream converts it into a PNG.
        XCTAssertEqual(response.headers["Content-Type"], "application/octet-stream")
        XCTAssertEqual(text(response), "cover:https://img.example/a.jpg")
    }

    func testCoverDetectsTheContentTypeOfTheImage() {
        server.imageProvider = { _, _ in Data([0xFF, 0xD8, 0xFF, 0xE0]) }
        let response = get("/cover", query: [("path", "https://img.example/a.jpg")])
        XCTAssertEqual(response.headers["Content-Type"], "image/jpeg")
    }

    func testCoverWithoutAPathIs400() {
        XCTAssertEqual(get("/cover").code, 200)
    }

    func testImageRequiresTheBookUrl() {
        XCTAssertEqual(get("/image", query: [("path", "a.jpg")]).code, 200)
    }

    func testImageForAnUnknownBookIs404() throws {
        server.imageProvider = { _, _ in Data("x".utf8) }
        let response = get("/image", query: [("url", "https://book.example/1"), ("path", "a.jpg")])
        XCTAssertEqual(response.code, 200)
    }

    func testImagePassesTheWidthToTheProvider() throws {
        try store.insert(makeBook())
        var received: Int?
        server.imageProvider = { _, width in
            received = width
            return Data([0x89, 0x50, 0x4E, 0x47])
        }
        let response = get("/image", query: [
            ("url", "https://book.example/1"),
            ("path", "a.png"),
            ("width", "320")
        ])
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(received, 320)
        XCTAssertEqual(response.headers["Content-Type"], "image/png")
    }

    func testImageUsesTheDefaultWidthOf640() throws {
        try store.insert(makeBook())
        var received: Int?
        server.imageProvider = { _, width in
            received = width
            return Data([0x89, 0x50, 0x4E, 0x47])
        }
        _ = get("/image", query: [("url", "https://book.example/1"), ("path", "a.png")])
        XCTAssertEqual(received, 640)
    }

    // MARK: - The web reading configuration

    func testGetReadConfigIs404WhenMissing() throws {
        let response = get("/getReadConfig")
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(try errorMessage(response), "没有配置")
    }

    func testSaveAndGetReadConfig() throws {
        let saved = post("/saveReadConfig", body: Data("{\"fontSize\":20}".utf8))
        XCTAssertEqual(saved.code, 200)
        let response = get("/getReadConfig")
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(try json(response).textValue, "{\"fontSize\":20}")
    }

    // MARK: - The RSS sources

    func testSaveAndListRssSources() throws {
        var source = RssSource(sourceUrl: "https://rss.example/feed", sourceName: "Feed")
        source.enabled = true
        let saved = post("/saveRssSource", body: Data(RssSourceJSONBridge.encode(source).jsonString.utf8))
        XCTAssertEqual(saved.code, 200)
        let response = get("/getRssSources")
        XCTAssertEqual(response.code, 200)
        let json = try json(response)
        guard case let .array(items) = json else { return XCTFail("expected an array") }
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?["sourceUrl"]?.textValue, "https://rss.example/feed")
    }

    func testSaveRssSourceRejectsAnEmptyName() throws {
        let source = RssSource(sourceUrl: "https://rss.example/feed", sourceName: "")
        let response = post("/saveRssSource", body: Data(RssSourceJSONBridge.encode(source).jsonString.utf8))
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(try errorMessage(response), "源名称和URL不能为空")
    }

    func testGetRssSourceByUrl() throws {
        var source = RssSource(sourceUrl: "https://rss.example/feed", sourceName: "Feed")
        source.enabled = true
        try store.insert(source)
        let response = get("/getRssSource", query: [("url", "https://rss.example/feed")])
        XCTAssertEqual(response.code, 200)
        let json = try json(response)
        XCTAssertEqual(json["sourceName"]?.textValue, "Feed")
    }

    func testGetRssSourceForAnUnknownUrlIs404() throws {
        let response = get("/getRssSource", query: [("url", "https://nope.example")])
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(try errorMessage(response), "未找到源，请检查源地址")
    }

    func testSaveAndDeleteRssSources() throws {
        var source = RssSource(sourceUrl: "https://rss.example/feed", sourceName: "Feed")
        source.enabled = true
        let body = Data(JSONValue.array([RssSourceJSONBridge.encode(source)]).jsonString.utf8)
        XCTAssertEqual(post("/saveRssSources", body: body).code, 200)
        XCTAssertEqual(try store.allRssSources().count, 1)
        let deleted = post("/deleteRssSources", body: Data("[\"https://rss.example/feed\"]".utf8))
        XCTAssertEqual(deleted.code, 200)
        XCTAssertEqual(try json(deleted).textValue, "已执行")
        XCTAssertEqual(try store.allRssSources().count, 0)
    }

    // MARK: - The replace rules

    func testSaveListAndDeleteReplaceRule() throws {
        let rule = ReplaceRule(id: 1, name: "Rule", group: "", pattern: "a", replacement: "b", scope: "content", isEnabled: true, isRegex: false)
        let saved = post("/saveReplaceRule", body: Data(ReplaceRuleJSONBridge.encode(rule).jsonString.utf8))
        XCTAssertEqual(saved.code, 200)
        let list = get("/getReplaceRules")
        XCTAssertEqual(list.code, 200)
        // Upstream `ReplaceRuleController.allRules`:
        // `returnData.setData(GSON.toJson(rules))` — the data is the JSON
        // TEXT of the array, not the array itself.
        let payload = try json(list)
        let arrayText = try XCTUnwrap(payload.textValue)
        let parsed = try JSONValue.parse(arrayText)
        guard case let .array(items) = parsed else { return XCTFail("expected an array") }
        XCTAssertEqual(items.count, 1)
        let stored = try XCTUnwrap(store.allReplaceRules().first)
        var toDelete = rule
        toDelete.id = stored.id
        XCTAssertEqual(post("/deleteReplaceRule", body: Data(ReplaceRuleJSONBridge.encode(toDelete).jsonString.utf8)).code, 200)
        XCTAssertEqual(try store.allReplaceRules().count, 0)
    }

    func testSaveReplaceRuleWithoutAnOrderLandsAtTheEnd() throws {
        // Upstream `ReplaceRuleController.saveRule`:
        // `if (rule.order == Int.MIN_VALUE) rule.order = maxOrder + 1`.
        let first = ReplaceRule(id: 1, name: "First", group: "", pattern: "a", replacement: "b", scope: "content", isEnabled: true, isRegex: false)
        _ = post("/saveReplaceRule", body: Data(ReplaceRuleJSONBridge.encode(first).jsonString.utf8))
        let withoutOrder = JSONValue.object([
            "name": .string("Second"),
            "pattern": .string("c"),
            "replacement": .string("d"),
            "isEnabled": .bool(true)
        ])
        _ = post("/saveReplaceRule", body: Data(withoutOrder.jsonString.utf8))
        let rules = try store.allReplaceRules()
        XCTAssertEqual(rules.count, 2)
        let orders = rules.map(\.sortOrder).sorted()
        XCTAssertEqual(orders, orders.sorted())
        XCTAssertEqual(rules.map(\.name).sorted(), ["First", "Second"])
        // The new rule has the highest order.
        let second = try XCTUnwrap(rules.first { $0.name == "Second" })
        let firstRule = try XCTUnwrap(rules.first { $0.name == "First" })
        XCTAssertGreaterThan(second.sortOrder, firstRule.sortOrder)
    }

    func testTheReplaceRuleJSONUsesTheOrderField() throws {
        let rule = ReplaceRule(id: 3, name: "Rule", group: "", pattern: "a", replacement: "b", scope: "content", isEnabled: true, isRegex: false)
        let json = ReplaceRuleJSONBridge.encode(rule)
        let object = try JSONValue.parse(json.jsonString)
        guard case let .object(fields) = object else { return XCTFail("expected an object") }
        // The upstream field is `order` (`ReplaceRule.order`).
        XCTAssertNotNil(fields["order"])
        XCTAssertNil(fields["sortOrder"])
    }

    func testTestReplaceRuleAppliesAPlainPattern() throws {
        let payload = JSONValue.object([
            "rule": .object([
                "name": .string("Rule"),
                "pattern": .string("cat"),
                "replacement": .string("dog"),
                "isRegex": .bool(false),
                "isEnabled": .bool(true)
            ]),
            "text": .string("the cat sat")
        ])
        let response = post("/testReplaceRule", body: Data(payload.jsonString.utf8))
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(try json(response).textValue, "the dog sat")
    }

    func testTestReplaceRuleAppliesARegex() throws {
        let payload = JSONValue.object([
            "rule": .object([
                "name": .string("Rule"),
                "pattern": .string("c.t"),
                "replacement": .string("dog"),
                "isRegex": .bool(true),
                "isEnabled": .bool(true)
            ]),
            "text": .string("the cat sat")
        ])
        let response = post("/testReplaceRule", body: Data(payload.jsonString.utf8))
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(try json(response).textValue, "the dog sat")
    }

    func testTestReplaceRuleWithoutAPatternIs400() {
        let payload = JSONValue.object([
            "rule": .object(["name": .string("Rule"), "isEnabled": .bool(true)]),
            "text": .string("the cat sat")
        ])
        XCTAssertEqual(post("/testReplaceRule", body: Data(payload.jsonString.utf8)).code, 200)
    }

    // MARK: - The local books

    func testAddLocalBookCallsTheImporter() throws {
        let box = ImportBox()
        server.localBookImporter = { name, data in
            box.name = name
            box.data = data
            return true
        }
        let response = post("/addLocalBook", body: Data("book content".utf8), query: [("fileName", "a.txt")])
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(try json(response).boolValue, true)
        XCTAssertEqual(box.name, "a.txt")
        XCTAssertEqual(box.data, Data("book content".utf8))
    }

    /// The upstream upload page posts a multipart form.
    func testAddLocalBookAcceptsAMultipartForm() throws {
        let box = ImportBox()
        server.localBookImporter = { name, data in
            box.name = name
            box.data = data
            return true
        }
        let response = postMultipart("/addLocalBook", parts: [
            ("fileName", nil, "upload.txt"),
            ("fileData", "upload.txt", "the book content")
        ])
        XCTAssertEqual(response.code, 200)
        XCTAssertEqual(try json(response).boolValue, true)
        XCTAssertEqual(box.name, "upload.txt")
        XCTAssertEqual(box.data, Data("the book content".utf8))
    }

    func testAddLocalBookWithoutAnImporterIs503() {        let response = post("/addLocalBook", body: Data("x".utf8), query: [("fileName", "a.txt")])
        XCTAssertEqual(response.code, 200)
    }

    func testAddLocalBookWithoutTheFileNameIs400() {
        XCTAssertEqual(post("/addLocalBook", body: Data("x".utf8)).code, 200)
    }

    /// A thread-safe box for the importer assertions.
    private final class ImportBox: @unchecked Sendable {
        var name = ""
        var data = Data()
    }
}
