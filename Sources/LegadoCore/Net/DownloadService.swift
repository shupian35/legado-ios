//
//  DownloadService.swift
//  LegadoCore
//
//  The generic file downloader — the port of upstream
//  `app/src/main/java/io/legado/app/service/DownloadService.kt` and
//  `app/src/main/java/io/legado/app/model/Download.kt`.
//
//  Upstream the service hands the address to the Android `DownloadManager`,
//  which writes the file into the public Download folder and reports the
//  progress through a notification that carries a 取消 action. iOS has no
//  public Download folder an app may write to, so the port writes into the
//  documents directory of the app (`downloads`) and lets the user export the
//  file with the share sheet.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/service/DownloadService.kt:1-279
//  app/src/main/java/io/legado/app/model/Download.kt
//  app/src/main/java/io/legado/app/constant/NotificationId.kt
//

import Foundation

#if canImport(FoundationNetworking)
// `URLSession` lives in FoundationNetworking on Linux.
import FoundationNetworking
#endif

// MARK: - The request

/// A file the user wants to download — upstream `DownloadService.startDownload`.
public struct DownloadRequest: Sendable, Equatable {

    /// The address of the file.
    public var url: String
    /// The name the file is saved under.
    public var fileName: String
    /// The headers of the request (the cookies of the app, the user agent).
    public var headers: [String: String]

    public init(url: String, fileName: String, headers: [String: String] = [:]) {
        self.url = url
        self.fileName = fileName
        self.headers = headers
    }

    /// The name of the file for an address — upstream `DownloadService.startDownload`
    /// uses the name of the path of the address.
    public static func fileName(for url: String, fallback: String = "download") -> String {
        guard let parsed = URL(string: url) else { return fallback }
        // The name of the last component of the path — a path that ends with a
        // slash has no name.
        var path = parsed.path
        while path.hasSuffix("/") { path.removeLast() }
        let name = (path as NSString).lastPathComponent
        if name.isEmpty { return fallback }
        // The characters that are not allowed in a file name.
        let cleaned = name.components(separatedBy: CharacterSet(charactersIn: "\\/:*?\"<>|"))
            .joined()
        return cleaned.isEmpty ? fallback : cleaned
    }
}

// MARK: - The state

/// The state of a download — upstream `DownloadService.queryState`.
public enum DownloadStatus: Sendable, Equatable {

    /// The download waits for its turn.
    case waiting
    /// The download runs — the received and the expected number of bytes.
    case running(received: Int64, total: Int64)
    /// The download finished — the file is at the given path.
    case finished(URL)
    /// The download failed.
    case failed(String)

    /// The user visible state — upstream `DownloadService.queryState`:
    /// 暂停 / 等待下载 / 下载中 / 下载成功 / 下载出错 / 未知状态.
    public var stateText: String {
        switch self {
        case .waiting: return "等待下载"
        case .running: return "下载中"
        case .finished: return "下载成功"
        case .failed: return "下载出错"
        }
    }

    /// Whether the download is over.
    public var isFinished: Bool {
        switch self {
        case .finished, .failed: return true
        case .waiting, .running: return false
        }
    }

    /// The progress in `0...1` — `nil` when the size of the file is unknown.
    public var progress: Double? {
        switch self {
        case .running(let received, let total):
            guard total > 0 else { return nil }
            return min(max(Double(received) / Double(total), 0), 1)
        case .finished: return 1
        case .waiting, .failed: return nil
        }
    }
}

/// A download of the service — upstream `DownloadService.DownloadInfo`.
public struct DownloadInfo: Identifiable, Sendable, Equatable {

    /// The identifier of the download.
    public let id: Int
    /// The request of the download.
    public var request: DownloadRequest
    /// The state of the download.
    public var status: DownloadStatus
    /// Where the file is written.
    public var destination: URL
    /// When the download started.
    public var startTime: Date

    public init(
        id: Int,
        request: DownloadRequest,
        status: DownloadStatus,
        destination: URL,
        startTime: Date = Date()
    ) {
        self.id = id
        self.request = request
        self.status = status
        self.destination = destination
        self.startTime = startTime
    }

    /// The title of the notification — upstream `DownloadService.queryState`
    /// builds "<fileName> <status>".
    public var title: String {
        "\(request.fileName) \(status.stateText)"
    }
}

// MARK: - The transport

/// The transport of the downloads.
public protocol FileDownloading: Sendable {

    /// Downloads the request into the destination file.
    ///
    /// The progress handler is called with the received and the expected
    /// number of bytes; the expected size is zero when the server does not
    /// announce it.
    func download(
        _ request: DownloadRequest,
        to destination: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws
}

/// The `URLSession` implementation of `FileDownloading`.
///
/// The port downloads the file with the same asynchronous API the HTTP client
/// uses (upstream the `DownloadManager` streams the file, but the platform
/// does not offer a comparable API on iOS), so the progress is reported when
/// the download starts and when it ends.
public struct URLSessionFileDownloader: FileDownloading {

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func download(
        _ request: DownloadRequest,
        to destination: URL,
        onProgress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws {
        guard let url = URL(string: request.url), url.scheme != nil else {
            throw HttpError.invalidURL(request.url)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        onProgress(0, 0)
        let (data, response) = try await session.data(for: urlRequest)
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw HttpError.status(
                code: httpResponse.statusCode,
                message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            )
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        onProgress(Int64(data.count), Int64(data.count))
    }
}

// MARK: - The service

/// The generic download service — upstream `service/DownloadService.kt`.
///
/// The upstream is an Android service that owns the `DownloadManager`; the
/// port is a small queue that writes the files itself and reports every
/// change through the change handler, so that the UI can post the
/// notifications of the upstream.
public final class DownloadService: @unchecked Sendable {

    /// The handler of the changes — upstream the service posts the
    /// notifications itself.
    public typealias ChangeHandler = @Sendable (DownloadInfo) -> Void

    /// The errors of the service.
    public enum ServiceError: Error, Equatable {
        /// The address is already in the list — upstream the toast "已在下载列表".
        case alreadyDownloading(String)
        /// The address is not valid.
        case invalidURL(String)
    }

    private let lock = NSLock()
    private var storage: [Int: DownloadInfo] = [:]
    private var tasks: [Int: Task<Void, Never>] = [:]
    /// The downloads the user cancelled — their state is not changed any more.
    private var cancelled: Set<Int> = []
    private var nextIdentifier = 0
    private let downloader: FileDownloading
    private let destinationDirectory: URL
    private let fileManager: FileManager
    private var handler: ChangeHandler?

    public init(
        downloader: FileDownloading,
        destinationDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.downloader = downloader
        self.destinationDirectory = destinationDirectory
        self.fileManager = fileManager
    }

    /// The directory the files are written into.
    public var directory: URL { destinationDirectory }

    /// Sets the handler of the changes.
    public func setChangeHandler(_ handler: ChangeHandler?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    /// The downloads, oldest first.
    public var items: [DownloadInfo] {
        lock.lock()
        defer { lock.unlock() }
        return storage.values.sorted { $0.id < $1.id }
    }

    /// The download with the given identifier.
    public func item(id: Int) -> DownloadInfo? {
        lock.lock()
        defer { lock.unlock() }
        return storage[id]
    }

    /// Whether the address is already being downloaded — upstream the toast
    /// "已在下载列表".
    public func isDownloading(url: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage.values.contains { $0.request.url == url && !$0.status.isFinished }
    }

    /// Starts a download — upstream `DownloadService.startDownload`.
    ///
    /// - Returns: the identifier of the download, or `nil` when the address is
    ///   already in the list.
    @discardableResult
    public func start(_ request: DownloadRequest) -> Int? {
        guard !request.url.isEmpty else { return nil }
        if isDownloading(url: request.url) { return nil }
        let identifier = nextIdentifier
        nextIdentifier += 1
        let destination = destinationDirectory.appendingPathComponent(request.fileName)
        let info = DownloadInfo(
            id: identifier,
            request: request,
            status: .waiting,
            destination: destination
        )
        lock.lock()
        storage[identifier] = info
        lock.unlock()
        notify(info)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(identifier: identifier)
        }
        lock.lock()
        tasks[identifier] = task
        lock.unlock()
        return identifier
    }

    /// Cancels a download — upstream the delete intent of the notification
    /// (`IntentAction.stop`).
    public func cancel(id: Int) {
        lock.lock()
        let task = tasks.removeValue(forKey: id)
        let info = storage[id]
        cancelled.insert(id)
        lock.unlock()
        task?.cancel()
        guard let info else { return }
        update(id: id, force: true) { item in
            item.status = .failed("已取消")
        }
        try? fileManager.removeItem(at: info.destination)
    }

    /// Removes the finished downloads from the list — upstream
    /// `DownloadService.deleteAllDownload`.
    public func removeFinished() {
        lock.lock()
        let finished = storage.values.filter { $0.status.isFinished }.map { $0.id }
        for identifier in finished {
            storage.removeValue(forKey: identifier)
            tasks.removeValue(forKey: identifier)
        }
        lock.unlock()
    }

    /// The file of a finished download.
    public func fileURL(id: Int) -> URL? {
        lock.lock()
        defer { lock.unlock() }
        guard case .finished(let url)? = storage[id]?.status else { return nil }
        return url
    }

    // MARK: - The work

    private func run(identifier: Int) async {
        guard let info = item(id: identifier) else { return }
        update(id: identifier) { item in
            item.status = .running(received: 0, total: 0)
        }
        do {
            let request = info.request
            let destination = info.destination
            try await downloader.download(request, to: destination) { [weak self] received, total in
                guard let self else { return }
                self.update(id: identifier) { item in
                    item.status = .running(received: received, total: total)
                }
            }
            update(id: identifier) { item in
                item.status = .finished(destination)
            }
        } catch is CancellationError {
            update(id: identifier) { item in
                item.status = .failed("已取消")
            }
        } catch {
            update(id: identifier) { item in
                item.status = .failed("\(error)")
            }
        }
        forgetTask(identifier)
    }

    private func forgetTask(_ identifier: Int) {
        lock.lock()
        tasks.removeValue(forKey: identifier)
        lock.unlock()
    }

    private func update(id: Int, force: Bool = false, _ change: (inout DownloadInfo) -> Void) {
        lock.lock()
        guard var info = storage[id] else {
            lock.unlock()
            return
        }
        // A cancelled download keeps its state — the progress of the task that
        // was stopped must not change it any more.
        if !force, cancelled.contains(id) {
            lock.unlock()
            return
        }
        change(&info)
        storage[id] = info
        let handler = self.handler
        lock.unlock()
        if let handler { handler(info) }
    }

    private func notify(_ info: DownloadInfo) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        if let handler { handler(info) }
    }
}
