import XCTest

@testable import LegadoCore

/// The tests of the remote import — the port of the upstream import view
/// models (`ui/association/ImportBookSourceViewModel.kt` and the RSS source
/// and the replace rule variants).
final class RemoteImportTests: XCTestCase {

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        return store
    }

    private func response(_ body: String, code: Int = 200) -> HttpResponse {
        HttpResponse(url: "https://example.com/x", body: body, code: code)
    }

    // MARK: - The address detection

    func testDetectsTheAbsoluteAddresses() {
        XCTAssertTrue(RemoteImport.isAbsoluteURL("https://example.com/x"))
        XCTAssertTrue(RemoteImport.isAbsoluteURL("http://example.com"))
        XCTAssertTrue(RemoteImport.isAbsoluteURL("legado://import/bookSource"))
        XCTAssertFalse(RemoteImport.isAbsoluteURL("example.com/x"))
        XCTAssertFalse(RemoteImport.isAbsoluteURL("not a url"))
        XCTAssertFalse(RemoteImport.isAbsoluteURL("[{\"bookSourceUrl\":\"https://a.com\"}]"))
    }

    // MARK: - The source addresses

    func testReadsTheSourceURLs() {
        let text = "{\"sourceUrls\":[\"https://a.com/s.json\",\"https://b.com/s.json\"]}"
        XCTAssertEqual(RemoteImport.sourceURLs(in: text), ["https://a.com/s.json", "https://b.com/s.json"])
    }

    func testReadsNoSourceURLs() {
        XCTAssertTrue(RemoteImport.sourceURLs(in: "{\"a\":1}").isEmpty)
        XCTAssertTrue(RemoteImport.sourceURLs(in: "[]").isEmpty)
        XCTAssertTrue(RemoteImport.sourceURLs(in: "not json").isEmpty)
    }

    // MARK: - The import

    func testImportsTheBookSourcesOfAPastedDocument() async throws {
        let store = try makeStore()
        let client = StubHttpClient(handler: { _ in self.response("[]") })
        let count = try await RemoteImport.importText(
            "[{\"bookSourceUrl\":\"https://a.com\",\"bookSourceName\":\"A\"}]",
            kind: .bookSource,
            httpClient: client,
            store: store
        )
        XCTAssertEqual(count, 1)
        let sources = try store.allSources()
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(sources.first?.bookSourceUrl, "https://a.com")
    }

    func testImportsTheBookSourcesOfAnAddress() async throws {
        let store = try makeStore()
        let client = StubHttpClient(handler: { request in
            self.response("[{\"bookSourceUrl\":\"\(request.url)\",\"bookSourceName\":\"A\"}]")
        })
        let count = try await RemoteImport.importText(
            "https://example.com/s.json",
            kind: .bookSource,
            httpClient: client,
            store: store
        )
        XCTAssertEqual(count, 1)
        XCTAssertEqual(client.requests.count, 1)
        XCTAssertEqual(client.requests.first?.url, "https://example.com/s.json")
    }

    func testExpandsTheSourceURLs() async throws {
        let store = try makeStore()
        let client = StubHttpClient(handler: { request in
            self.response("[{\"bookSourceUrl\":\"\(request.url)\",\"bookSourceName\":\"A\"}]")
        })
        let count = try await RemoteImport.importText(
            "{\"sourceUrls\":[\"https://a.com/s.json\",\"https://b.com/s.json\"]}",
            kind: .bookSource,
            httpClient: client,
            store: store
        )
        XCTAssertEqual(count, 2)
        XCTAssertEqual(client.requests.count, 2)
        let sources = try store.allSources()
        XCTAssertEqual(sources.count, 2)
    }

    func testTheUserAgentMarkerIsStripped() async throws {
        let store = try makeStore()
        let client = StubHttpClient(handler: { _ in self.response("[]") })
        _ = try? await RemoteImport.importText(
            "https://example.com/s.json#requestWithoutUA",
            kind: .bookSource,
            httpClient: client,
            store: store
        )
        let request = client.requests.first
        XCTAssertEqual(request?.url, "https://example.com/s.json")
        XCTAssertEqual(request?.headers["User-Agent"], "null")
    }

    func testTheSubscriptionKindSelectsTheTable() async throws {
        let store = try makeStore()
        let client = StubHttpClient(handler: { _ in
            self.response("[{\"sourceUrl\":\"https://rss.com\",\"sourceName\":\"R\"}]")
        })
        let sub = RuleSub(id: 1, name: "RSS", url: "https://rss.com/s.json", type: 1)
        let count = try await RemoteImport.importSubscription(sub, httpClient: client, store: store)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(try store.allRssSources().count, 1)
        XCTAssertEqual(try store.allSources().count, 0)
    }

    func testRejectsAGarbageDocument() async throws {
        let store = try makeStore()
        let client = StubHttpClient(handler: { _ in self.response("[]") })
        do {
            _ = try await RemoteImport.importText(
                "this is not a rule",
                kind: .bookSource,
                httpClient: client,
                store: store
            )
            XCTFail("the import should fail")
        } catch {
            XCTAssertEqual(error as? RemoteImport.ImportError, .wrongFormat)
        }
    }

    func testReportsTheHttpError() async throws {
        let store = try makeStore()
        let client = StubHttpClient(handler: { _ in self.response("nope", code: 500) })
        do {
            _ = try await RemoteImport.importText(
                "https://example.com/s.json",
                kind: .bookSource,
                httpClient: client,
                store: store
            )
            XCTFail("the import should fail")
        } catch {
            XCTAssertEqual(error as? RemoteImport.ImportError, .http(500))
        }
    }
}
