//
//  SimulatedReadingTests.swift
//  LegadoCoreTests
//
//  The simulated reading — upstream `help/book/BookExtensions.kt:355`
//  (`simulatedTotalChapterNum`) and `data/entities/Book.kt:163`
//  (`getUnreadChapterNum`).
//

import XCTest
@testable import LegadoCore

final class SimulatedReadingTests: XCTestCase {

    /// A book with `total` chapters and the simulation switched on.
    private func makeBook(total: Int64, startChapter: Int, dailyChapters: Int, startDate: String?) -> Book {
        var book = Book(bookUrl: "https://example.com/book", name: "书名", author: "作者")
        book.totalChapterNum = total
        var config = BookReadConfig()
        config.readSimulating = true
        config.startChapter = startChapter
        config.dailyChapters = dailyChapters
        config.startDate = startDate
        book.readConfigBox = config
        return book
    }

    func testWithoutTheSimulationTheRealCountIsUsed() {
        var book = Book(bookUrl: "https://example.com/book")
        book.totalChapterNum = 100
        XCTAssertFalse(book.readSimulating())
        XCTAssertEqual(book.simulatedTotalChapterNum(), 100)
    }

    func testTheSimulationUnlocksTheChaptersDayByDay() {
        // Started today with three chapters a day: today unlocks chapter 0…2.
        let book = makeBook(total: 100, startChapter: 0, dailyChapters: 3, startDate: "2026-01-01")
        let today = Book.simulationDateFormatter.date(from: "2026-01-01")!
        XCTAssertEqual(book.simulatedTotalChapterNum(now: today), 3)
        // The second day: 0 + 2 * 3 = 6.
        let secondDay = Book.simulationDateFormatter.date(from: "2026-01-02")!
        XCTAssertEqual(book.simulatedTotalChapterNum(now: secondDay), 6)
        // The fifth day: 0 + 5 * 3 = 15.
        let fifthDay = Book.simulationDateFormatter.date(from: "2026-01-05")!
        XCTAssertEqual(book.simulatedTotalChapterNum(now: fifthDay), 15)
    }

    func testTheStartChapterIsAddedToTheUnlockedChapters() {
        let book = makeBook(total: 100, startChapter: 10, dailyChapters: 2, startDate: "2026-01-01")
        let today = Book.simulationDateFormatter.date(from: "2026-01-01")!
        XCTAssertEqual(book.simulatedTotalChapterNum(now: today), 12)
    }

    func testTheSimulationNeverUnlocksMoreThanTheRealCount() {
        let book = makeBook(total: 5, startChapter: 0, dailyChapters: 10, startDate: "2026-01-01")
        let today = Book.simulationDateFormatter.date(from: "2026-01-01")!
        XCTAssertEqual(book.simulatedTotalChapterNum(now: today), 5)
    }

    func testTheUnreadCountFollowsTheSimulation() {
        var book = makeBook(total: 100, startChapter: 0, dailyChapters: 3, startDate: "2026-01-01")
        let today = Book.simulationDateFormatter.date(from: "2026-01-01")!
        book.durChapterIndex = 0
        XCTAssertEqual(book.unreadChapterNum(now: today), 2)
        book.durChapterIndex = 2
        XCTAssertEqual(book.unreadChapterNum(now: today), 0)
        // Never negative.
        book.durChapterIndex = 50
        XCTAssertEqual(book.unreadChapterNum(now: today), 0)
    }

    func testTheStartDateSurvivesTheReadConfigRoundTrip() {
        var book = Book(bookUrl: "https://example.com/book")
        var config = book.readConfigBox
        config.startDate = "2026-03-04"
        config.readSimulating = true
        book.readConfigBox = config
        XCTAssertEqual(book.readConfigBox.startDate, "2026-03-04")
        XCTAssertTrue(book.readConfigBox.readSimulating)
    }
}

final class BookTagTests: XCTestCase {

    func testTheTagsAreAddedAndRemoved() {
        var book = Book(bookUrl: "https://example.com/book")
        XCTAssertFalse(book.hasDelTag(BookTag.rubyTag.rawValue))
        var config = book.readConfigBox
        config.delTag = book.addingDelTag(BookTag.rubyTag.rawValue)
        book.readConfigBox = config
        XCTAssertTrue(book.hasDelTag(BookTag.rubyTag.rawValue))
        XCTAssertFalse(book.hasDelTag(BookTag.hTag.rawValue))
        config = book.readConfigBox
        config.delTag = book.removingDelTag(BookTag.rubyTag.rawValue)
        book.readConfigBox = config
        XCTAssertFalse(book.hasDelTag(BookTag.rubyTag.rawValue))
    }

    func testTheUpstreamTagValues() {
        XCTAssertEqual(BookTag.hTag.rawValue, 2)
        XCTAssertEqual(BookTag.rubyTag.rawValue, 4)
    }
}

final class SameTitleMarkerTests: XCTestCase {

    private func makeStorage() -> (BookCacheStorage, URL) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("legado-same-title-\(UUID().uuidString)")
        return (BookCacheStorage(layout: BookCacheLayout(root: root)), root)
    }

    func testTheMarkerKeepsTheDuplicatedTitle() {
        let (storage, root) = makeStorage()
        defer { try? FileManager.default.removeItem(at: root) }
        var book = Book(bookUrl: "https://example.com/book", name: "书名")
        let chapter = BookChapter(url: "https://example.com/1", title: "第一章", bookUrl: book.bookUrl)
        // Without the marker the duplicated title is removed.
        XCTAssertTrue(storage.isSameTitleRemoved(book: book, chapter: chapter))
        storage.setSameTitleRemoved(book: book, chapter: chapter, removed: false)
        XCTAssertFalse(storage.isSameTitleRemoved(book: book, chapter: chapter))
        storage.setSameTitleRemoved(book: book, chapter: chapter, removed: true)
        XCTAssertTrue(storage.isSameTitleRemoved(book: book, chapter: chapter))
    }
}
