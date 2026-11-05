//
//  OpenURLRequestTests.swift
//  LegadoCoreTests
//
//  The tests of the confirmation of an external link — upstream
//  `OpenUrlConfirmActivity` / `OpenUrlConfirmDialog`.
//

import XCTest
@testable import LegadoCore

final class OpenURLRequestTests: XCTestCase {

    // MARK: - The request

    func testTheMessageNamesTheSource() {
        let request = OpenURLRequest(url: "https://example.com", sourceName: "测试书源")
        XCTAssertEqual(request.message, "测试书源 正在请求跳转链接/应用，是否跳转？")
    }

    func testTheRequestIsIdentifiable() {
        let request = OpenURLRequest(url: "https://example.com", mimeType: "text/plain", sourceKey: "key")
        XCTAssertEqual(request.id, "https://example.com|text/plain|key")
        XCTAssertNotEqual(request.id, OpenURLRequest(url: "https://example.com").id)
    }

    // MARK: - The coordinator

    func testTheAcceptedRequestReturnsTrue() throws {
        let coordinator = OpenURLCoordinator()
        coordinator.onRequest = { _ in coordinator.complete(true) }
        let accepted = try coordinator.confirmOpenURL(url: "https://example.com", sourceName: "书源")
        XCTAssertTrue(accepted)
    }

    func testTheRefusedRequestReturnsFalse() throws {
        let coordinator = OpenURLCoordinator()
        coordinator.onRequest = { _ in coordinator.complete(false) }
        let accepted = try coordinator.confirmOpenURL(url: "https://example.com")
        XCTAssertFalse(accepted)
    }

    func testTheRequestIsPublished() throws {
        let coordinator = OpenURLCoordinator()
        var published: OpenURLRequest?
        coordinator.onRequest = { request in
            published = request
            coordinator.complete(true)
        }
        _ = try coordinator.confirmOpenURL(
            url: "https://example.com/a",
            mimeType: "text/html",
            sourceKey: "key",
            sourceName: "书源"
        )
        XCTAssertEqual(published?.url, "https://example.com/a")
        XCTAssertEqual(published?.mimeType, "text/html")
        XCTAssertEqual(published?.sourceKey, "key")
        XCTAssertEqual(published?.sourceName, "书源")
    }

    func testAnEmptySourceKeyIsNil() throws {
        let coordinator = OpenURLCoordinator()
        var published: OpenURLRequest?
        coordinator.onRequest = { request in
            published = request
            coordinator.complete(true)
        }
        _ = try coordinator.confirmOpenURL(url: "https://example.com", sourceKey: "")
        XCTAssertNil(published?.sourceKey)
    }

    func testALongAddressIsRejected() {
        let coordinator = OpenURLCoordinator()
        let url = String(repeating: "a", count: 64 * 1024)
        XCTAssertThrowsError(try coordinator.confirmOpenURL(url: url)) { error in
            XCTAssertEqual(error as? ScriptEngineError, .verificationFailed("跳转地址过长"))
        }
    }

    func testThePendingRequestIsClearedAfterTheAnswer() throws {
        let coordinator = OpenURLCoordinator()
        coordinator.onRequest = { _ in coordinator.complete(true) }
        _ = try coordinator.confirmOpenURL(url: "https://example.com")
        XCTAssertNil(coordinator.pending)
    }

    func testTheCancelIsADenial() throws {
        let coordinator = OpenURLCoordinator()
        coordinator.onRequest = { _ in coordinator.cancel() }
        let accepted = try coordinator.confirmOpenURL(url: "https://example.com")
        XCTAssertFalse(accepted)
    }
}
