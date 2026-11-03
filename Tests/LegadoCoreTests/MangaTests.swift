import XCTest
@testable import LegadoCore

/// The manga mode — upstream `ui/book/manga/*` + `model/ReadManga.kt`.
final class MangaTests: XCTestCase {

    // MARK: - The images of a chapter

    func testTheImageURLsAreResolvedAgainstTheChapterURL() {
        let content = "<p><img src=\"/img/1.png\"><img src='https://cdn.example.com/2.png'></p>"
        let urls = MangaAssembler.imageURLs(in: content, chapterURL: "https://example.com/book/1/1")
        XCTAssertEqual(urls, [
            "https://example.com/img/1.png",
            "https://cdn.example.com/2.png"
        ])
    }

    func testTheConsecutiveDuplicatesAreDropped() {
        // upstream `distinctUntilChanged` only removes the CONSECUTIVE duplicates
        let content = "<img src=\"a.png\"><img src=\"a.png\"><img src=\"b.png\"><img src=\"a.png\">"
        let urls = MangaAssembler.imageURLs(in: content, chapterURL: "https://example.com/c")
        XCTAssertEqual(urls, [
            "https://example.com/a.png",
            "https://example.com/b.png",
            "https://example.com/a.png"
        ])
    }

    // MARK: - The pages of a chapter

    private func chapter(isVolume: Bool = false, title: String = "第一章") -> BookChapter {
        BookChapter(url: "https://example.com/book/1/1", title: title, isVolume: isVolume, index: 0)
    }

    func testTheChapterHasAHeaderTheImagesAndAFooter() {
        let content = "<img src=\"1.png\"><img src=\"2.png\">"
        let manga = MangaAssembler.chapter(chapter(), chapterSize: 3, content: content)
        XCTAssertEqual(manga.imageCount, 2)
        XCTAssertEqual(manga.pages.count, 4)
        if case let .loading(title, _) = manga.pages[0].kind {
            XCTAssertEqual(title, "阅读 第一章")
        } else {
            XCTFail("the first page must be the header")
        }
        XCTAssertEqual(manga.pages[1].imageURL, "https://example.com/book/1/1.png")
        XCTAssertEqual(manga.pages[2].imageURL, "https://example.com/book/1/2.png")
        if case let .loading(title, _) = manga.pages[3].kind {
            XCTAssertEqual(title, "已读完 第一章")
        } else {
            XCTFail("the last page must be the footer")
        }
    }

    func testTheHiddenTitleDropsTheHeaderAndTheFooter() {
        let content = "<img src=\"1.png\">"
        let manga = MangaAssembler.chapter(chapter(), chapterSize: 3, content: content, hideTitle: true)
        XCTAssertEqual(manga.pages.count, 1)
        XCTAssertEqual(manga.pages[0].imageURL, "https://example.com/book/1/1.png")
    }

    func testAnEmptyVolumeChapterYieldsOneVolumePage() {
        let manga = MangaAssembler.chapter(chapter(isVolume: true), chapterSize: 1, content: "")
        XCTAssertEqual(manga.pages.count, 1)
        if case let .loading(title, isVolume) = manga.pages[0].kind {
            XCTAssertEqual(title, "第一章")
            XCTAssertTrue(isVolume)
        } else {
            XCTFail("a volume page must be a loading page")
        }
    }

    func testAnEmptyChapterStillHasTheHeaderAndTheFooter() {
        let manga = MangaAssembler.chapter(chapter(), chapterSize: 1, content: "")
        XCTAssertEqual(manga.pages.count, 2)
        XCTAssertEqual(manga.imageCount, 0)
    }

    // MARK: - The progress

    func testTheProgressFollowsTheUpstreamFormula() {
        // chapterIndex * 1.0 / chapterSize + 1.0 / chapterSize * (chapterPos + 1) / imageCount
        let ratio = MangaAssembler.progressRatio(
            chapterIndex: 1,
            chapterSize: 2,
            chapterPos: 0,
            imageCount: 4
        )
        XCTAssertEqual(ratio, 0.5 + 0.5 * 1.0 / 4.0, accuracy: 0.000_001)
    }

    func testTheFooterClampsToNinetyNinePointNinePercent() {
        let text = MangaAssembler.footerText(
            chapterTitle: "第一章",
            chapterIndex: 1,
            chapterSize: 2,
            chapterPos: 3,
            imageCount: 4,
            isLastItem: false
        )
        XCTAssertTrue(text.contains("99.9%"), text)
    }

    func testTheFooterKeepsOneHundredPercentForTheLastItem() {
        let text = MangaAssembler.footerText(
            chapterTitle: "第一章",
            chapterIndex: 1,
            chapterSize: 2,
            chapterPos: 3,
            imageCount: 4,
            isLastItem: true
        )
        XCTAssertTrue(text.contains("100.0%"), text)
    }

    // MARK: - The zoom and the tap zones

    func testTheZoomLimitsMatchTheUpstream() {
        XCTAssertEqual(MangaMode.Zoom.minRate, 0.5)
        XCTAssertEqual(MangaMode.Zoom.defaultRate, 1.0)
        XCTAssertEqual(MangaMode.Zoom.maxRate, 3.0)
        XCTAssertEqual(MangaMode.Zoom.doubleTapRate, 2.0)
        XCTAssertEqual(MangaMode.Zoom.animationDuration, 0.2)
        XCTAssertEqual(MangaMode.Zoom.flingFactor, 0.4)
        XCTAssertEqual(MangaMode.Zoom.clamp(0.1), 0.5)
        XCTAssertEqual(MangaMode.Zoom.clamp(9), 3.0)
    }

    func testTheTapZonesMatchTheUpstream() {
        XCTAssertEqual(MangaMode.TapZone.zone(x: 50, y: 50, width: 100, height: 100), .middle)
        XCTAssertEqual(MangaMode.TapZone.zone(x: 10, y: 90, width: 100, height: 100), .bottomLeft)
        XCTAssertEqual(MangaMode.TapZone.zone(x: 90, y: 90, width: 100, height: 100), .bottomRight)
        XCTAssertEqual(MangaMode.TapZone.zone(x: 10, y: 10, width: 100, height: 100), .other)
    }

    // MARK: - The filters

    func testTheColorFilterIsIdentityWhenEveryValueIsZero() {
        XCTAssertTrue(MangaColorFilter().isIdentity)
        XCTAssertFalse(MangaColorFilter(r: 10).isIdentity)
    }

    func testTheColorFilterMatrixUsesTheUpstreamFormula() {
        let filter = MangaColorFilter(r: 255, g: 0, b: 0)
        let matrix = filter.matrix
        XCTAssertEqual(matrix[0], 0, accuracy: 0.000_001)
        XCTAssertEqual(matrix[4], 255, accuracy: 0.000_001)
        XCTAssertEqual(matrix[6], 1, accuracy: 0.000_001)
    }

    func testTheEpaperFilterBinarisesTheGrayValue() {
        let filter = MangaEpaperFilter(threshold: 150)
        XCTAssertTrue(filter.isBlack(red: 0, green: 0, blue: 0))
        XCTAssertTrue(filter.isBlack(red: 100, green: 100, blue: 100))
        XCTAssertFalse(filter.isBlack(red: 255, green: 255, blue: 255))
        XCTAssertFalse(filter.isBlack(red: 200, green: 200, blue: 200))
    }
}
