//
//  HttpTtsPlaybackTests.swift
//  LegadoCoreTests
//
//  Tests for the playback plan of the HTTP TTS engine.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/service/HttpReadAloudService.kt
//

import XCTest
@testable import LegadoCore

final class HttpTtsPlaybackTests: XCTestCase {

    private let url = "https://tts.example.com/say"
    private let rate = 15

    func testTheDeliveryModeDefaultsToDownloading() {
        XCTAssertEqual(HttpTtsDelivery.default, .download)
        XCTAssertEqual(HttpTtsDelivery.allCases.count, 2)
    }

    func testTheTextThatIsReallySpoken() {
        // A paragraph with letters is spoken as it is.
        XCTAssertEqual(HttpTtsPlayback.speakText("你好，世界"), "你好，世界")
        // A paragraph that only holds punctuation is silent.
        XCTAssertEqual(HttpTtsPlayback.speakText("……"), "")
        XCTAssertEqual(HttpTtsPlayback.speakText("   "), "")
        XCTAssertEqual(HttpTtsPlayback.speakText("·—《》"), "")
    }

    func testTheSilentParagraph() {
        let item = HttpTtsPlayback.item(
            text: "……",
            chapterTitle: "第一章",
            ttsUrl: url,
            speechRate: rate
        )
        XCTAssertTrue(item.isSilent)
        XCTAssertEqual(item.speakText, "")
        XCTAssertEqual(item.text, "……")
    }

    func testTheNameOfTheCachedFile() {
        // Upstream `md5Encode16(chapterTitle) + "_" +
        // md5Encode16("url-|-rate-|-content")`.
        let name = HttpTtsPlayback.fileName(
            text: "第一段",
            chapterTitle: "第一章",
            ttsUrl: url,
            speechRate: rate
        )
        let title = ScriptDigest.md5Encode16("第一章")
        let content = ScriptDigest.md5Encode16("\(url)|-\(rate)|-第一段")
        XCTAssertEqual(name, "\(title)_\(content)")
    }

    func testTheNameChangesWithTheSpeed() {
        let slow = HttpTtsPlayback.fileName(
            text: "第一段",
            chapterTitle: "第一章",
            ttsUrl: url,
            speechRate: 10
        )
        let fast = HttpTtsPlayback.fileName(
            text: "第一段",
            chapterTitle: "第一章",
            ttsUrl: url,
            speechRate: 20
        )
        XCTAssertNotEqual(slow, fast)
    }

    func testThePlanHasOneItemPerParagraph() {
        let plan = HttpTtsPlayback.plan(
            paragraphs: ["第一段", "第二段", "……"],
            chapterTitle: "第一章",
            ttsUrl: url,
            speechRate: rate
        )
        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual(plan.map(\.text), ["第一段", "第二段", "……"])
        XCTAssertFalse(plan[0].isSilent)
        XCTAssertTrue(plan[2].isSilent)
        // The names are different for every paragraph.
        XCTAssertEqual(Set(plan.map(\.fileName)).count, 3)
    }

    func testThePreDownloadTakesTheFirstTenParagraphs() {
        let paragraphs = (1...15).map { "第\($0)段" }
        let plan = HttpTtsPlayback.preDownloadPlan(
            paragraphs: paragraphs,
            chapterTitle: "第二章",
            ttsUrl: url,
            speechRate: rate
        )
        XCTAssertEqual(plan.count, 10)
        XCTAssertEqual(plan.first?.text, "第1段")
        XCTAssertEqual(plan.last?.text, "第10段")
    }

    func testThePartThatWasAlreadySpokenIsRemoved() {
        XCTAssertEqual(HttpTtsPlayback.remainingText("你好世界", from: 0), "你好世界")
        XCTAssertEqual(HttpTtsPlayback.remainingText("你好世界", from: 2), "世界")
        XCTAssertEqual(HttpTtsPlayback.remainingText("你好世界", from: 9), "")
    }
}
