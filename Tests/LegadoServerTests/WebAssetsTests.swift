//
//  WebAssetsTests.swift
//  LegadoServerTests
//
//  The web bookshelf assets.
//

import XCTest
@testable import LegadoServer

final class WebAssetsTests: XCTestCase {

    override func tearDown() {
        WebAssets.accessToken = nil
        super.tearDown()
    }

    /// The upstream Vue bundle is copied into the package resources, so the
    /// port serves the very same web UI as the Android app.
    func testTheUpstreamVueBundleIsServed() {
        XCTAssertTrue(WebAssets.hasUpstreamBundle)
        let response = WebAssets.response(for: "/")
        XCTAssertNotNil(response)
        XCTAssertEqual(response?.code, 200)
        let body = String(decoding: response?.body ?? Data(), as: UTF8.self)
        // The upstream `index.html` of the Vue application.
        XCTAssertTrue(body.contains("<div id=\"app\"></div>"), body.prefix(200).description)
        XCTAssertTrue(body.contains("./assets/index-"), body.prefix(400).description)
    }

    func testTheBundleAssetsAreServedWithTheirContentType() {
        let index = String(decoding: WebAssets.response(for: "/")?.body ?? Data(), as: UTF8.self)
        guard let range = index.range(of: "./assets/index-") else {
            return XCTFail("no bundle entry in the index")
        }
        let rest = index[range.upperBound...]
        let name = "index-" + String(rest.prefix(while: { $0 != "\"" }))
        let response = WebAssets.response(for: "/assets/\(name)")
        XCTAssertEqual(response?.code, 200)
        XCTAssertEqual(response?.headers["Content-Type"], "application/javascript; charset=utf-8")
        XCTAssertGreaterThan(response?.body.count ?? 0, 1000)
    }

    func testTheTokenIsInjectedIntoTheIndexPage() {
        WebAssets.accessToken = "s3cret"
        let body = String(decoding: WebAssets.response(for: "/")?.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("s3cret"), "the token script is missing")
        XCTAssertTrue(body.contains("Authorization"))
    }

    func testWithoutATokenThePageIsNotPatched() {
        WebAssets.accessToken = nil
        let body = String(decoding: WebAssets.response(for: "/")?.body ?? Data(), as: UTF8.self)
        XCTAssertFalse(body.contains("Authorization"))
    }

    /// The upstream help pages are served as well.
    func testTheUpstreamHelpPagesAreServed() {
        let response = WebAssets.response(for: "/help/index.html")
        XCTAssertEqual(response?.code, 200)
        XCTAssertEqual(response?.headers["Content-Type"], "text/html; charset=utf-8")
    }

    /// The upstream upload page is served as well.
    func testTheUpstreamUploadPageIsServed() {
        let response = WebAssets.response(for: "/uploadBook/index.html")
        XCTAssertEqual(response?.code, 200)
        XCTAssertEqual(response?.headers["Content-Type"], "text/html; charset=utf-8")
    }

    /// The Vue application is reachable under the upstream path as well.
    func testTheVueApplicationIsServedUnderTheUpstreamPath() {
        let response = WebAssets.response(for: "/vue/index.html")
        XCTAssertEqual(response?.code, 200)
        let body = String(decoding: response?.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("id=\"app\""))
    }

    /// The fallback client is kept for the case where the bundle is missing.
    func testTheFallbackClientIsServed() {        let response = WebAssets.response(for: "/app.js")
        XCTAssertEqual(response?.code, 200)
        XCTAssertEqual(response?.headers["Content-Type"], "application/javascript")
        let body = String(decoding: response?.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("/getBookshelf"))
        XCTAssertTrue(body.contains("/getChapterList"))
        XCTAssertTrue(body.contains("/getBookContent"))
    }

    func testTheFallbackStylesheetIsServed() {
        let response = WebAssets.response(for: "/style.css")
        XCTAssertEqual(response?.code, 200)
        XCTAssertEqual(response?.headers["Content-Type"], "text/css")
    }

    func testAnUnknownPathIsNotAnAsset() {
        XCTAssertNil(WebAssets.response(for: "/nope"))
    }

    func testTheServerServesTheWebBookshelf() {
        let server = LegadoServer(configuration: LegadoAPIConfiguration(token: "t"))
        let request = HTTPRequestHead(method: "GET", target: "/", headers: [:], body: Data())
        let response = server.respond(to: request)
        XCTAssertEqual(response.code, 200)
        let body = String(decoding: response.body, as: UTF8.self)
        XCTAssertTrue(body.contains("<div id=\"app\"></div>"), body.prefix(200).description)
    }

    func testAnUnknownPathIsStillNotFound() {
        let server = LegadoServer(configuration: LegadoAPIConfiguration(token: "t"))
        let request = HTTPRequestHead(method: "GET", target: "/nope", headers: [:], body: Data())
        XCTAssertEqual(server.respond(to: request).code, 404)
    }
}
