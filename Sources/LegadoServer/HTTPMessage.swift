import Foundation
import LegadoCore

/// A minimal HTTP/1.1 message model — everything the local book API needs,
/// with no dependencies.
///
/// The Android app serves this API with NanoHTTPD and NanoWSD
/// (`app/src/main/java/io/legado/app/web/{HttpServer,WebSocketServer}.kt`).
/// Those are Java-only, so the port implements the subset it actually uses:
/// request parsing, response building, and the WebSocket handshake plus text
/// frames.
public struct HTTPRequestHead: Sendable {
    public var method: String
    public var target: String
    /// The path of the target, without the query string.
    public var path: String
    /// The decoded query parameters.
    public var query: [(String, String)]
    public var headers: [String: String]
    public var body: Data

    public init(
        method: String,
        target: String,
        headers: [String: String] = [:],
        body: Data = Data()
    ) {
        self.method = method
        self.target = target
        let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        self.path = parts.first.map(String.init) ?? target
        if parts.count > 1 {
            self.query = HTTPRequestHead.parseQuery(String(parts[1]))
        } else {
            self.query = []
        }
        self.headers = headers
        self.body = body
    }

    /// Header lookup, case-insensitive (as HTTP requires).
    public func header(_ name: String) -> String? {
        if let exact = headers[name] { return exact }
        let lowered = name.lowercased()
        for (key, value) in headers where key.lowercased() == lowered { return value }
        return nil
    }

    /// A query parameter, or `nil`.
    public func query(_ name: String) -> String? {
        query.first { $0.0 == name }?.1
    }

    /// The body as UTF-8 text.
    public var bodyText: String {
        String(decoding: body, as: UTF8.self)
    }

    static func parseQuery(_ text: String) -> [(String, String)] {
        text.split(separator: "&", omittingEmptySubsequences: true).map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = decodePercent(String(parts.first ?? ""))
            let value = parts.count > 1 ? decodePercent(String(parts[1])) : ""
            return (key, value)
        }
    }

    static func decodePercent(_ text: String) -> String {
        text.replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding ?? text
    }
}

/// A response the server sends back.
public struct HTTPResponseMessage: Equatable, Sendable {
    public var code: Int
    public var reason: String
    public var headers: [String: String]
    public var body: Data

    public init(
        code: Int = 200,
        reason: String? = nil,
        headers: [String: String] = [:],
        body: Data = Data()
    ) {
        self.code = code
        self.reason = reason ?? HTTPResponseMessage.reasonPhrase(for: code)
        self.headers = headers
        self.body = body
    }

    /// A JSON response.
    public static func json(_ text: String, code: Int = 200) -> HTTPResponseMessage {
        HTTPResponseMessage(
            code: code,
            headers: ["Content-Type": "application/json; charset=utf-8"],
            body: Data(text.utf8)
        )
    }

    /// A JSON response in the upstream envelope — upstream `api/ReturnData.kt`
    /// (`isSuccess`, `errorMsg`, `data`).
    ///
    /// The upstream web client (the Vue app of `modules/web`) reads the
    /// payload from `data`, so the local API has to use the same shape.
    public static func api(_ payload: JSONValue, code: Int = 200) -> HTTPResponseMessage {
        let envelope = JSONValue.object([
            "isSuccess": .bool(true),
            "errorMsg": .string(""),
            "data": payload
        ])
        return json(envelope.jsonString, code: code)
    }

    /// A business error in the upstream envelope.
    ///
    /// Upstream `ReturnData.setErrorMsg` keeps the HTTP status 200 and puts
    /// the message into `errorMsg` — the clients read the envelope, not the
    /// status code.
    public static func apiError(_ message: String) -> HTTPResponseMessage {
        let envelope = JSONValue.object([
            "isSuccess": .bool(false),
            "errorMsg": .string(message),
            "data": .null
        ])
        return json(envelope.jsonString)
    }

    /// A plain-text response — what upstream returns for most errors.
    public static func text(_ text: String, code: Int = 200) -> HTTPResponseMessage {
        HTTPResponseMessage(
            code: code,
            headers: ["Content-Type": "text/plain; charset=utf-8"],
            body: Data(text.utf8)
        )
    }

    public static func error(_ message: String, code: Int = 500) -> HTTPResponseMessage {
        text(message, code: code)
    }

    /// A binary response — the cover and the chapter images.
    public static func binary(_ data: Data, contentType: String = "application/octet-stream", code: Int = 200) -> HTTPResponseMessage {
        HTTPResponseMessage(
            code: code,
            headers: ["Content-Type": contentType],
            body: data
        )
    }

    public static func redirect(to location: String) -> HTTPResponseMessage {
        HTTPResponseMessage(code: 302, headers: ["Location": location])
    }

    /// Serialises the response for the wire.
    public func serialized(keepAlive: Bool) -> Data {
        var head = "HTTP/1.1 \(code) \(reason)\r\n"
        var allHeaders = headers
        allHeaders["Content-Length"] = String(body.count)
        allHeaders["Connection"] = keepAlive ? "keep-alive" : "close"
        if allHeaders["Date"] == nil {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
            allHeaders["Date"] = formatter.string(from: Date())
        }
        for key in allHeaders.keys.sorted() {
            head += "\(key): \(allHeaders[key] ?? "")\r\n"
        }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        return data
    }

    static func reasonPhrase(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Internal Server Error"
        default: return "Status \(code)"
        }
    }
}

public enum HTTPParseError: Error, Equatable {
    /// The request head is incomplete — the caller should read more.
    case incomplete
    case malformed(String)
}

public enum HTTPParser {

    /// Parses a request head (`\r\n\r\n`-terminated) plus the body that
    /// follows it.
    ///
    /// - Returns: the request and the number of bytes consumed.
    public static func parseRequest(_ data: Data) throws -> (request: HTTPRequestHead, consumed: Int) {
        guard let headerEnd = findHeaderEnd(data) else { throw HTTPParseError.incomplete }
        let headBytes = data.prefix(headerEnd)
        guard let headText = String(data: headBytes, encoding: .utf8) else {
            throw HTTPParseError.malformed("request head is not UTF-8")
        }
        var lines = headText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { throw HTTPParseError.malformed("empty request") }
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { throw HTTPParseError.malformed("bad request line: \(requestLine)") }
        let method = String(parts[0])
        let target = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if let existing = headers[name] {
                headers[name] = existing + ", " + value
            } else {
                headers[name] = value
            }
        }

        let bodyStart = headerEnd
        let contentLength = Int(headers["Content-Length"] ?? headers["content-length"] ?? "") ?? 0
        if data.count < bodyStart + contentLength { throw HTTPParseError.incomplete }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
        let request = HTTPRequestHead(method: method, target: target, headers: headers, body: body)
        return (request, bodyStart + contentLength)
    }

    static func findHeaderEnd(_ data: Data) -> Int? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else { return nil }
        return data.distance(from: data.startIndex, to: range.upperBound)
    }
}

