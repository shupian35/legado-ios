//
//  HttpClient.swift
//  LegadoCore
//
//  The transport layer — the port of the parts of
//  app/src/main/java/io/legado/app/help/http/ that the rule engine needs.
//  Upstream uses OkHttp (+ Cronet); the port uses URLSession.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Request

/// An outgoing HTTP request.
public struct HttpRequest: Sendable {
    public var url: String
    public var method: String
    public var headers: [String: String]
    public var body: Data?
    /// The request timeout (upstream `readTimeout`).
    public var readTimeout: TimeInterval
    /// The overall call timeout (upstream `callTimeout`).
    public var callTimeout: TimeInterval
    /// An optional proxy (`host:port`).
    public var proxy: String?

    public init(
        url: String,
        method: String = "GET",
        headers: [String: String] = [:],
        body: Data? = nil,
        readTimeout: TimeInterval = 20,
        callTimeout: TimeInterval = 60,
        proxy: String? = nil
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.readTimeout = readTimeout
        self.callTimeout = callTimeout
        self.proxy = proxy
    }
}

// MARK: - Response

/// An HTTP response — the port of `io.legado.app.help.http.StrResponse`.
public struct HttpResponse: Sendable {
    /// The final URL (after redirects).
    public var url: String
    /// The response body decoded with the response charset.
    public var body: String?
    /// The raw bytes of the response body.
    public var data: Data?
    public var code: Int
    public var message: String
    public var headers: [String: String]
    /// The body of a failed request.
    public var errorBody: Data?

    public init(
        url: String,
        body: String? = nil,
        data: Data? = nil,
        code: Int = 200,
        message: String = "OK",
        headers: [String: String] = [:],
        errorBody: Data? = nil
    ) {
        self.url = url
        self.body = body
        self.data = data
        self.code = code
        self.message = message
        self.headers = headers
        self.errorBody = errorBody
    }

    public var isSuccessful: Bool { (200...299).contains(code) }
}

// MARK: - Errors

public enum HttpError: Error, Equatable {
    case invalidURL(String)
    case transport(String)
    case status(code: Int, message: String)
}

// MARK: - Client

/// The transport protocol — the port of the OkHttp client factory.
public protocol HttpClient: Sendable {
    func send(_ request: HttpRequest) async throws -> HttpResponse
}

/// The URLSession implementation of `HttpClient`.
public struct URLSessionHttpClient: HttpClient {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public init(configuration: URLSessionConfiguration) {
        self.session = URLSession(configuration: configuration)
    }

    public func send(_ request: HttpRequest) async throws -> HttpResponse {
        do {
            return try await perform(request)
        } catch let error as URLError where error.code == .networkConnectionLost {
            // Upstream OkHttp runs with `retryOnConnectionFailure`: a server
            // that closes the keep-alive connection (or drops it mid
            // response) silently gets a second attempt on a fresh
            // connection. URLSession surfaces it as
            // "The network connection was lost." instead — the reader saw
            // that alert on sources whose servers reset links aggressively.
            return try await perform(request)
        }
    }

    private func perform(_ request: HttpRequest) async throws -> HttpResponse {
        guard let url = URL(string: request.url), url.scheme != nil else {
            throw HttpError.invalidURL(request.url)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.uppercased()
        urlRequest.httpBody = request.body
        urlRequest.timeoutInterval = request.callTimeout
        for (name, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        let timeout = request.callTimeout
        let (data, response) = try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask {
                let (data, response) = try await self.session.data(for: urlRequest)
                return (data, response)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw HttpError.transport("请求超时")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HttpError.transport("无效的响应")
        }
        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            headers["\(key)"] = "\(value)"
        }
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
        return HttpResponse(
            url: httpResponse.url?.absoluteString ?? request.url,
            body: text,
            data: data,
            code: httpResponse.statusCode,
            message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
            headers: headers
        )
    }
}
