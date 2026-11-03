import XCTest
@testable import LegadoCore

/// The tests of the direct link upload — the port of the upstream
/// `help/DirectLinkUpload.kt` and of `AnalyzeUrl.upload`.
final class DirectLinkUploadTests: XCTestCase {

    // MARK: - The multipart body

    func testTheMultipartBodyCarriesTheFieldsAndTheFile() {
        let boundary = "BOUNDARY"
        let body = MultipartBody.encode(
            [
                MultipartBody.Part.field("name", "value"),
                MultipartBody.Part(
                    name: "file",
                    fileName: "backup.json",
                    contentType: "application/json",
                    data: Data("{}".utf8)
                )
            ],
            boundary: boundary
        )
        let text = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(text.hasPrefix("--BOUNDARY\r\n"))
        XCTAssertTrue(text.hasSuffix("--BOUNDARY--\r\n"))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"name\""))
        XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"file\"; filename=\"backup.json\""))
        XCTAssertTrue(text.contains("Content-Type: application/json"))
        XCTAssertTrue(text.contains("\r\n\r\nvalue\r\n"))
        XCTAssertTrue(text.contains("\r\n\r\n{}\r\n"))
    }

    func testTheBoundaryIsUnique() {
        let first = MultipartBody.makeBoundary()
        let second = MultipartBody.makeBoundary()
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(first.hasPrefix("----LegadoBoundary"))
    }

    // MARK: - The rule

    func testTheDefaultRulesAreTheUpstreamOnes() {
        XCTAssertEqual(DirectLinkUpload.defaultRules.count, 3)
        XCTAssertEqual(DirectLinkUpload.defaultRules[0].summary, "喵公子网盘①(有效期30天·香港G口)")
        XCTAssertEqual(DirectLinkUpload.defaultRules[1].summary, "喵公子网盘②(有效期7天)")
        XCTAssertEqual(DirectLinkUpload.defaultRules[2].summary, "橘涂书源网盘2.0 Beta(永久有效)")
        XCTAssertTrue(DirectLinkUpload.defaultRules[0].uploadUrl.contains("multipart/form-data"))
        XCTAssertTrue(DirectLinkUpload.defaultRules[0].downloadUrlRule.contains("shuyuan.nyasama.net"))
    }

    func testTheRuleIsStoredAndRead() {
        let store = InMemorySettingsStore()
        XCTAssertNil(DirectLinkUpload.getConfig(store: store))
        // Without a stored rule the first default one is used.
        XCTAssertEqual(DirectLinkUpload.getRule(store: store), DirectLinkUpload.defaultRules[0])
        XCTAssertEqual(DirectLinkUpload.getSummary(store: store), DirectLinkUpload.defaultRules[0].summary)

        let rule = DirectLinkUploadRule(
            uploadUrl: "https://example.com/up",
            downloadUrlRule: "$.data",
            summary: "测试",
            compress: true
        )
        DirectLinkUpload.putConfig(rule, store: store)
        XCTAssertEqual(DirectLinkUpload.getConfig(store: store), rule)
        XCTAssertEqual(DirectLinkUpload.getRule(store: store), rule)
        XCTAssertEqual(DirectLinkUpload.getSummary(store: store), "测试")

        DirectLinkUpload.delConfig(store: store)
        XCTAssertNil(DirectLinkUpload.getConfig(store: store))
    }

    // MARK: - The upload

    func testTheUploadSendsAMultipartBodyAndReadsTheDownloadLink() async throws {
        let client = UploadStubClient()
        let rule = DirectLinkUploadRule(
            uploadUrl: "https://example.com/up,{\"method\":\"POST\",\"body\": {\"file\": \"fileRequest\"},\"type\": \"multipart/form-data\"}",
            downloadUrlRule: "$.data",
            summary: "测试"
        )
        let url = try await DirectLinkUpload.upload(
            fileName: "backup.json",
            file: Data("{\"a\":1}".utf8),
            contentType: "application/json",
            rule: rule,
            dependencies: AnalyzeUrlDependencies(httpClient: client, cookieStore: CookieStore())
        )
        XCTAssertEqual(url, "https://example.com/download/1")
        // The request dropped the query and posted a multipart body.
        XCTAssertEqual(client.requestedURL, "https://example.com/up")
        XCTAssertEqual(client.requestedMethod, "POST")
        let contentType = client.requestedHeaders["Content-Type"] ?? ""
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = String(data: client.requestedBody ?? Data(), encoding: .utf8) ?? ""
        XCTAssertTrue(body.contains("name=\"file\"; filename=\"backup.json\""))
        XCTAssertTrue(body.contains("{\"a\":1}"))
    }

    func testTheUploadFailsWithoutTheAddress() async {
        let rule = DirectLinkUploadRule(uploadUrl: "", downloadUrlRule: "$.data", summary: "x")
        do {
            _ = try await DirectLinkUpload.upload(
                fileName: "a.json",
                file: Data("{}".utf8),
                contentType: "application/json",
                rule: rule
            )
            XCTFail("the upload should fail")
        } catch let error as DirectLinkUploadError {
            XCTAssertEqual(error, .notConfigured("上传url未配置"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testTheUploadFailsWithoutTheDownloadRule() async {
        let rule = DirectLinkUploadRule(uploadUrl: "https://example.com/up", downloadUrlRule: "", summary: "x")
        do {
            _ = try await DirectLinkUpload.upload(
                fileName: "a.json",
                file: Data("{}".utf8),
                contentType: "application/json",
                rule: rule
            )
            XCTFail("the upload should fail")
        } catch let error as DirectLinkUploadError {
            XCTAssertEqual(error, .notConfigured("下载地址规则未配置"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testTheUploadFailsWhenTheAnswerHasNoLink() async {
        let client = UploadStubClient(body: "{}")
        let rule = DirectLinkUploadRule(
            uploadUrl: "https://example.com/up,{\"body\": {\"file\": \"fileRequest\"}}",
            downloadUrlRule: "$.data",
            summary: "x"
        )
        do {
            _ = try await DirectLinkUpload.upload(
                fileName: "a.json",
                file: Data("{}".utf8),
                contentType: "application/json",
                rule: rule,
                dependencies: AnalyzeUrlDependencies(httpClient: client, cookieStore: CookieStore())
            )
            XCTFail("the upload should fail")
        } catch let error as DirectLinkUploadError {
            XCTAssertEqual(error, .uploadFailed("上传失败,{}"))
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}

/// A stub client that records the upload request.
final class UploadStubClient: HttpClient, @unchecked Sendable {

    private let body: String
    private let lock = NSLock()
    private var url = ""
    private var method = ""
    private var headers: [String: String] = [:]
    private var payload: Data?

    init(body: String = "{\"data\":\"https://example.com/download/1\"}") {
        self.body = body
    }

    var requestedURL: String {
        lock.lock()
        defer { lock.unlock() }
        return url
    }

    var requestedMethod: String {
        lock.lock()
        defer { lock.unlock() }
        return method
    }

    var requestedHeaders: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return headers
    }

    var requestedBody: Data? {
        lock.lock()
        defer { lock.unlock() }
        return payload
    }

    func send(_ request: HttpRequest) async throws -> HttpResponse {
        lock.lock()
        url = request.url
        method = request.method
        headers = request.headers
        payload = request.body
        lock.unlock()
        return HttpResponse(url: request.url, body: body, code: 200)
    }
}
