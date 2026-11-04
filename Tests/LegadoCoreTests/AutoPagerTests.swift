//
//  AutoPagerTests.swift
//  LegadoCoreTests
//
//  The auto pager — upstream `ui/book/read/page/AutoPager.kt`.
//

import XCTest
@testable import LegadoCore

final class AutoPagerTests: XCTestCase {

    // MARK: - The configuration

    func testTheSpeedIsClampedToAtLeastOneSecond() {
        XCTAssertEqual(AutoPager.Configuration(speed: 0).speed, 1)
        XCTAssertEqual(AutoPager.Configuration(speed: -5).speed, 1)
        XCTAssertEqual(AutoPager.Configuration(speed: 10).speed, 10)
    }

    // MARK: - The page-turn mode

    func testThePageTurnModeTurnsThePage() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .pageTurn))
        var turns: [PageTurnDirection] = []
        pager.onTurn = { direction in
            turns.append(direction)
            return true
        }
        pager.start()
        XCTAssertTrue(pager.tick(elapsed: 10))
        XCTAssertEqual(turns, [.next])
    }

    func testThePageTurnModeStopsAtTheEndOfTheBook() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .pageTurn))
        pager.onTurn = { _ in false }
        pager.start()
        XCTAssertFalse(pager.tick(elapsed: 10))
        XCTAssertFalse(pager.isRunning)
    }

    // MARK: - The scroll mode

    func testTheScrollModeAccumulatesTheOffset() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .scroll))
        var scroll: [Double] = []
        pager.onScroll = { scroll.append($0) }
        pager.onTurn = { _ in true }
        pager.start()
        // 100 points high, 10 seconds per page: after 5 seconds half a page.
        pager.tick(elapsed: 5, pageHeight: 100)
        XCTAssertEqual(scroll.last ?? 0, 0.5, accuracy: 0.0001)
    }

    func testTheScrollModeTurnsThePageWhenThePageIsFull() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .scroll))
        var turns = 0
        pager.onTurn = { _ in
            turns += 1
            return true
        }
        pager.start()
        // 100 points high, 10 seconds per page: after 10 seconds the page is
        // full and the pager turns to the next one.
        XCTAssertTrue(pager.tick(elapsed: 10, pageHeight: 100))
        XCTAssertEqual(turns, 1)
        XCTAssertEqual(pager.pageProgress, 0, accuracy: 0.0001)
    }

    func testTheScrollModeStopsAtTheEndOfTheBook() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .scroll))
        pager.onTurn = { _ in false }
        pager.start()
        XCTAssertFalse(pager.tick(elapsed: 10, pageHeight: 100))
        XCTAssertFalse(pager.isRunning)
    }

    func testTheScrollModeKeepsTheRemainder() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .scroll))
        pager.onTurn = { _ in true }
        pager.start()
        // 100 points high, 10 seconds per page: 3 seconds is 30 points, then
        // another 8 seconds is 80 points — 110 points in total, so the page
        // turns and 10 points are left over.
        pager.tick(elapsed: 3, pageHeight: 100)
        XCTAssertTrue(pager.tick(elapsed: 8, pageHeight: 100))
    }

    // MARK: - The progress mode

    func testTheProgressModeGrowsTheProgress() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .progress))
        var scroll: [Double] = []
        pager.onScroll = { scroll.append($0) }
        pager.onTurn = { _ in true }
        pager.start()
        pager.tick(elapsed: 5)
        XCTAssertEqual(scroll.last ?? 0, 0.5, accuracy: 0.0001)
        XCTAssertEqual(pager.pageProgress, 0.5, accuracy: 0.0001)
    }

    func testTheProgressModeTurnsThePageWhenTheTimeIsUp() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .progress))
        var turns = 0
        pager.onTurn = { _ in
            turns += 1
            return true
        }
        pager.start()
        XCTAssertTrue(pager.tick(elapsed: 9))
        XCTAssertEqual(turns, 0)
        XCTAssertTrue(pager.tick(elapsed: 1))
        XCTAssertEqual(turns, 1)
        // The progress starts again on the next page.
        XCTAssertEqual(pager.pageProgress, 0, accuracy: 0.0001)
    }

    func testTheProgressModeStopsAtTheEndOfTheBook() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .progress))
        pager.onTurn = { _ in false }
        pager.start()
        XCTAssertFalse(pager.tick(elapsed: 10))
        XCTAssertFalse(pager.isRunning)
    }

    func testTheProgressModeNeverReportsMoreThanOne() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .progress))
        var scroll: [Double] = []
        pager.onScroll = { scroll.append($0) }
        pager.onTurn = { _ in false }
        pager.start()
        pager.tick(elapsed: 30)
        XCTAssertEqual(scroll.last ?? 0, 1, accuracy: 0.0001)
    }

    // MARK: - The state

    func testAPausedPagerDoesNotAdvance() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .pageTurn))
        var turns = 0
        pager.onTurn = { _ in
            turns += 1
            return true
        }
        pager.start()
        pager.pause()
        XCTAssertTrue(pager.tick(elapsed: 10))
        XCTAssertEqual(turns, 0)
        pager.resume()
        XCTAssertTrue(pager.tick(elapsed: 10))
        XCTAssertEqual(turns, 1)
    }

    func testAStoppedPagerDoesNotAdvance() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .pageTurn))
        var turns = 0
        pager.onTurn = { _ in
            turns += 1
            return true
        }
        pager.start()
        pager.stop()
        XCTAssertTrue(pager.tick(elapsed: 10))
        XCTAssertEqual(turns, 0)
        XCTAssertFalse(pager.isRunning)
    }

    func testStartingResetsTheProgress() {
        let pager = AutoPager(configuration: .init(speed: 10, mode: .scroll))
        pager.onTurn = { _ in true }
        pager.start()
        pager.tick(elapsed: 3, pageHeight: 100)
        XCTAssertGreaterThan(pager.pageProgress, 0)
        pager.start()
        XCTAssertEqual(pager.pageProgress, 0, accuracy: 0.0001)
    }
}
