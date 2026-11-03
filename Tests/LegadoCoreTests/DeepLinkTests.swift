//
//  DeepLinkTests.swift
//  LegadoCoreTests
//
//  The port of the upstream import-once tests for
//  app/src/main/java/io/legado/app/ui/association/.
//

import XCTest
@testable import LegadoCore

final class DeepLinkTests: XCTestCase {

    // MARK: - Parsing

    func testParsesTheDocumentedURLFormat() throws {
        let url = URL(string: "legado://import/bookSource?src=https://example.com/s.json")!
        let request = try DeepLink.parse(url)
        XCTAssertEqual(request.path, "/bookSource")
        XCTAssertEqual(request.host, "import")
        XCTAssertEqual(request.source, "https://example.com/s.json")
    }

    func testRejectsAForeignScheme() {
        let url = URL(string: "https://example.com/s.json")!
        XCTAssertThrowsError(try DeepLink.parse(url)) { error in
            XCTAssertEqual(error as? DeepLinkError, .wrongScheme("https"))
        }
    }

    func testRejectsAMissingSource() {
        let url = URL(string: "legado://import/bookSource")!
        XCTAssertThrowsError(try DeepLink.parse(url)) { error in
            XCTAssertEqual(error as? DeepLinkError, .missingSource)
        }
    }

    // MARK: - Kind detection

    func testDetectsABookSource() throws {
        XCTAssertEqual(try DeepLink.detectKind(json: #"{"bookSourceUrl":"https://a"}"#), .bookSource)
    }

    func testDetectsAnRssSource() throws {
        XCTAssertEqual(try DeepLink.detectKind(json: #"{"sourceUrl":"https://a"}"#), .rssSource)
    }

    func testDetectsAReplaceRule() throws {
        XCTAssertEqual(try DeepLink.detectKind(json: #"{"name":"a","pattern":"b"}"#), .replaceRule)
    }

    func testDetectsATxtTocRule() throws {
        XCTAssertEqual(try DeepLink.detectKind(json: #"{"name":"a","rule":"b"}"#), .txtRule)
    }

    func testDetectsAnHttpTtsRule() throws {
        XCTAssertEqual(try DeepLink.detectKind(json: #"{"name":"a","url":"b"}"#), .httpTts)
    }

    func testInspectsTheFirstElementOfAnArray() throws {
        let json = #"[{"bookSourceUrl":"https://a"},{"sourceUrl":"https://b"}]"#
        XCTAssertEqual(try DeepLink.detectKind(json: json), .bookSource)
    }

    func testRejectsAnUnknownFormat() {
        XCTAssertThrowsError(try DeepLink.detectKind(json: #"{"foo":"bar"}"#)) { error in
            XCTAssertEqual(error as? DeepLinkError, .unknownFormat)
        }
        XCTAssertThrowsError(try DeepLink.detectKind(json: "not json")) { error in
            XCTAssertEqual(error as? DeepLinkError, .unknownFormat)
        }
    }

    // MARK: - Paths

    func testThePathSelectsTheKind() {
        XCTAssertEqual(DeepLink.kind(forPath: "/bookSource", host: "import"), .bookSource)
        XCTAssertEqual(DeepLink.kind(forPath: "/rssSource", host: "import"), .rssSource)
        XCTAssertEqual(DeepLink.kind(forPath: "/replaceRule", host: "import"), .replaceRule)
        XCTAssertEqual(DeepLink.kind(forPath: "/textTocRule", host: "import"), .txtRule)
        XCTAssertEqual(DeepLink.kind(forPath: "/httpTTS", host: "import"), .httpTts)
        XCTAssertEqual(DeepLink.kind(forPath: "/dictRule", host: "import"), .dictRule)
        XCTAssertEqual(DeepLink.kind(forPath: "/theme", host: "import"), .theme)
    }

    func testTheImportOnlineHostSelectsTheKind() {
        XCTAssertEqual(DeepLink.kind(forPath: "/importonline", host: "booksource"), .bookSource)
        XCTAssertEqual(DeepLink.kind(forPath: "/importonline", host: "rsssource"), .rssSource)
        XCTAssertEqual(DeepLink.kind(forPath: "/importonline", host: "replace"), .replaceRule)
        XCTAssertNil(DeepLink.kind(forPath: "/importonline", host: "other"))
    }

    // MARK: - Importing

    func testImportsBookSources() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        let json = #"[{"bookSourceUrl":"https://a","bookSourceName":"源 A","enabled":true}]"#
        let summary = try DeepLink.importJSON(json, kind: .bookSource, store: store)
        XCTAssertEqual(summary.kind, .bookSource)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.name, "源 A")
        XCTAssertEqual(try store.allSources().count, 1)
    }

    func testImportsRssSources() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        let json = #"[{"sourceUrl":"https://r","sourceName":"RSS"}]"#
        let summary = try DeepLink.importJSON(json, kind: .rssSource, store: store)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(try store.allRssSources().count, 1)
    }

    func testImportsReplaceRules() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        let json = #"[{"name":"净化","pattern":"a","replacement":"b"}]"#
        let summary = try DeepLink.importJSON(json, kind: .replaceRule, store: store)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.name, "净化")
    }

    func testRejectsAnEmptyDocument() {
        let store = LegadoStore(tables: MemoryTableStore())
        XCTAssertThrowsError(try DeepLink.importJSON("[]", kind: .bookSource, store: store)) { error in
            XCTAssertEqual(error as? DeepLinkError, .invalidData(.bookSource))
        }
    }

    // MARK: - Downloading

    func testDownloadsAndImportsThroughTheHttpClient() async throws {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        let client = StubHttpClient { request in
            HttpResponse(
                url: request.url,
                body: #"[{"bookSourceUrl":"https://a","bookSourceName":"下载的源"}]"#,
                code: 200
            )
        }
        let request = DeepLinkRequest(path: "/bookSource", host: "import", source: "https://example.com/s.json")
        let summary = try await DeepLink.importData(from: request, httpClient: client, store: store)
        XCTAssertEqual(summary.count, 1)
        XCTAssertEqual(summary.name, "下载的源")
        XCTAssertEqual(try store.allSources().count, 1)
    }

    func testTheRequestWithoutUserAgentMarkerSetsTheLiteralNullHeader() async throws {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        let recorder = StubHttpClient { request in
            HttpResponse(url: request.url, body: "[]", code: 200)
        }
        let request = DeepLinkRequest(
            path: "/bookSource",
            host: "import",
            source: "https://example.com/s.json" + DeepLink.requestWithoutUserAgent
        )
        _ = try? await DeepLink.importData(from: request, httpClient: recorder, store: store)
        let sent = recorder.requests.last
        XCTAssertEqual(sent?.headers["User-Agent"], "null")
        XCTAssertEqual(sent?.url, "https://example.com/s.json")
    }

    func testAFailedDownloadIsReported() async {
        let store = LegadoStore(tables: MemoryTableStore())
        let client = StubHttpClient { request in
            HttpResponse(url: request.url, body: "", code: 404)
        }
        let request = DeepLinkRequest(path: "/bookSource", host: "import", source: "https://example.com/s.json")
        do {
            _ = try await DeepLink.importData(from: request, httpClient: client, store: store)
            XCTFail("expected a failure")
        } catch {
            XCTAssertEqual(error as? DeepLinkError, .downloadFailed("HTTP 404"))
        }
    }
}
