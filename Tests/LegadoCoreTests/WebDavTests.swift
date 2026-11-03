import XCTest

@testable import LegadoCore

/// An `HttpClient` that records requests and answers from a closure.
final class StubHttpClient: HttpClient, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HttpRequest] = []
    private let handler: @Sendable (HttpRequest) -> HttpResponse

    init(handler: @escaping @Sendable (HttpRequest) -> HttpResponse) {
        self.handler = handler
    }

    var requests: [HttpRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        lock.lock()
        recorded.append(request)
        lock.unlock()
        return handler(request)
    }
}

final class WebDavTests: XCTestCase {

    private let base = "https://dav.example.com/dav/"

    private func makeClient(handler: @escaping @Sendable (HttpRequest) -> HttpResponse) -> (WebDavClient, StubHttpClient) {
        let stub = StubHttpClient(handler: handler)
        let configuration = WebDavConfiguration(
            url: base,
            username: "user",
            password: "pass"
        )
        return (WebDavClient(configuration: configuration, httpClient: stub), stub)
    }

    // MARK: - Authentication

    func testSendsBasicAuthorization() async throws {
        let (client, stub) = makeClient { request in
            HttpResponse(url: request.url, body: "", code: 207)
        }
        _ = try await client.list("")
        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.headers["Authorization"], "Basic dXNlcjpwYXNz")
        XCTAssertEqual(request.method, "PROPFIND")
        XCTAssertEqual(request.headers["Depth"], "1")
    }

    func testUnauthorizedIsReported() async throws {
        let (client, _) = makeClient { request in
            HttpResponse(url: request.url, body: "denied", code: 401)
        }
        do {
            try await client.checkAuthorization()
            XCTFail("expected unauthorized")
        } catch let error as WebDavError {
            XCTAssertEqual(error, .unauthorized)
        }
    }

    // MARK: - PROPFIND

    func testParsesMultistatusWithNamespacePrefix() async throws {
        let xml = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:">
          <d:response>
            <d:href>/dav/</d:href>
            <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/backup2023-11-14.zip</d:href>
            <d:propstat><d:prop>
              <d:getcontentlength>2048</d:getcontentlength>
              <d:getlastmodified>Mon, 14 Nov 2023 10:00:00 GMT</d:getlastmodified>
              <d:resourcetype/>
            </d:prop></d:propstat>
          </d:response>
          <d:response>
            <d:href>/dav/bookProgress/</d:href>
            <d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop></d:propstat>
          </d:response>
        </d:multistatus>
        """
        let (client, _) = makeClient { request in
            HttpResponse(url: request.url, body: xml, code: 207)
        }
        let files = try await client.list("")
        XCTAssertEqual(files.count, 2, "the collection itself is dropped")
        XCTAssertEqual(files[0].name, "backup2023-11-14.zip")
        XCTAssertEqual(files[0].path, "backup2023-11-14.zip")
        XCTAssertFalse(files[0].isDirectory)
        XCTAssertEqual(files[0].size, 2048)
        XCTAssertNotNil(files[0].lastModified)
        XCTAssertTrue(files[1].isDirectory)
        XCTAssertEqual(files[1].name, "bookProgress")
    }

    func testParsesMultistatusWithoutNamespacePrefix() async throws {
        let xml = """
        <multistatus xmlns="DAV:">
          <response>
            <href>https://dav.example.com/dav/backup.zip</href>
            <propstat><prop><resourcetype/></prop></propstat>
          </response>
        </multistatus>
        """
        let (client, _) = makeClient { request in
            HttpResponse(url: request.url, body: xml, code: 207)
        }
        let files = try await client.list("")
        XCTAssertEqual(files.map(\.name), ["backup.zip"])
    }

    // MARK: - Upload / download

    func testUploadsWithPut() async throws {
        let (client, stub) = makeClient { request in
            HttpResponse(url: request.url, code: 201, message: "Created")
        }
        try await client.upload(Data("hello".utf8), to: "bookProgress/书_作者.json")
        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.body, Data("hello".utf8))
        XCTAssertEqual(request.headers["Content-Type"], "application/octet-stream")
        XCTAssertTrue(request.url.hasSuffix("/dav/bookProgress/%E4%B9%A6_%E4%BD%9C%E8%80%85.json"),
                      "non-ASCII path components must be percent-encoded, got \(request.url)")
    }

    func testDownloadsFile() async throws {
        let (client, _) = makeClient { request in
            HttpResponse(url: request.url, body: "content", data: Data("content".utf8), code: 200)
        }
        let data = try await client.download("backup.zip")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "content")
    }

    func testNotFoundIsReported() async throws {
        let (client, _) = makeClient { request in
            HttpResponse(url: request.url, code: 404)
        }
        do {
            _ = try await client.download("missing.zip")
            XCTFail("expected notFound")
        } catch let error as WebDavError {
            guard case .notFound = error else { return XCTFail("wrong error \(error)") }
        }
    }

    func testDeleteIgnoresMissingFile() async throws {
        let (client, _) = makeClient { request in
            HttpResponse(url: request.url, code: 404)
        }
        try await client.delete("gone.zip")
    }

    // MARK: - Service

    func testBackupNamesAreFilteredAndSorted() async throws {
        let xml = """
        <d:multistatus xmlns:d="DAV:">
          <d:response><d:href>/dav/backup2023-11-13.zip</d:href>
            <d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
          <d:response><d:href>/dav/backup2023-11-14.zip</d:href>
            <d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
          <d:response><d:href>/dav/notes.txt</d:href>
            <d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response>
        </d:multistatus>
        """
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: xml, code: 207)
        }
        let service = WebDavService(
            configuration: WebDavConfiguration(url: base, username: "u", password: "p"),
            httpClient: stub
        )
        let names = try await service.backupNames()
        XCTAssertEqual(names.map(\.name), ["backup2023-11-14.zip", "backup2023-11-13.zip"])
    }

    func testUploadBackupWritesAZipWithTheArchiveName() async throws {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, code: 201)
        }
        let service = WebDavService(
            configuration: WebDavConfiguration(url: base, username: "u", password: "p"),
            httpClient: stub
        )
        let archive = BackupArchive(
            fileName: "backup2023-11-14.zip",
            files: [BackupFile(name: "bookshelf.json", string: "[]")]
        )
        try await service.uploadBackup(archive)
        let request = try XCTUnwrap(stub.requests.first)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertTrue(request.url.hasSuffix("/dav/backup2023-11-14.zip"))
        let unzipped = try ZipArchive(data: XCTUnwrap(request.body))
        XCTAssertTrue(unzipped.contains("bookshelf.json"))
    }

    func testProgressRoundTrip() async throws {
        let progress = BookProgress(
            name: "书一",
            author: "作者",
            durChapterIndex: 7,
            durChapterPos: 123,
            durChapterTime: 1_700_000_000,
            durChapterTitle: "第七章"
        )
        let payload = try JSONEncoder().encode(progress)
        let stub = StubHttpClient { request in
            if request.method == "PUT" {
                return HttpResponse(url: request.url, code: 201)
            }
            return HttpResponse(url: request.url, body: String(decoding: payload, as: UTF8.self), data: payload, code: 200)
        }
        let service = WebDavService(
            configuration: WebDavConfiguration(url: base, username: "u", password: "p"),
            httpClient: stub
        )
        try await service.uploadProgress(progress)
        let put = try XCTUnwrap(stub.requests.first)
        XCTAssertTrue(put.url.hasSuffix("/dav/bookProgress/%E4%B9%A6%E4%B8%80_%E4%BD%9C%E8%80%85.json"))

        let fetched = try await service.downloadProgress(fileName: progress.fileName)
        XCTAssertEqual(fetched, progress)
    }

    // MARK: - Adoption rule

    func testProgressIsAdoptedOnlyWhenItIsFurther() {
        let local = BookProgress(
            name: "书", author: "作者",
            durChapterIndex: 3, durChapterPos: 100, durChapterTime: 1000, durChapterTitle: nil
        )
        var remote = local
        remote.durChapterIndex = 4
        XCTAssertTrue(WebDavService.shouldAdopt(remote: remote, local: local))

        remote = local
        remote.durChapterIndex = 2
        XCTAssertFalse(WebDavService.shouldAdopt(remote: remote, local: local), "an earlier chapter must not win")

        remote = local
        remote.durChapterPos = 200
        XCTAssertTrue(WebDavService.shouldAdopt(remote: remote, local: local))

        remote = local
        remote.durChapterPos = 50
        XCTAssertFalse(WebDavService.shouldAdopt(remote: remote, local: local))

        XCTAssertTrue(WebDavService.shouldAdopt(remote: local, local: nil))
    }

    func testSamePositionFallsBackToTime() {
        let local = BookProgress(
            name: "书", author: "作者",
            durChapterIndex: 3, durChapterPos: 100, durChapterTime: 1000, durChapterTitle: nil
        )
        var remote = local
        remote.durChapterTime = 2000
        XCTAssertTrue(WebDavService.shouldAdopt(remote: remote, local: local))
        remote.durChapterTime = 500
        XCTAssertFalse(WebDavService.shouldAdopt(remote: remote, local: local))
    }
}
