//
//  ScriptFileCacheTests.swift
//  LegadoCoreTests
//
//  The file downloads of the rule scripts — the port of upstream
//  `app/src/main/java/io/legado/app/help/JsExtensions.kt`:
//  `downloadFile(url)` and `cacheFile(urlStr, saveTime)`.
//
//

import XCTest
@testable import LegadoCore

final class ScriptFileCacheTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("script-cache-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    private func makeClient(_ body: String = "hello") -> (HttpScriptClient, StubHttpClient) {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: body)
        }
        return (HttpScriptClient(httpClient: stub), stub)
    }

    private func makeSandbox() -> SandboxFileSandbox {
        SandboxFileSandbox(baseDirectory: directory.path)
    }

    // MARK: - The names

    func testTheNameIsTheMd5OfTheAddressAndTheSuffix() {
        let name = ScriptFileCache.downloadFileName(for: "https://example.com/dir/book.txt")
        XCTAssertEqual(name, "\(ScriptDigest.md5Encode16("https://example.com/dir/book.txt")).txt")
    }

    func testTheTypeOfTheOptionBlockWinsOverTheSuffix() {
        // The option block of the upstream is a JSON object after the first comma.
        let url = "https://example.com/dir/book.txt,{\"type\":\"pdf\"}"
        let name = ScriptFileCache.downloadFileName(for: url)
        XCTAssertTrue(name.hasSuffix(".pdf"))
    }

    // MARK: - The download

    func testTheDownloadWritesTheFileIntoTheSandbox() throws {
        let (client, stub) = makeClient("你好")
        let sandbox = makeSandbox()
        let cache = ScriptFileCache()
        let path = try cache.download(
            url: "https://example.com/dir/book.txt",
            client: client,
            files: sandbox
        )
        // The upstream returns the path relative to the cache directory.
        XCTAssertTrue(path.hasPrefix("/"))
        XCTAssertTrue(path.hasSuffix(".txt"))
        XCTAssertEqual(
            try sandbox.readScriptFile(String(path.dropFirst())),
            "你好"
        )
        XCTAssertEqual(stub.requests.count, 1)
    }

    func testTheDownloadSendsTheHeaders() throws {
        let (client, stub) = makeClient()
        let cache = ScriptFileCache()
        _ = try cache.download(
            url: "https://example.com/a.txt",
            client: client,
            files: makeSandbox(),
            headers: ["User-Agent": "Legado/1.0"]
        )
        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.headers["User-Agent"], "Legado/1.0")
    }

    // MARK: - The cache

    func testTheCacheReturnsTheTextOfTheFile() throws {
        let (client, stub) = makeClient("缓存的内容")
        let cache = ScriptFileCache()
        let text = try cache.cacheFile(
            url: "https://example.com/a.txt",
            saveTime: 60,
            client: client,
            files: makeSandbox()
        )
        XCTAssertEqual(text, "缓存的内容")
        XCTAssertEqual(stub.requests.count, 1)
    }

    func testTheSecondCallIsAnsweredFromTheCache() throws {
        let (client, stub) = makeClient("缓存的内容")
        let cache = ScriptFileCache()
        let sandbox = makeSandbox()
        _ = try cache.cacheFile(
            url: "https://example.com/a.txt",
            saveTime: 60,
            client: client,
            files: sandbox
        )
        let text = try cache.cacheFile(
            url: "https://example.com/a.txt",
            saveTime: 60,
            client: client,
            files: sandbox
        )
        XCTAssertEqual(text, "缓存的内容")
        // The file is downloaded only once.
        XCTAssertEqual(stub.requests.count, 1)
    }

    func testAnExpiredEntryIsDownloadedAgain() throws {
        let (client, stub) = makeClient("缓存的内容")
        let cache = ScriptFileCache()
        let sandbox = makeSandbox()
        _ = try cache.cacheFile(
            url: "https://example.com/a.txt",
            saveTime: 60,
            client: client,
            files: sandbox
        )
        // The lifetime is over.
        cache.removeAll()
        _ = try cache.cacheFile(
            url: "https://example.com/a.txt",
            saveTime: 60,
            client: client,
            files: sandbox
        )
        XCTAssertEqual(stub.requests.count, 2)
    }
}
