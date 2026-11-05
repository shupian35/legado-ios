import Foundation
import LegadoCore
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

/// `SOCK_STREAM` is a plain `Int32` constant on Darwin but a `__socket_type`
/// enum on Glibc, so the raw value has to be taken on one platform only.
private let legadoStreamSocketType: Int32 = {
    #if canImport(Darwin)
    return SOCK_STREAM
    #else
    return Int32(SOCK_STREAM.rawValue)
    #endif
}()

/// The local web service — the port of `web/HttpServer.kt` (NanoHTTPD) and
/// `service/WebService.kt` (the Android foreground service that hosts it).
///
/// The Android app exposes the bookshelf over HTTP on `AppConfig.webPort`
/// (default 1122, clamped to 1024…65530) and a WebSocket API on `port + 1`.
/// The iOS port does the same, with three differences that matter for safety:
///
/// * a bearer token is required when one is configured;
/// * the listener can be bound to loopback only (`bindAddress`);
/// * `Origin` is never reflected — only the single configured origin is
///   allowed (see `LegadoAPIConfiguration.allowedOrigin`).
public final class LegadoServer: @unchecked Sendable {

    public struct Status: Equatable, Sendable {
        public let isRunning: Bool
        public let httpPort: Int
        public let webSocketPort: Int
        public let addresses: [String]
    }

    private let routes: [LegadoAPI.Route]
    private let configuration: LegadoAPIConfiguration
    private let fallback: @Sendable (HTTPRequestHead) async -> HTTPResponseMessage
    private let webSocketHandler: LegadoWebSocketHandler?
    private let bindAddress: String

    private var listener: Int32 = -1
    private var acceptThread: Thread?
    /// The second listener for the WebSocket API.
    ///
    /// The upstream web client (`modules/web/src/api/index.ts:80-96`) uses
    /// the HTTP port **+ 1** for the WebSocket, so the port listens there as
    /// well to stay compatible with the upstream web UI.
    private var webSocketListener: Int32 = -1
    private var webSocketAcceptThread: Thread?
    private var isRunning = false
    private let lock = NSLock()

    /// - Parameters:
    ///   - bindAddress: `"0.0.0.0"` (all interfaces, like Android) or
    ///     `"127.0.0.1"` (loopback only).
    public init(
        configuration: LegadoAPIConfiguration,
        routes: [LegadoAPI.Route]? = nil,
        bindAddress: String = "0.0.0.0",
        fallback: (@Sendable (HTTPRequestHead) async -> HTTPResponseMessage)? = nil,
        webSocketHandler: LegadoWebSocketHandler? = nil
    ) {
        self.configuration = configuration
        self.routes = routes ?? LegadoAPI.routes()
        self.bindAddress = bindAddress
        self.fallback = fallback ?? { request in
            // The web bookshelf (the port of the upstream Vue client).
            if let asset = WebAssets.response(for: request.path) {
                return asset
            }
            return .error("not found: \(request.path)", code: 404)
        }
        self.webSocketHandler = webSocketHandler
        // The web client needs the token to talk to the API.
        WebAssets.accessToken = configuration.token
    }

    /// The port upstream uses when the configured one is out of range.
    public static let defaultPort = 1122

    /// Clamps a configured port the way `WebService.getPort()` does.
    public static func normalizedPort(_ port: Int) -> Int {
        (1024...65_530).contains(port) ? port : defaultPort
    }

    // MARK: - Lifecycle

    /// Starts listening. Returns the bound port, which may differ from the
    /// configured one when it was out of range.
    @discardableResult
    public func start() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        guard !isRunning else { return configuration.port }
        let port = LegadoServer.normalizedPort(configuration.port)

        let socketFD = socket(AF_INET, legadoStreamSocketType, 0)
        guard socketFD >= 0 else { throw ServerError.socket(String(cString: strerror(errno))) }
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        address.sin_addr.s_addr = bindAddress == "127.0.0.1" ? INADDR_LOOPBACK.bigEndian : INADDR_ANY.bigEndian

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(socketFD)
            throw ServerError.bind("port \(port): \(String(cString: strerror(errno)))")
        }
        guard listen(socketFD, 16) == 0 else {
            close(socketFD)
            throw ServerError.bind("listen: \(String(cString: strerror(errno)))")
        }

        listener = socketFD
        isRunning = true
        let thread = Thread { [weak self] in self?.acceptLoop() }
        thread.name = "LegadoServer.accept"
        thread.start()
        acceptThread = thread
        startWebSocketListener(port: port)
        return port
    }

    /// Opens the second listener on `port + 1` for the WebSocket API.
    ///
    /// A failure is not fatal: the HTTP port still accepts the WebSocket
    /// upgrade, so the API keeps working when the port is taken.
    private func startWebSocketListener(port: Int) {
        guard webSocketHandler != nil else { return }
        let socketFD = socket(AF_INET, legadoStreamSocketType, 0)
        guard socketFD >= 0 else { return }
        var reuse: Int32 = 1
        setsockopt(socketFD, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port + 1).bigEndian)
        address.sin_addr.s_addr = bindAddress == "127.0.0.1" ? INADDR_LOOPBACK.bigEndian : INADDR_ANY.bigEndian

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketFD, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            close(socketFD)
            return
        }
        guard listen(socketFD, 16) == 0 else {
            close(socketFD)
            return
        }
        webSocketListener = socketFD
        let thread = Thread { [weak self] in self?.webSocketAcceptLoop() }
        thread.name = "LegadoServer.webSocket"
        thread.start()
        webSocketAcceptThread = thread
    }

    /// The accept loop of the WebSocket port.
    private func webSocketAcceptLoop() {
        while true {
            lock.lock()
            let fd = webSocketListener
            let running = isRunning
            lock.unlock()
            guard running, fd >= 0 else { return }

            var clientAddress = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &clientAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(fd, $0, &length)
                }
            }
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            let thread = Thread { [weak self] in self?.serveWebSocketConnection(client) }
            thread.name = "LegadoServer.webSocket.client"
            thread.start()
        }
    }

    /// Reads the handshake of a WebSocket connection on the second port.
    private func serveWebSocketConnection(_ client: Int32) {
        defer { close(client) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            guard let (request, consumed) = try? HTTPParser.parseRequest(buffer) else {
                let read = recv(client, &chunk, chunk.count, 0)
                if read <= 0 { return }
                buffer.append(contentsOf: chunk[0..<read])
                continue
            }
            buffer.removeFirst(consumed)
            guard WebSocket.isUpgradeRequest(request) else { return }
            writeAll(client, WebSocket.handshakeResponse(for: request).serialized(keepAlive: true))
            serveWebSocket(client, request: request, initial: buffer)
            return
        }
    }

    public func stop() {
        lock.lock()
        defer { lock.unlock() }
        guard isRunning else { return }
        isRunning = false
        if listener >= 0 {
            shutdown(listener, Int32(SHUT_RDWR))
            close(listener)
            listener = -1
        }
        if webSocketListener >= 0 {
            shutdown(webSocketListener, Int32(SHUT_RDWR))
            close(webSocketListener)
            webSocketListener = -1
        }
        acceptThread = nil
        webSocketAcceptThread = nil
    }

    public var status: Status {
        lock.lock()
        defer { lock.unlock() }
        let port = LegadoServer.normalizedPort(configuration.port)
        return Status(
            isRunning: isRunning,
            httpPort: port,
            webSocketPort: port + 1,
            addresses: isRunning ? localAddresses(port: port) : []
        )
    }

    // MARK: - Accept loop

    private func acceptLoop() {
        while true {
            lock.lock()
            let fd = listener
            let running = isRunning
            lock.unlock()
            guard running, fd >= 0 else { return }

            var clientAddress = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let client = withUnsafeMutablePointer(to: &clientAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    accept(fd, $0, &length)
                }
            }
            if client < 0 {
                if errno == EINTR { continue }
                return
            }
            let thread = Thread { [weak self] in self?.serve(client) }
            thread.name = "LegadoServer.client"
            thread.start()
        }
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 8192)
        while true {
            let read = recv(client, &chunk, chunk.count, 0)
            if read <= 0 { return }
            buffer.append(contentsOf: chunk[0..<read])

            // A WebSocket upgrade takes over the connection.
            if let (request, _) = try? HTTPParser.parseRequest(buffer),
               WebSocket.isUpgradeRequest(request) {
                writeAll(client, WebSocket.handshakeResponse(for: request).serialized(keepAlive: true))
                serveWebSocket(client, request: request, initial: buffer)
                return
            }

            while true {
                guard let (request, consumed) = try? HTTPParser.parseRequest(buffer) else { break }
                buffer.removeFirst(consumed)
                if request.path == "/" && buffer.isEmpty && request.headers.isEmpty { break }
                let response = respond(to: request)
                writeAll(client, response.serialized(keepAlive: true))
                if request.header("Connection")?.lowercased() == "close" { return }
            }
        }
    }

    private func serveWebSocket(_ client: Int32, request: HTTPRequestHead, initial: Data) {
        guard let handler = webSocketHandler else { return }
        var chunk = [UInt8](repeating: 0, count: 8192)
        var pending = Data()
        let state = WebSocketSessionState()
        startWebSocketHeartbeat(client, state: state)
        while true {
            let read = recv(client, &chunk, chunk.count, 0)
            if read <= 0 { break }
            pending.append(contentsOf: chunk[0..<read])
            while true {
                let decoded: (frame: WebSocket.Frame, consumed: Int)?
                do {
                    decoded = try WebSocket.decode(pending)
                } catch {
                    state.isFinished = true
                    return
                }
                guard let decoded else { break }
                pending.removeFirst(decoded.consumed)
                switch decoded.frame.opcode {
                case .close:
                    writeAll(client, WebSocket.encode(.init(opcode: .close)))
                    state.isFinished = true
                    return
                case .ping:
                    writeAll(client, WebSocket.encode(.init(opcode: .pong, payload: decoded.frame.payload)))
                case .text, .binary:
                    let path = request.path
                    let message = decoded.frame.text
                    let client = client
                    let send: @Sendable (LegadoWebSocketOutgoing) -> Void = { outgoing in
                        switch outgoing {
                        case .text(let text):
                            self.writeAll(client, WebSocket.textFrame(text))
                        case .ping:
                            self.writeAll(client, WebSocket.encode(.init(opcode: .ping, payload: Data("ping".utf8))))
                        case .close:
                            self.writeAll(client, WebSocket.encode(.init(opcode: .close)))
                            state.isClosed = true
                        }
                    }
                    runAsync { await handler(path, message, send) }
                    if state.isClosed { state.isFinished = true; return }
                case .continuation, .pong:
                    continue
                }
            }
        }
        state.isFinished = true
    }

    /// Pings the client every 30 seconds while the socket is open.
    ///
    /// Upstream `BookSearchWebSocket.onOpen`:
    /// `while (isOpen) { ping("ping".toByteArray()); delay(30000) }`.
    private func startWebSocketHeartbeat(_ client: Int32, state: WebSocketSessionState) {
        let thread = Thread { [weak self] in
            while !state.isFinished {
                Thread.sleep(forTimeInterval: 30)
                if state.isFinished || state.isClosed { break }
                self?.writeAll(client, WebSocket.encode(.init(opcode: .ping, payload: Data("ping".utf8))))
            }
        }
        thread.name = "LegadoServer.webSocket.ping"
        thread.start()
    }

    private func writeAll(_ fd: Int32, _ data: Data) {
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let written = send(fd, base.advanced(by: sent), data.count - sent, 0)
                if written <= 0 { return }
                sent += written
            }
        }
    }

    // MARK: - Dispatch

    /// Routes a request. Exposed for tests so the API can be exercised without
    /// opening a socket.
    public func respond(to request: HTTPRequestHead) -> HTTPResponseMessage {
        let method = request.method.uppercased()
        let path = request.path
        for route in routes where route.method == method && route.path == path {
            let context = apiContext
            return runAsync { await route.handler(request, context) }
                ?? .error("handler produced no response", code: 500)
        }
        // HEAD is optional; answer it from GET so the web UI's probes work.
        if method == "HEAD" {
            for route in routes where route.method == "GET" && route.path == path {
                let context = apiContext
                if let response = runAsync({ await route.handler(request, context) }) {
                    var head = response
                    head.body = Data()
                    return head
                }
            }
        }
        if method == "OPTIONS" {
            var response = HTTPResponseMessage(code: 204)
            response.headers["Allow"] = "GET, POST, OPTIONS"
            if let origin = configuration.allowedOrigin {
                response.headers["Access-Control-Allow-Origin"] = origin
                response.headers["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
                response.headers["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
            }
            return response
        }
        return runAsync { [fallback] in await fallback(request) } ?? .error("no response", code: 500)
    }

    /// The store the API reads from. Set before `start()`.
    public var sharedStore: LegadoStore {
        get { storeStorage }
        set { storeStorage = newValue }
    }

    /// Loads chapter content for `/getBookContent`.
    public var contentProvider: (@Sendable (Book, BookChapter) async throws -> String?)? {
        get { contentProviderStorage }
        set { contentProviderStorage = newValue }
    }

    private var contentProviderStorage: (@Sendable (Book, BookChapter) async throws -> String?)?
    private var storeStorage = LegadoStore(tables: MemoryTableStore())

    /// Reloads the table of contents of a book (`/refreshToc`).
    public var chapterListProvider: (@Sendable (BookSource, Book) async throws -> [BookChapter])? {
        get { chapterListProviderStorage }
        set { chapterListProviderStorage = newValue }
    }

    /// Reloads the table of contents of a local book (`/refreshToc`).
    public var localChapterListProvider: (@Sendable (Book) async throws -> [BookChapter])? {
        get { localChapterListProviderStorage }
        set { localChapterListProviderStorage = newValue }
    }

    /// Returns the bytes of an image (`/cover`, `/image`).
    ///
    /// The width scales the image — upstream
    /// `ImageProvider.getImage(book, src, width)`.
    public var imageProvider: (@Sendable (String, Int?) async throws -> Data?)? {
        get { imageProviderStorage }
        set { imageProviderStorage = newValue }
    }

    /// Uploads the reading progress to the WebDAV (`/saveBook`,
    /// `/saveBookProgress`) — upstream `AppWebDav.uploadBookProgress`.
    public var progressUploader: (@Sendable (Book) async -> Void)? {
        get { progressUploaderStorage }
        set { progressUploaderStorage = newValue }
    }

    /// Stores a local book file (`/addLocalBook`).
    public var localBookImporter: (@Sendable (String, Data) async throws -> Bool)? {
        get { localBookImporterStorage }
        set { localBookImporterStorage = newValue }
    }

    private var chapterListProviderStorage: (@Sendable (BookSource, Book) async throws -> [BookChapter])?
    private var localChapterListProviderStorage: (@Sendable (Book) async throws -> [BookChapter])?
    private var imageProviderStorage: (@Sendable (String, Int?) async throws -> Data?)?
    private var progressUploaderStorage: (@Sendable (Book) async -> Void)?
    private var localBookImporterStorage: (@Sendable (String, Data) async throws -> Bool)?

    private var apiContext: LegadoAPI.LegadoAPIRequestContext {
        LegadoAPI.LegadoAPIRequestContext(
            store: storeStorage,
            configuration: configuration,
            contentProvider: contentProviderStorage,
            chapterListProvider: chapterListProviderStorage,
            localChapterListProvider: localChapterListProviderStorage,
            imageProvider: imageProviderStorage,
            progressUploader: progressUploaderStorage,
            localBookImporter: localBookImporterStorage
        )
    }

    // MARK: - Async bridging

    /// Runs an async body on a blocking thread and returns its result.
    private func runAsync<T: Sendable>(_ body: @escaping @Sendable () async -> T) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        Task {
            box.value = await body()
            semaphore.signal()
        }
        semaphore.wait()
        return box.value
    }

    private final class ResultBox<T>: @unchecked Sendable {
        var value: T?
    }

    // MARK: - Addresses

    /// The addresses the service is reachable at, for the notification the
    /// Android service shows (`WebService.kt:196-213`).
    func localAddresses(port: Int) -> [String] {
        guard bindAddress != "127.0.0.1" else { return ["http://127.0.0.1:\(port)"] }
        var addresses: [String] = []
        // Field by field: the member ORDER of `addrinfo` differs between
        // Darwin (`ai_canonname` before `ai_addr`) and Glibc (after it), so the
        // positional initializer only compiles on one of them.
        var hints = addrinfo()
        hints.ai_flags = AI_PASSIVE
        hints.ai_family = AF_INET
        hints.ai_socktype = legadoStreamSocketType
        hints.ai_protocol = 0
        hints.ai_addrlen = 0
        hints.ai_addr = nil
        hints.ai_canonname = nil
        hints.ai_next = nil
        var result: UnsafeMutablePointer<addrinfo>?
        if getaddrinfo(nil, "0", &hints, &result) == 0, let first = result {
            defer { freeaddrinfo(result) }
            var current: UnsafeMutablePointer<addrinfo>? = first
            while let node = current {
                if let address = node.pointee.ai_addr {
                    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(address, node.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let host = String(cString: buffer)
                        if host != "127.0.0.1" { addresses.append("http://\(host):\(port)") }
                    }
                }
                current = node.pointee.ai_next
            }
        }
        addresses.insert("http://127.0.0.1:\(port)", at: 0)
        return addresses
    }
}

public enum ServerError: Error, Equatable {
    case socket(String)
    case bind(String)
}



