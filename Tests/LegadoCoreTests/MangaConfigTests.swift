import XCTest
@testable import LegadoCore

/// The manga settings — upstream `ui/book/manga/config/`.
final class MangaConfigTests: XCTestCase {

    // MARK: - The colour filter

    func testTheEmptyFilterIsStoredAsAnEmptyString() {
        XCTAssertEqual(MangaColorFilter().jsonString(), "")
        XCTAssertTrue(MangaColorFilter().isIdentity)
    }

    func testTheColourFilterRoundTrip() {
        let filter = MangaColorFilter(r: 10, g: 20, b: 30, a: 40, l: 50)
        let json = filter.jsonString()
        XCTAssertFalse(json.isEmpty)
        XCTAssertEqual(MangaColorFilter.parse(json), filter)
    }

    func testTheColourFilterMultipliersFollowTheUpstreamMatrix() {
        // Upstream `MangaAdapter.setImageColorFilter` — `(255 - x) / 255`.
        let filter = MangaColorFilter(r: 255, g: 0, b: 51, a: 0, l: 0)
        let multipliers = filter.multipliers
        XCTAssertEqual(multipliers.red, 0, accuracy: 0.0001)
        XCTAssertEqual(multipliers.green, 1, accuracy: 0.0001)
        XCTAssertEqual(multipliers.blue, 0.8, accuracy: 0.0001)
        XCTAssertEqual(multipliers.alpha, 1, accuracy: 0.0001)
    }

    func testParsingAnInvalidColourFilterGivesTheDefault() {
        XCTAssertEqual(MangaColorFilter.parse("not json"), MangaColorFilter())
        XCTAssertEqual(MangaColorFilter.parse(nil), MangaColorFilter())
        XCTAssertEqual(MangaColorFilter.parse(""), MangaColorFilter())
    }

    // MARK: - The footer configuration

    func testTheFooterConfigurationDefaults() {
        let config = MangaFooterConfig()
        XCTAssertFalse(config.hideChapter)
        XCTAssertFalse(config.hideFooter)
        XCTAssertEqual(config.footerOrientation, 0)
    }

    func testTheFooterConfigurationRoundTrip() {
        let config = MangaFooterConfig(
            hideChapterLabel: true,
            hideChapter: true,
            hidePageNumberLabel: true,
            hidePageNumber: true,
            hideProgressRatioLabel: true,
            hideProgressRatio: true,
            footerOrientation: 2,
            hideFooter: true,
            hideChapterName: true
        )
        let json = config.jsonString()
        XCTAssertEqual(MangaFooterConfig.parse(json), config)
    }

    func testParsingAnInvalidFooterConfigurationGivesTheDefault() {
        XCTAssertEqual(MangaFooterConfig.parse("nonsense"), MangaFooterConfig())
        XCTAssertEqual(MangaFooterConfig.parse(nil), MangaFooterConfig())
    }

    // MARK: - The preferences

    func testTheColourFilterIsStoredInThePreference() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        let filter = MangaColorFilter(r: 1, g: 2, b: 3, a: 4, l: 5)
        MangaSettings.setColorFilter(filter, settings: settings)
        XCTAssertEqual(MangaSettings.colorFilter(settings), filter)
    }

    func testTheFooterConfigurationIsStoredInThePreference() {
        let store = InMemorySettingsStore()
        let settings = AppSettings(store: store)
        let config = MangaFooterConfig(footerOrientation: 1, hideFooter: true)
        MangaSettings.setFooterConfig(config, settings: settings)
        XCTAssertEqual(MangaSettings.footerConfig(settings), config)
    }

    // MARK: - The e-ink filter

    func testTheEInkFilterBinarisesAtTheThreshold() {
        let filter = MangaEpaperFilter(threshold: 128)
        XCTAssertTrue(filter.isBlack(red: 0, green: 0, blue: 0))
        XCTAssertTrue(filter.isBlack(red: 100, green: 100, blue: 100))
        XCTAssertFalse(filter.isBlack(red: 200, green: 200, blue: 200))
    }

    func testTheEInkThresholdIsClamped() {
        XCTAssertEqual(MangaEpaperFilter(threshold: -10).threshold, 0)
        XCTAssertEqual(MangaEpaperFilter(threshold: 300).threshold, 255)
    }
}
