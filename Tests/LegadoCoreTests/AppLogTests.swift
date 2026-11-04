import XCTest
@testable import LegadoCore

/// The in-memory app log — upstream `constant/AppLog.kt`.
final class AppLogTests: XCTestCase {

    func testPutRecordsTheNewestFirst() {
        let log = AppLog()
        log.put("first")
        log.put("second")
        XCTAssertEqual(log.logs.count, 2)
        XCTAssertEqual(log.logs.first?.message, "second")
        XCTAssertEqual(log.logs.last?.message, "first")
    }

    func testTheLimitDropsTheOldestEntry() {
        let log = AppLog()
        for index in 0..<(AppLog.limit + 10) {
            log.put("entry \(index)")
        }
        XCTAssertEqual(log.logs.count, AppLog.limit)
        // The newest entry is kept, the oldest ones are dropped.
        XCTAssertEqual(log.logs.first?.message, "entry \(AppLog.limit + 9)")
        XCTAssertEqual(log.logs.last?.message, "entry 10")
    }

    func testPutKeepsTheErrorDescription() {
        struct Failure: Error {}
        let log = AppLog()
        log.put("boom", error: Failure())
        XCTAssertNotNil(log.logs.first?.errorDescription)
        XCTAssertEqual(log.logs.first?.message, "boom")
    }

    func testAnEmptyMessageIsNotRecorded() {
        let log = AppLog()
        XCTAssertNil(log.put(""))
        XCTAssertTrue(log.logs.isEmpty)
    }

    func testPutDebugOnlyRecordsWhenThePreferenceIsOn() {
        let log = AppLog()
        log.putDebug("debug", recordLog: false)
        XCTAssertTrue(log.logs.isEmpty)
        log.putDebug("debug", recordLog: true)
        XCTAssertEqual(log.logs.count, 1)
    }

    func testClearRemovesEverything() {
        let log = AppLog()
        log.put("one")
        log.put("two")
        log.clear()
        XCTAssertTrue(log.logs.isEmpty)
    }

    func testTheTimeFormat() {
        // The upstream format is "MM-dd HH:mm:ss" in the local time zone.
        let text = AppLog.formatTime(Date(timeIntervalSince1970: 1_762_329_983))
        let pattern = #"^\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"#
        XCTAssertNotNil(text.range(of: pattern, options: .regularExpression))
    }
}
