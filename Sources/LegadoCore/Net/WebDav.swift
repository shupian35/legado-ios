import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A WebDAV client — the port of `lib/webdav/{WebDav, Authorization,
/// WebDavFile, WebDavException}.kt`.
///
/// Upstream hand-rolls the protocol on top of OkHttp rather than pulling in a
/// third-party WebDAV library, and the port keeps that choice: only `PROPFIND`,
/// `PUT`, `GET`, `DELETE` and `MKCOL` are needed, which is a few dozen lines
/// each.
///
/// The server is used for three things (see `WebDavService`): backups, reading
/// progress and the books uploaded from the phone.
public struct WebDavFile: Equatable, Sendable {
    /// The path below the base URL, without a leading slash.
    public let path: String
    /// The file name, i.e. the last path component.
    public let name: String
    public let isDirectory: Bool
    public let size: Int64?
    /// The server's last-modification date, when it reports one.
    public let lastModified: Date?

    public init(
        path: String,
        name: String,
        isDirectory: Bool,
        size: Int64? = nil,
        lastModified: Date? = nil
    ) {
        self.path = path
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.lastModified = lastModified
    }
}

public enum WebDavError: Error, Equatable {
    /// The server answered 401/403 — the stored password must be dropped.
    case unauthorized
    case notFound(String)
    case server(Int, String)
    case invalidResponse(String)
    case invalidURL(String)
}

/// Connection settings for a WebDAV account.
public struct WebDavConfiguration: Equatable, Sendable {
    public var url: String
    public var username: String
    public var password: String
    /// Where backups are written — the server root, as upstream.
    public var backupDirectory: String
    /// Per-book reading progress files.
    public var bookProgressDirectory: String
    /// Books uploaded from the phone.
    public var booksDirectory: String
    /// Reading-background images.
    public var backgroundDirectory: String

    public init(
        url: String = "https://dav.jianguoyun.com/dav/",
        username: String = "",
        password: String = "",
        backupDirectory: String = "",
        bookProgressDirectory: String = "bookProgress/",
        booksDirectory: String = "books/",
        backgroundDirectory: String = "background/"
    ) {
        self.url = url
        self.username = username
        self.password = password
        self.backupDirectory = backupDirectory
        self.bookProgressDirectory = bookProgressDirectory
        self.booksDirectory = booksDirectory
        self.backgroundDirectory = backgroundDirectory
    }

    /// Whether a server is configured.
    public var isConfigured: Bool {
        !url.isEmpty && !username.isEmpty && !password.isEmpty
    }

    var baseURL: URL? {
        var text = url
        guard !text.isEmpty else { return nil }
        if !text.hasSuffix("/") { text += "/" }
        return URL(string: text)
    }
}

public final class WebDavClient: @unchecked Sendable {
    public let configuration: WebDavConfiguration
    private let httpClient: any HttpClient

    public init(configuration: WebDavConfiguration, httpClient: any HttpClient = URLSessionHttpClient()) {
        self.configuration = configuration
        self.httpClient = httpClient
    }

    // MARK: - URL helpers

    /// Resolves a path below the base URL, percent-encoding each component.
    public func url(for path: String) throws -> URL {
        guard let base = configuration.baseURL else {
            throw WebDavError.invalidURL(configuration.url)
        }
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let encoded = trimmed
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { percentEncoded(String($0)) }
            .joined(separator: "/")
        guard !encoded.isEmpty else { return base }
        var text = base.absoluteString
        if !text.hasSuffix("/") { text += "/" }
        text += encoded
        guard let url = URL(string: text) else {
            throw WebDavError.invalidURL(text)
        }
        return url
    }

    private func percentEncoded(_ component: String) -> String {
        component.addingPercentEncoding(withAllowedCharacters: pathAllowed) ?? component
    }

    private var pathAllowed: CharacterSet {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#")
        return allowed
    }

    private func request(url: URL, method: String, headers: [String: String] = [:], body: Data? = nil) -> HttpRequest {
        var allHeaders = headers
        allHeaders["Authorization"] = Self.basicAuthorization(
            username: configuration.username,
            password: configuration.password
        )
        return HttpRequest(
            url: url.absoluteString,
            method: method,
            headers: allHeaders,
            body: body,
            callTimeout: 120
        )
    }

    static func basicAuthorization(username: String, password: String) -> String {
        "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()
    }

    // MARK: - Operations

    /// `PROPFIND` — lists a directory, or describes a single resource.
    public func list(_ path: String, depth: Int = 1) async throws -> [WebDavFile] {
        let url = try url(for: path)
        let body = """
        <?xml version="1.0" encoding="utf-8" ?>
        <d:propfind xmlns:d="DAV:">
          <d:prop>
            <d:displayname/>
            <d:getcontentlength/>
            <d:getlastmodified/>
            <d:resourcetype/>
          </d:prop>
        </d:propfind>
        """
        let response = try await httpClient.send(
            request(
                url: url,
                method: "PROPFIND",
                headers: ["Depth": String(depth), "Content-Type": "application/xml; charset=utf-8"],
                body: Data(body.utf8)
            )
        )
        try validate(response)
        guard let text = response.body else {
            throw WebDavError.invalidResponse("empty PROPFIND body")
        }
        let basePath = Self.pathComponent(of: path)
        var files = WebDavMultistatus.parse(text, baseURL: configuration.url)
        // The response always contains the collection itself; drop it so a
        // caller sees only its children (upstream does the same).
        files.removeAll { $0.path == basePath && $0.isDirectory }
        return files
    }

    /// `PUT` — uploads a file, creating it when it does not exist.
    public func upload(_ data: Data, to path: String, contentType: String = "application/octet-stream") async throws {
        let url = try url(for: path)
        let response = try await httpClient.send(
            request(
                url: url,
                method: "PUT",
                headers: ["Content-Type": contentType, "Content-Length": String(data.count)],
                body: data
            )
        )
        try validate(response)
    }

    /// `GET` — downloads a file.
    public func download(_ path: String) async throws -> Data {
        let url = try url(for: path)
        let response = try await httpClient.send(request(url: url, method: "GET"))
        try validate(response)
        return response.data ?? Data((response.body ?? "").utf8)
    }

    /// `GET` as text.
    public func downloadText(_ path: String) async throws -> String {
        String(decoding: try await download(path), as: UTF8.self)
    }

    /// `DELETE`.
    public func delete(_ path: String) async throws {
        let url = try url(for: path)
        let response = try await httpClient.send(request(url: url, method: "DELETE"))
        // Deleting something that is already gone is not an error.
        if response.code == 404 { return }
        try validate(response)
    }

    /// `MKCOL` — creates a collection, ignoring "already exists".
    public func createDirectory(_ path: String) async throws {
        let url = try url(for: path)
        let response = try await httpClient.send(request(url: url, method: "MKCOL"))
        if response.code == 405 { return } // already exists
        try validate(response)
    }

    /// Whether the credentials work — the upstream `checkAuthorization()`.
    public func checkAuthorization() async throws {
        let response = try await httpClient.send(request(url: try url(for: ""), method: "PROPFIND", headers: ["Depth": "0"]))
        try validate(response)
    }

    private func validate(_ response: HttpResponse) throws {
        switch response.code {
        case 401, 403:
            throw WebDavError.unauthorized
        case 404:
            throw WebDavError.notFound(response.url)
        case 200...299, 207:
            return
        default:
            throw WebDavError.server(response.code, response.body ?? response.message)
        }
    }

    static func pathComponent(of path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

/// Parses a WebDAV `multistatus` document.
///
/// Written by hand rather than with an XML library because the response mixes
/// namespaces (`DAV:`, `urn:ietf:params:xml:ns:caldav`, …) and servers differ
/// in whether they emit a `d:` prefix at all — this parser only cares about
/// local names.
enum WebDavMultistatus {

    static func parse(_ xml: String, baseURL: String) -> [WebDavFile] {
        var files: [WebDavFile] = []
        for block in blocks(in: xml, localName: "response") {
            guard let href = firstValue(in: block, localName: "href") else { continue }
            let path = normalize(href: href, baseURL: baseURL)
            let isDirectory = firstValue(in: block, localName: "collection") != nil
                || href.hasSuffix("/")
            let size = firstValue(in: block, localName: "getcontentlength").flatMap { Int64($0) }
            let modified = firstValue(in: block, localName: "getlastmodified").flatMap { date(from: $0) }
            let name = path.split(separator: "/").last.map(String.init) ?? path
            files.append(
                WebDavFile(
                    path: path,
                    name: name,
                    isDirectory: isDirectory,
                    size: size,
                    lastModified: modified
                )
            )
        }
        return files
    }

    /// Extracts the inner text of every element with the given local name.
    static func blocks(in text: String, localName: String) -> [String] {
        let pattern = "<(?:[\\w.-]+:)?\(localName)\\b[^>]*>(.*?)</(?:[\\w.-]+:)?\(localName)\\s*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }
        let ns = text as NSString
        return regex.matches(in: text, options: [], range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    /// The inner text of the first element with the given local name.
    static func firstValue(in text: String, localName: String) -> String? {
        guard let raw = blocks(in: text, localName: localName).first else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : unescapeXML(trimmed)
    }

    /// Turns an `href` (absolute URL or absolute path) into a path below the
    /// configured base URL.
    static func normalize(href: String, baseURL: String) -> String {
        var value = unescapeXML(href.trimmingCharacters(in: .whitespacesAndNewlines))
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            guard let absolute = URL(string: value) else { return value }
            value = absolute.path
        }
        // Strip the mount point of the account ("/dav/" for 坚果云), so the
        // caller sees paths relative to the configured base URL.
        let basePath = URL(string: baseURL)?.path ?? ""
        if !basePath.isEmpty, basePath != "/", value.hasPrefix(basePath) {
            value.removeFirst(basePath.count)
        }
        return pathComponent(of: value)
    }

    private static func pathComponent(of path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func date(from text: String) -> Date? {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",       // RFC 1123
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    static func unescapeXML(_ text: String) -> String {
        text.replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
