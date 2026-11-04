//
//  SourceConfigTests.swift
//  LegadoCoreTests
//
//  The user rating of the books of a source — the "好评 / 差评" of the change
//  source dialog.
//
//  Upstream:
//  app/src/main/java/io/legado/app/help/config/SourceConfig.kt
//

import XCTest
@testable import LegadoCore

final class SourceConfigTests: XCTestCase {

    // MARK: - The scores

    func testTheGoodScoreIsStoredForTheBookAndTheSource() {
        var config = SourceConfig()
        config.setBookScore(origin: "src", name: "书", author: "作者", score: 1)
        XCTAssertEqual(config.bookScore(origin: "src", name: "书", author: "作者"), 1)
        XCTAssertEqual(config.sourceScore(origin: "src"), 1)
    }

    func testTheBadScoreIsStoredForTheBookAndTheSource() {
        var config = SourceConfig()
        config.setBookScore(origin: "src", name: "书", author: "作者", score: -1)
        XCTAssertEqual(config.bookScore(origin: "src", name: "书", author: "作者"), -1)
        XCTAssertEqual(config.sourceScore(origin: "src"), -1)
    }

    /// Upstream `SourceConfig.setBookScore` — the score of the book is
    /// absolute, the total of the source gets the DELTA.
    func testChangingTheScoreAdjustsTheTotalOfTheSource() {
        var config = SourceConfig()
        config.setBookScore(origin: "src", name: "书", author: "作者", score: 1)
        // The good → the bad: the delta is -1 - 1 = -2.
        config.setBookScore(origin: "src", name: "书", author: "作者", score: -1)
        XCTAssertEqual(config.bookScore(origin: "src", name: "书", author: "作者"), -1)
        XCTAssertEqual(config.sourceScore(origin: "src"), -1)
    }

    func testResettingTheScoreRestoresTheTotalOfTheSource() {
        var config = SourceConfig()
        config.setBookScore(origin: "src", name: "书", author: "作者", score: 1)
        config.setBookScore(origin: "src", name: "书", author: "作者", score: 0)
        XCTAssertEqual(config.bookScore(origin: "src", name: "书", author: "作者"), 0)
        XCTAssertEqual(config.sourceScore(origin: "src"), 0)
    }

    func testTheScoresOfDifferentBooksAreIndependent() {
        var config = SourceConfig()
        config.setBookScore(origin: "src", name: "书A", author: "作者", score: 1)
        config.setBookScore(origin: "src", name: "书B", author: "作者", score: -1)
        XCTAssertEqual(config.bookScore(origin: "src", name: "书A", author: "作者"), 1)
        XCTAssertEqual(config.bookScore(origin: "src", name: "书B", author: "作者"), -1)
        XCTAssertEqual(config.sourceScore(origin: "src"), 0)
    }

    /// Upstream `SourceConfig.removeSource` — every key that starts with the
    /// origin is removed.
    func testRemovingASourceRemovesItsScores() {
        var config = SourceConfig()
        config.setBookScore(origin: "src", name: "书", author: "作者", score: 1)
        config.setBookScore(origin: "other", name: "书", author: "作者", score: 1)
        config.removeSource(origin: "src")
        XCTAssertEqual(config.bookScore(origin: "src", name: "书", author: "作者"), 0)
        XCTAssertEqual(config.sourceScore(origin: "src"), 0)
        XCTAssertEqual(config.bookScore(origin: "other", name: "书", author: "作者"), 1)
    }

    func testTheKeyOfABook() {
        XCTAssertEqual(
            SourceConfig.bookKey(origin: "src", name: "书", author: "作者"),
            "src_书_作者"
        )
    }

    // MARK: - The persistence

    func testTheJSONRoundTrip() {
        var config = SourceConfig()
        config.setBookScore(origin: "src", name: "书", author: "作者", score: 1)
        let restored = SourceConfig.parse(config.jsonString)
        XCTAssertEqual(restored.bookScore(origin: "src", name: "书", author: "作者"), 1)
        XCTAssertEqual(restored.sourceScore(origin: "src"), 1)
    }

    func testABrokenJSONGivesTheEmptyConfiguration() {
        let config = SourceConfig.parse("not json")
        XCTAssertTrue(config.bookScores.isEmpty)
        XCTAssertTrue(config.sourceScores.isEmpty)
    }

    func testTheConfigurationIsStoredInTheStore() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        var config = SourceConfig()
        config.setBookScore(origin: "src", name: "书", author: "作者", score: 1)
        SourceConfig.save(config, store: store)
        let loaded = SourceConfig.load(store: store)
        XCTAssertEqual(loaded.bookScore(origin: "src", name: "书", author: "作者"), 1)
        XCTAssertEqual(loaded.sourceScore(origin: "src"), 1)
    }

    func testAnEmptyStoreGivesTheEmptyConfiguration() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        let loaded = SourceConfig.load(store: store)
        XCTAssertTrue(loaded.bookScores.isEmpty)
    }

    // MARK: - The order of a moved source

    func testTheTopOrderIsBelowTheSmallestOrder() {
        let sources = [
            BookSource(bookSourceUrl: "a", bookSourceName: "A", customOrder: 3),
            BookSource(bookSourceUrl: "b", bookSourceName: "B", customOrder: -2)
        ]
        XCTAssertEqual(SourceOrdering.topOrder(of: sources), -3)
    }

    func testTheBottomOrderIsAboveTheBiggestOrder() {
        let sources = [
            BookSource(bookSourceUrl: "a", bookSourceName: "A", customOrder: 3),
            BookSource(bookSourceUrl: "b", bookSourceName: "B", customOrder: -2)
        ]
        XCTAssertEqual(SourceOrdering.bottomOrder(of: sources), 4)
    }
}
