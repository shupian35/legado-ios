import XCTest
@testable import LegadoCore

/// The reader's header and footer tips — the port of
/// `app/src/main/java/io/legado/app/help/config/ReadTipConfig.kt` and
/// `ui/book/read/page/PageView.kt`.
final class ReaderTipTests: XCTestCase {

    private func context(
        bookName: String = "斗破苍穹",
        chapterTitle: String = "第一章 陨落的天才",
        pageIndex: Int = 0,
        pageSize: Int = 10,
        chapterIndex: Int = 2,
        chapterSize: Int = 100,
        readProgress: String = "3.5%",
        isChapterCompleted: Bool = true,
        batteryLevel: Int = 80
    ) -> ReaderTipContext {
        ReaderTipContext(
            bookName: bookName,
            chapterTitle: chapterTitle,
            pageIndex: pageIndex,
            pageSize: pageSize,
            chapterIndex: chapterIndex,
            chapterSize: chapterSize,
            readProgress: readProgress,
            isChapterCompleted: isChapterCompleted,
            time: Date(timeIntervalSince1970: 0),
            batteryLevel: batteryLevel
        )
    }

    func testTheTipConstantsMatchTheUpstream() {
        XCTAssertEqual(ReaderTipType.none.rawValue, 0)
        XCTAssertEqual(ReaderTipType.chapterTitle.rawValue, 1)
        XCTAssertEqual(ReaderTipType.time.rawValue, 2)
        XCTAssertEqual(ReaderTipType.battery.rawValue, 3)
        XCTAssertEqual(ReaderTipType.page.rawValue, 4)
        XCTAssertEqual(ReaderTipType.totalProgress.rawValue, 5)
        XCTAssertEqual(ReaderTipType.pageAndTotal.rawValue, 6)
        XCTAssertEqual(ReaderTipType.bookName.rawValue, 7)
        XCTAssertEqual(ReaderTipType.timeBattery.rawValue, 8)
        XCTAssertEqual(ReaderTipType.timeBatteryPercentage.rawValue, 9)
        XCTAssertEqual(ReaderTipType.batteryPercentage.rawValue, 10)
        XCTAssertEqual(ReaderTipType.totalProgress1.rawValue, 11)
    }

    func testThePickerOrderMatchesTheUpstream() {
        XCTAssertEqual(
            ReaderTipType.pickerOrder.map(\.rawValue),
            [0, 7, 1, 2, 3, 10, 4, 5, 11, 6, 8, 9]
        )
    }

    func testTheTextsMatchTheUpstream() {
        let context = context()
        XCTAssertNil(ReaderTipRenderer.text(for: .none, context: context))
        XCTAssertEqual(ReaderTipRenderer.text(for: .bookName, context: context), "斗破苍穹")
        XCTAssertEqual(ReaderTipRenderer.text(for: .chapterTitle, context: context), "第一章 陨落的天才")
        XCTAssertEqual(ReaderTipRenderer.text(for: .battery, context: context), "80")
        XCTAssertEqual(ReaderTipRenderer.text(for: .batteryPercentage, context: context), "80%")
        XCTAssertEqual(ReaderTipRenderer.text(for: .page, context: context), "1/10")
        XCTAssertEqual(ReaderTipRenderer.text(for: .totalProgress, context: context), "3.5%")
        XCTAssertEqual(ReaderTipRenderer.text(for: .totalProgress1, context: context), "3/100")
        XCTAssertEqual(ReaderTipRenderer.text(for: .pageAndTotal, context: context), "1/10  3.5%")
    }

    func testThePageNumberIsApproximateWhileTheChapterLoads() {
        XCTAssertEqual(
            ReaderTipRenderer.pageText(index: 0, pageSize: 10, isChapterCompleted: true),
            "1/10"
        )
        XCTAssertEqual(
            ReaderTipRenderer.pageText(index: 0, pageSize: 10, isChapterCompleted: false),
            "1/~10"
        )
        XCTAssertEqual(
            ReaderTipRenderer.pageText(index: 2, pageSize: 0, isChapterCompleted: false),
            "3/-"
        )
    }

    func testTheClockUsesTheUpstreamFormat() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let expected = formatter.string(from: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(ReaderTipRenderer.formatTime(Date(timeIntervalSince1970: 0)), expected)
    }

    func testTheHeaderAndTheFooterModes() {
        XCTAssertFalse(ReaderTipMode.automatic.isVisible(statusBarVisible: true))
        XCTAssertTrue(ReaderTipMode.automatic.isVisible(statusBarVisible: false))
        XCTAssertTrue(ReaderTipMode.always.isVisible(statusBarVisible: true))
        XCTAssertFalse(ReaderTipMode.never.isVisible(statusBarVisible: false))
    }

    func testTheDefaultConfigurationMatchesTheUpstream() {
        let config = ReaderConfig()
        XCTAssertEqual(config.tipHeaderLeft, ReaderTipType.time.rawValue)
        XCTAssertEqual(config.tipHeaderMiddle, ReaderTipType.none.rawValue)
        XCTAssertEqual(config.tipHeaderRight, ReaderTipType.battery.rawValue)
        XCTAssertEqual(config.tipFooterLeft, ReaderTipType.chapterTitle.rawValue)
        XCTAssertEqual(config.tipFooterMiddle, ReaderTipType.none.rawValue)
        XCTAssertEqual(config.tipFooterRight, ReaderTipType.pageAndTotal.rawValue)
        XCTAssertEqual(config.headerMode, 0)
        XCTAssertEqual(config.footerMode, 0)
        XCTAssertEqual(config.tipColor, 0)
        XCTAssertEqual(config.tipDividerColor, -1)
    }

    func testTheLayoutIsBuiltFromTheConfiguration() {
        let config = ReaderConfig()
        let layout = config.tipLayout
        XCTAssertEqual(layout.header.left, .time)
        XCTAssertEqual(layout.header.middle, .none)
        XCTAssertEqual(layout.header.right, .battery)
        XCTAssertEqual(layout.footer.left, .chapterTitle)
        XCTAssertEqual(layout.footer.middle, .none)
        XCTAssertEqual(layout.footer.right, .pageAndTotal)
        XCTAssertTrue(layout.showsFooter())
        XCTAssertFalse(layout.showsHeader(statusBarVisible: true))
    }
}
