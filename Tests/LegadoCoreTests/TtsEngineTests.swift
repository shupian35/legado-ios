//
//  TtsEngineTests.swift
//  LegadoCoreTests
//
//  The read-aloud engine resolution and the auto-stop timer.
//
//  Upstream source of truth:
//  app/src/main/java/io/legado/app/model/ReadAloud.kt:24,32-33
//  app/src/main/java/io/legado/app/ui/book/read/config/SpeakEngineDialog.kt:143-152
//  app/src/main/java/io/legado/app/service/BaseReadAloudService.kt:392-432
//

import XCTest
@testable import LegadoCore

final class TtsEngineTests: XCTestCase {

    // MARK: - The engine of the book wins over the global one

    func testResolvePrefersTheBookEngine() {
        XCTAssertEqual(
            TtsEngine.resolve(bookEngine: "12", globalEngine: "34"),
            "12"
        )
    }

    func testResolveFallsBackToTheGlobalEngine() {
        XCTAssertEqual(
            TtsEngine.resolve(bookEngine: nil, globalEngine: "34"),
            "34"
        )
    }

    func testResolveIgnoresABlankBookEngine() {
        XCTAssertEqual(
            TtsEngine.resolve(bookEngine: "", globalEngine: "34"),
            "34"
        )
    }

    func testResolveReturnsNilWhenNothingIsSet() {
        XCTAssertNil(TtsEngine.resolve(bookEngine: nil, globalEngine: nil))
        XCTAssertNil(TtsEngine.resolve(bookEngine: "", globalEngine: ""))
    }

    // MARK: - The profile id

    func testProfileIdOfANumericEngine() {
        XCTAssertEqual(TtsEngine.profileId(of: "42"), 42)
        XCTAssertEqual(TtsEngine.profileId(of: "0"), 0)
    }

    func testProfileIdOfANonNumericEngine() {
        // The upstream stores a JSON object for the system engines.
        XCTAssertNil(TtsEngine.profileId(of: "{\"type\":\"system\"}"))
        XCTAssertNil(TtsEngine.profileId(of: "not a number"))
        XCTAssertNil(TtsEngine.profileId(of: nil))
    }

    // MARK: - The engine of a book

    func testEngineOfABookReadsTheReadConfig() {
        var book = Book()
        book.bookUrl = "https://example.com/book"
        XCTAssertNil(TtsEngine.engine(of: book))
        var config = book.readConfigBox
        config.ttsEngine = "7"
        book.readConfigBox = config
        XCTAssertEqual(TtsEngine.engine(of: book), "7")
    }

    func testEngineOfANilBook() {
        XCTAssertNil(TtsEngine.engine(of: nil))
    }

    // MARK: - The profile of an engine

    func testProfileOfAnEngineReadsTheStore() throws {
        let store = try makeStore()
        let profile = HttpTTS(id: 9, name: "测试引擎", url: "http://tts.local")
        try store.insert(profile)

        let resolved = TtsEngine.profile(
            of: TtsEngine.resolve(bookEngine: "9", globalEngine: nil),
            store: store
        )
        XCTAssertEqual(resolved?.name, "测试引擎")
    }

    func testProfileOfAMissingEngine() throws {
        let store = try makeStore()
        XCTAssertNil(
            TtsEngine.profile(
                of: TtsEngine.resolve(bookEngine: "404", globalEngine: nil),
                store: store
            )
        )
    }

    // MARK: - The helper

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        return store
    }
}

final class ReadAloudTimerTests: XCTestCase {

    func testTimerCountsDown() {
        var timer = ReadAloudTimer(minutes: 3)
        XCTAssertEqual(timer.remaining, 3)
        XCTAssertFalse(timer.tick(paused: false))
        XCTAssertEqual(timer.remaining, 2)
        XCTAssertFalse(timer.tick(paused: false))
        XCTAssertEqual(timer.remaining, 1)
        XCTAssertTrue(timer.tick(paused: false))
        XCTAssertEqual(timer.remaining, 0)
    }

    func testTimerDoesNotCountWhilePaused() {
        // Upstream `doDs()`: `if (!pause) { timeMinute-- }`.
        var timer = ReadAloudTimer(minutes: 5)
        XCTAssertFalse(timer.tick(paused: true))
        XCTAssertEqual(timer.remaining, 5)
        XCTAssertFalse(timer.tick(paused: false))
        XCTAssertEqual(timer.remaining, 4)
    }

    func testTimerIsInactiveWhenItWasNotStarted() {
        var timer = ReadAloudTimer()
        XCTAssertEqual(timer.minutes, 0)
        XCTAssertFalse(timer.tick(paused: false))
    }

    func testTimerAddsTenMinutes() {
        // Upstream `addTimer()`: `timeMinute += 10`.
        var timer = ReadAloudTimer(minutes: 20)
        timer.add()
        XCTAssertEqual(timer.minutes, 30)
        XCTAssertEqual(timer.remaining, 30)
    }

    func testTimerStopsAtOneHundredEightyMinutes() {
        var timer = ReadAloudTimer(minutes: 180)
        timer.add()
        XCTAssertEqual(timer.minutes, 0)
        XCTAssertEqual(timer.remaining, 0)
    }

    func testTimerWrapsAroundAtTheCap() {
        // The upstream: `if (timeMinute > 180) timeMinute = 0`.
        var timer = ReadAloudTimer(minutes: 180)
        timer.add()
        XCTAssertEqual(timer.minutes, 0)
        timer.add()
        XCTAssertEqual(timer.minutes, 10)
    }

    func testTimerCancel() {
        var timer = ReadAloudTimer(minutes: 30)
        timer.cancel()
        XCTAssertEqual(timer.minutes, 0)
        XCTAssertEqual(timer.remaining, 0)
    }
}
