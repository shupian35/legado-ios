//
//  ReadRecordTests.swift
//  LegadoCoreTests
//
//  The reading records — upstream `ui/about/ReadRecordActivity.kt` and
//  `data/dao/ReadRecordDao.kt`.
//

import XCTest
@testable import LegadoCore

final class ReadRecordTests: XCTestCase {

    private var store: LegadoStore!
    private var model: ReadRecordModel!

    override func setUp() {
        super.setUp()
        store = LegadoStore(tables: MemoryTableStore())
        try? store.createSchema()
        model = ReadRecordModel(store: store)
    }

    override func tearDown() {
        store = nil
        model = nil
        super.tearDown()
    }

    private func insert(_ deviceId: String, _ bookName: String, _ readTime: Int64, _ lastRead: Int64) {
        try? store.insert(ReadRecord(deviceId: deviceId, bookName: bookName, readTime: readTime, lastRead: lastRead))
    }

    func testTheRecordsAreGroupedByTheBookName() throws {
        insert("device1", "书A", 1000, 100)
        insert("device2", "书A", 2000, 300)
        insert("device1", "书B", 500, 200)

        let records = try model.records()
        XCTAssertEqual(records.count, 2)
        let a = records.first { $0.bookName == "书A" }
        XCTAssertEqual(a?.readTime, 3000)
        XCTAssertEqual(a?.lastRead, 300)
    }

    func testTheSearchMatchesTheBookName() throws {
        insert("device1", "书A", 1000, 100)
        insert("device1", "书B", 500, 200)

        let records = try model.records(searchKey: "书A")
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.bookName, "书A")
    }

    func testTheSortByTheName() throws {
        insert("device1", "阿凡提", 1, 1)
        insert("device1", "白起", 1, 1)

        let records = try model.records(sort: .name)
        XCTAssertEqual(records.map(\.bookName), ["阿凡提", "白起"])
    }

    func testTheSortByTheReadingTime() throws {
        insert("device1", "书A", 100, 1)
        insert("device1", "书B", 300, 1)

        let records = try model.records(sort: .readTime)
        XCTAssertEqual(records.map(\.bookName), ["书B", "书A"])
    }

    func testTheSortByTheLastReading() throws {
        insert("device1", "书A", 1, 100)
        insert("device1", "书B", 1, 300)

        let records = try model.records(sort: .lastRead)
        XCTAssertEqual(records.map(\.bookName), ["书B", "书A"])
    }

    func testTheTotalTime() throws {
        insert("device1", "书A", 1000, 1)
        insert("device1", "书B", 2000, 1)
        XCTAssertEqual(try model.totalTime(), 3000)
    }

    func testDeletingTheRecordsOfABook() throws {
        insert("device1", "书A", 1000, 1)
        insert("device1", "书B", 2000, 1)

        try model.delete(bookName: "书A")
        let records = try model.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.bookName, "书B")
    }

    func testClearingEveryRecord() throws {
        insert("device1", "书A", 1000, 1)
        insert("device1", "书B", 2000, 1)

        try model.clear()
        XCTAssertEqual(try model.records().count, 0)
        XCTAssertEqual(try model.totalTime(), 0)
    }

    func testTheDurationText() {
        XCTAssertEqual(ReadRecordShow(bookName: "a", readTime: 0).readDurationText, "0秒")
        XCTAssertEqual(ReadRecordShow(bookName: "a", readTime: 5_000).readDurationText, "5秒")
        XCTAssertEqual(ReadRecordShow(bookName: "a", readTime: 65_000).readDurationText, "1分钟5秒")
        XCTAssertEqual(
            ReadRecordShow(bookName: "a", readTime: 3_661_000).readDurationText,
            "1小时1分钟1秒"
        )
        XCTAssertEqual(
            ReadRecordShow(bookName: "a", readTime: 90_061_000).readDurationText,
            "1天1小时1分钟1秒"
        )
    }

    func testTheLastReadTextIsEmptyWhenThereIsNoReading() {
        XCTAssertEqual(ReadRecordShow(bookName: "a", readTime: 1, lastRead: 0).lastReadText, "")
    }
}
