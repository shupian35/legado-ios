//
//  HttpTtsCacheTests.swift
//  LegadoCoreTests
//
//  The cache of the HTTP TTS audio and the request of the service — upstream
//  `HttpReadAloudService.getSpeakStream()` / `md5SpeakFileName()`.
//

import XCTest
@testable import LegadoCore

final class HttpTtsCacheTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("httpTtsCache-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    /// Upstream `md5SpeakFileName(content, textChapter)`:
    /// `md5Encode16(title) + "_" + md5Encode16("url-|-rate-|-text")`.
    func testTheFileNameIsTheUpstreamOne() {
        let name = HttpTtsCache.fileName(
            text: "hello",
            chapterTitle: "第一章",
            ttsUrl: "https://tts.example.com/say",
            speechRate: 5
        )
        let title = ScriptDigest.md5Encode16("第一章")
        let content = ScriptDigest.md5Encode16("https://tts.example.com/say-|-5-|-hello")
        XCTAssertEqual(name, "\(title)_\(content)")
    }

    /// The audio is written into the cache and read back.
    func testTheAudioIsStoredAndRead() {
        let data = Data([1, 2, 3, 4])
        XCTAssertTrue(HttpTtsCache.store(
            data,
            root: root,
            text: "hello",
            chapterTitle: "第一章",
            ttsUrl: "https://tts.example.com/say",
            speechRate: 5
        ))
        let read = HttpTtsCache.data(
            root: root,
            text: "hello",
            chapterTitle: "第一章",
            ttsUrl: "https://tts.example.com/say",
            speechRate: 5
        )
        XCTAssertEqual(read, data)
        // The file lives in the `httpTTS` folder — upstream `cacheDir/httpTTS`.
        let url = HttpTtsCache.fileURL(
            root: root,
            text: "hello",
            chapterTitle: "第一章",
            ttsUrl: "https://tts.example.com/say",
            speechRate: 5
        )
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "httpTTS")
        XCTAssertEqual(url.pathExtension, "mp3")
    }

    /// A different rate is a different file — upstream the rate is part of the
    /// name.
    func testTheRateIsPartOfTheName() {
        XCTAssertNotEqual(
            HttpTtsCache.fileName(text: "a", chapterTitle: "t", ttsUrl: "u", speechRate: 1),
            HttpTtsCache.fileName(text: "a", chapterTitle: "t", ttsUrl: "u", speechRate: 2)
        )
    }

    /// The cache is removed — upstream `clearTtsCache()`.
    func testTheCacheIsRemoved() {
        HttpTtsCache.store(
            Data([1]),
            root: root,
            text: "hello",
            chapterTitle: "c",
            ttsUrl: "u",
            speechRate: 5
        )
        HttpTtsCache.removeAll(root: root)
        XCTAssertNil(HttpTtsCache.data(
            root: root,
            text: "hello",
            chapterTitle: "c",
            ttsUrl: "u",
            speechRate: 5
        ))
    }
}

// MARK: - The request

final class HttpTtsRequestTests: XCTestCase {

    private func makeTts(
        header: String? = nil,
        contentType: String? = nil,
        loginCheckJs: String? = nil
    ) -> HttpTTS {
        var tts = HttpTTS(id: 7, name: "引擎", url: "https://tts.example.com/say?text={{speakText}}")
        tts.header = header
        tts.contentType = contentType
        tts.loginCheckJs = loginCheckJs
        return tts
    }

    /// The header of the profile is part of the request.
    func testTheRequestCarriesTheHeader() throws {
        let request = try HttpTts.request(
            text: "hello",
            tts: makeTts(header: "{\"X-Token\":\"abc\"}")
        )
        XCTAssertEqual(request.headers["X-Token"], "abc")
    }

    /// Upstream `BaseSource.getHeaderMap()`: a default `User-Agent` is added
    /// when the header has none.
    func testTheRequestCarriesTheDefaultUserAgent() throws {
        let request = try HttpTts.request(text: "hello", tts: makeTts())
        XCTAssertEqual(request.headers["User-Agent"], SourceSupport.defaultUserAgent)
    }

    /// The login header is merged into the request — upstream
    /// `AnalyzeUrl(source = httpTts)`.
    func testTheRequestCarriesTheLoginHeader() throws {
        let request = try HttpTts.request(
            text: "hello",
            tts: makeTts(header: "{\"X-Token\":\"abc\"}"),
            loginHeaderMap: ["Cookie": "token=1"]
        )
        XCTAssertEqual(request.headers["Cookie"], "token=1")
        XCTAssertEqual(request.headers["X-Token"], "abc")
    }

    /// A script header rule is evaluated — upstream `getHeaderMap()`.
    func testTheHeaderRuleIsEvaluated() throws {
        let engine = StubScriptEngine()
        engine.result = .text("{\"X-Script\":\"yes\"}")
        let request = try HttpTts.request(
            text: "hello",
            tts: makeTts(header: "@js:{\"X-Script\":\"yes\"}"),
            scriptEngine: engine
        )
        XCTAssertEqual(request.headers["X-Script"], "yes")
    }

    /// The URL of the request carries the text — upstream `{{speakText}}`.
    func testTheRequestCarriesTheText() throws {
        let request = try HttpTts.request(text: "hello", tts: makeTts())
        XCTAssertTrue(request.url.contains("hello"))
    }
}

// MARK: - The error of the service

final class HttpTtsErrorTests: XCTestCase {

    private func makeTts(contentType: String? = nil) -> HttpTTS {
        var tts = HttpTTS(id: 7, name: "引擎", url: "https://tts.example.com/say")
        tts.contentType = contentType
        return tts
    }

    /// A JSON response is the error message of the service — upstream
    /// `getSpeakStream`.
    func testAJsonResponseIsAnError() {
        let message = HttpTts.errorMessage(
            contentType: "application/json; charset=utf-8",
            body: "{\"error\":\"登录已过期\"}",
            tts: makeTts()
        )
        XCTAssertEqual(message, "{\"error\":\"登录已过期\"}")
    }

    /// A text response is the error message of the service.
    func testATextResponseIsAnError() {
        let message = HttpTts.errorMessage(
            contentType: "text/html",
            body: "请先登录",
            tts: makeTts()
        )
        XCTAssertEqual(message, "请先登录")
    }

    /// The content type does not match the profile — upstream
    /// `"TTS服务器返回错误：" + body`.
    func testTheContentTypeMismatchIsAnError() {
        let message = HttpTts.errorMessage(
            contentType: "audio/mpeg",
            body: "oops",
            tts: makeTts(contentType: "audio/mp3")
        )
        XCTAssertEqual(message, "TTS服务器返回错误：oops")
    }

    /// The audio of the service is not an error.
    func testTheAudioIsNotAnError() {
        XCTAssertNil(HttpTts.errorMessage(
            contentType: "audio/mpeg",
            body: nil,
            tts: makeTts(contentType: "audio/mpeg")
        ))
        // Without a content type the upstream does not check anything.
        XCTAssertNil(HttpTts.errorMessage(contentType: nil, body: nil, tts: makeTts()))
    }
}

// MARK: - The login check

final class HttpTtsLoginCheckTests: XCTestCase {

    /// The script leaves the response alone.
    func testTheResponseIsUnchanged() throws {
        let engine = StubScriptEngine()
        engine.result = .null
        let result = try HttpTts.applyLoginCheck(
            script: "result",
            body: "the body",
            code: 200,
            headers: [:],
            scriptEngine: engine
        )
        XCTAssertEqual(result, .unchanged)
    }

    /// The script reports an error.
    func testTheScriptReportsAnError() throws {
        let engine = StubScriptEngine()
        engine.result = .text("登录已过期")
        let result = try HttpTts.applyLoginCheck(
            script: "result",
            body: "",
            code: 401,
            headers: [:],
            scriptEngine: engine
        )
        XCTAssertEqual(result, .failure("登录已过期"))
    }

    /// The script replaces the body of the response.
    func testTheScriptReplacesTheBody() throws {
        let engine = StubScriptEngine()
        engine.result = .scriptObject(["body": .text("new body")])
        let result = try HttpTts.applyLoginCheck(
            script: "result",
            body: "old body",
            code: 200,
            headers: [:],
            scriptEngine: engine
        )
        XCTAssertEqual(result, .body("new body"))
    }

    /// Without a script engine the response is unchanged.
    func testWithoutAnEngineTheResponseIsUnchanged() throws {
        let result = try HttpTts.applyLoginCheck(
            script: "result",
            body: "the body",
            code: 200,
            headers: [:],
            scriptEngine: nil
        )
        XCTAssertEqual(result, .unchanged)
    }
}
