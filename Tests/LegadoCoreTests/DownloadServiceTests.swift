//
//  DownloadServiceTests.swift
//  LegadoCoreTests
//
//  The generic download service — the port of upstream
//  `app/src/main/java/io/legado/app/service/DownloadService.kt`.
//
//

import XCTest
@testable import LegadoCore

/// A `FileDownloading` that writes a file and records the requests.
final class StubFileDownloader: FileDownloading, @unchecked Sendable {

    private let lock = NSLock()
    private var recorded: [DownloadRequest] = []
    private let handler: @Sendable (DownloadRequest, URL) throws -> Void

    init(handler: @escaping @Sendable (DownloadRequest, URL) throws -> Void) {
        self.handler = handler
    }

    var requests: [DownloadRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func download(
        _ request: DownloadRequest,
        to destination: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        lock.lock()
        recorded.append(request)
        lock.unlock()
        onProgress(0, 0)
        try handler(request, destination)
        onProgress(10, 10)
    }
}

final class DownloadServiceTests: XCTestCase {

    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("downloads-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
        super.tearDown()
    }

    // MARK: - The helper

    private func makeService(
        handler: @escaping @Sendable (DownloadRequest, URL) throws -> Void
    ) -> (DownloadService, StubFileDownloader) {
        let downloader = StubFileDownloader(handler: handler)
        let service = DownloadService(
            downloader: downloader,
            destinationDirectory: directory
        )
        return (service, downloader)
    }

    private func waitForFinish(
        _ service: DownloadService,
        id: Int,
        timeout: TimeInterval = 5
    ) -> DownloadInfo? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let info = service.item(id: id), info.status.isFinished {
                return info
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return service.item(id: id)
    }

    // MARK: - The download

    func testTheDownloadWritesTheFileAndFinishes() throws {
        let (service, downloader) = makeService { request, destination in
            try Data("内容".utf8).write(to: destination)
        }
        let identifier = try XCTUnwrap(
            service.start(DownloadRequest(url: "https://example.com/a.txt", fileName: "a.txt"))
        )
        let info = try XCTUnwrap(waitForFinish(service, id: identifier))
        XCTAssertEqual(info.status.stateText, "下载成功")
        XCTAssertEqual(downloader.requests.count, 1)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("a.txt"), encoding: .utf8), "内容")
    }

    func testTheDownloadIsReportedThroughTheChangeHandler() throws {
        let (service, _) = makeService { _, destination in
            try Data("ok".utf8).write(to: destination)
        }
        let states = LockedBox<[String]>([])
        service.setChangeHandler { info in
            states.append(info.status.stateText)
        }
        let identifier = try XCTUnwrap(
            service.start(DownloadRequest(url: "https://example.com/b.txt", fileName: "b.txt"))
        )
        _ = waitForFinish(service, id: identifier)
        XCTAssertTrue(states.value.contains("等待下载"))
        XCTAssertTrue(states.value.contains("下载中"))
        XCTAssertTrue(states.value.contains("下载成功"))
    }

    func testTheSameAddressIsNotDownloadedTwice() throws {
        let (service, downloader) = makeService { _, destination in
            Thread.sleep(forTimeInterval: 0.2)
            try Data("ok".utf8).write(to: destination)
        }
        let request = DownloadRequest(url: "https://example.com/c.txt", fileName: "c.txt")
        XCTAssertNotNil(service.start(request))
        // The upstream shows the toast "已在下载列表".
        XCTAssertNil(service.start(request))
        XCTAssertTrue(service.isDownloading(url: request.url))
        XCTAssertEqual(service.items.count, 1)
        _ = downloader
    }

    func testTheCancelMarksTheDownloadAsFailed() throws {
        let (service, _) = makeService { _, destination in
            Thread.sleep(forTimeInterval: 0.3)
            try Data("ok".utf8).write(to: destination)
        }
        let identifier = try XCTUnwrap(
            service.start(DownloadRequest(url: "https://example.com/d.txt", fileName: "d.txt"))
        )
        service.cancel(id: identifier)
        let info = try XCTUnwrap(service.item(id: identifier))
        XCTAssertEqual(info.status.stateText, "下载出错")
    }

    func testAFailedDownloadIsReported() throws {
        let (service, _) = makeService { _, _ in
            throw HttpError.status(code: 404, message: "not found")
        }
        let identifier = try XCTUnwrap(
            service.start(DownloadRequest(url: "https://example.com/e.txt", fileName: "e.txt"))
        )
        let info = try XCTUnwrap(waitForFinish(service, id: identifier))
        XCTAssertEqual(info.status.stateText, "下载出错")
        XCTAssertNil(service.fileURL(id: identifier))
    }

    func testTheFinishedDownloadsAreRemoved() throws {
        let (service, _) = makeService { _, destination in
            try Data("ok".utf8).write(to: destination)
        }
        let identifier = try XCTUnwrap(
            service.start(DownloadRequest(url: "https://example.com/f.txt", fileName: "f.txt"))
        )
        _ = waitForFinish(service, id: identifier)
        XCTAssertEqual(service.items.count, 1)
        service.removeFinished()
        XCTAssertTrue(service.items.isEmpty)
    }

    func testTheFileOfAFinishedDownloadIsFound() throws {
        let (service, _) = makeService { _, destination in
            try Data("ok".utf8).write(to: destination)
        }
        let identifier = try XCTUnwrap(
            service.start(DownloadRequest(url: "https://example.com/g.txt", fileName: "g.txt"))
        )
        _ = waitForFinish(service, id: identifier)
        let file = try XCTUnwrap(service.fileURL(id: identifier))
        XCTAssertEqual(file.lastPathComponent, "g.txt")
    }

    // MARK: - The names and the states

    func testTheFileNameComesFromThePathOfTheAddress() {
        XCTAssertEqual(
            DownloadRequest.fileName(for: "https://example.com/dir/book.pdf"),
            "book.pdf"
        )
        // The upstream guesses the name with `URLUtil.guessFileName` — the last
        // component of the path.
        XCTAssertEqual(
            DownloadRequest.fileName(for: "https://example.com/dir/"),
            "dir"
        )
        // An address without a path has no name.
        XCTAssertEqual(
            DownloadRequest.fileName(for: "https://example.com"),
            "download"
        )
    }

    func testTheStateTextsFollowTheUpstream() {
        XCTAssertEqual(DownloadStatus.waiting.stateText, "等待下载")
        XCTAssertEqual(DownloadStatus.running(received: 1, total: 2).stateText, "下载中")
        XCTAssertEqual(DownloadStatus.finished(URL(string: "file:///a")!).stateText, "下载成功")
        XCTAssertEqual(DownloadStatus.failed("x").stateText, "下载出错")
    }

    func testTheTitleCarriesTheNameAndTheState() {
        let info = DownloadInfo(
            id: 0,
            request: DownloadRequest(url: "https://example.com/h.txt", fileName: "h.txt"),
            status: .running(received: 1, total: 2),
            destination: URL(fileURLWithPath: "/tmp/h.txt")
        )
        XCTAssertEqual(info.title, "h.txt 下载中")
    }

    func testTheProgressIsTheRatioOfTheBytes() {
        XCTAssertEqual(DownloadStatus.running(received: 5, total: 10).progress, 0.5)
        XCTAssertNil(DownloadStatus.running(received: 0, total: 0).progress)
        XCTAssertEqual(DownloadStatus.finished(URL(string: "file:///a")!).progress, 1)
    }
}

/// A box with a lock — the helper of the tests that collect the states.
final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ element: Value.Element) where Value: RangeReplaceableCollection {
        lock.lock()
        defer { lock.unlock() }
        storage.append(element)
    }
}
