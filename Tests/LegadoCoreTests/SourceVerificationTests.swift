//
//  SourceVerificationTests.swift
//  LegadoCoreTests
//
//  The source verification — the captcha the user has to solve when a book
//  source asks for it.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/help/source/SourceVerificationHelp.kt
//  app/src/main/java/io/legado/app/ui/association/VerificationCodeDialog.kt
//

import XCTest
@testable import LegadoCore

final class SourceVerificationTests: XCTestCase {

    /// The verification runs on a background thread — the upstream refuses to
    /// run it on the main thread (`check(!isMainThread)`).
    private func onBackgroundThread<T>(_ body: @escaping () throws -> T) rethrows -> T? {
        var result: Result<T, Error>?
        let thread = Thread {
            result = Result { try body() }
        }
        thread.start()
        // The thread has to finish before the test ends.
        while result == nil {
            Thread.sleep(forTimeInterval: 0.005)
        }
        return try? result!.get()
    }

    func testTheCaptchaRequestIsPublishedAndTheAnswerComesBack() throws {
        let coordinator = SourceVerificationCoordinator()
        var published: SourceVerificationRequest?
        coordinator.onRequest = { request in
            published = request
            // The user answers right away.
            coordinator.complete("1234")
        }
        let answer = try onBackgroundThread {
            try coordinator.verificationCode(
                imageURL: "https://example.com/captcha.png",
                sourceKey: "key1",
                sourceName: "测试书源"
            )
        }
        XCTAssertEqual(answer, "1234")
        XCTAssertEqual(published?.kind, .captcha)
        XCTAssertEqual(published?.imageURL, "https://example.com/captcha.png")
        XCTAssertEqual(published?.sourceKey, "key1")
        XCTAssertEqual(published?.sourceName, "测试书源")
    }

    func testTheBrowserRequestCarriesTheAddress() throws {
        let coordinator = SourceVerificationCoordinator()
        var published: SourceVerificationRequest?
        coordinator.onRequest = { request in
            published = request
            coordinator.complete("<html>ok</html>")
        }
        let answer = try onBackgroundThread {
            try coordinator.browserResult(url: "https://example.com/check", sourceKey: "key2")
        }
        XCTAssertEqual(answer, "<html>ok</html>")
        XCTAssertEqual(published?.kind, .browser)
        XCTAssertEqual(published?.url, "https://example.com/check")
        XCTAssertNil(published?.imageURL)
    }

    func testTheCancelReportsTheEmptyResult() {
        let coordinator = SourceVerificationCoordinator()
        coordinator.onRequest = { _ in
            coordinator.cancel()
        }
        var caught: Error?
        _ = onBackgroundThread {
            do {
                _ = try coordinator.verificationCode(
                    imageURL: "https://example.com/captcha.png",
                    sourceKey: "key3"
                )
            } catch {
                caught = error
            }
        }
        XCTAssertNotNil(caught)
        XCTAssertEqual((caught as? ScriptEngineError)?.message, "验证结果为空")
    }

    func testTheTimeoutIsReported() {
        let coordinator = SourceVerificationCoordinator(timeout: 0.05)
        coordinator.onRequest = { _ in
            // Nobody answers.
        }
        var caught: Error?
        _ = onBackgroundThread {
            do {
                _ = try coordinator.verificationCode(
                    imageURL: "https://example.com/captcha.png",
                    sourceKey: "key4"
                )
            } catch {
                caught = error
            }
        }
        XCTAssertNotNil(caught)
        XCTAssertEqual((caught as? ScriptEngineError)?.message, "验证超时")
    }

    func testTheVerificationRefusesToRunOnTheMainThread() {
        let coordinator = SourceVerificationCoordinator()
        var caught: Error?
        do {
            _ = try coordinator.verificationCode(
                imageURL: "https://example.com/captcha.png",
                sourceKey: "key5"
            )
        } catch {
            caught = error
        }
        XCTAssertNotNil(caught)
        XCTAssertEqual((caught as? ScriptEngineError)?.message, "验证必须在后台线程调用")
    }

    func testTheAddressMayNotBeTooLong() {
        let coordinator = SourceVerificationCoordinator()
        let long = String(repeating: "a", count: 64 * 1024)
        var caught: Error?
        _ = onBackgroundThread {
            do {
                _ = try coordinator.browserResult(url: long, sourceKey: "key6")
            } catch {
                caught = error
            }
        }
        XCTAssertNotNil(caught)
        XCTAssertEqual((caught as? ScriptEngineError)?.message, "验证地址过长")
    }

    func testThePendingRequestIsClearedAfterTheAnswer() throws {
        let coordinator = SourceVerificationCoordinator()
        coordinator.onRequest = { _ in
            coordinator.complete("42")
        }
        _ = try onBackgroundThread {
            try coordinator.verificationCode(
                imageURL: "https://example.com/captcha.png",
                sourceKey: "key7"
            )
        }
        XCTAssertNil(coordinator.pending)
    }
}
