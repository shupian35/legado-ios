import XCTest
@testable import LegadoCore

/// The reader background — upstream `ReadBookConfig.Config` +
/// `ReadBookConfig.curBgDrawable`.
final class ReaderBackgroundTests: XCTestCase {

    // MARK: - The display mode

    func testTheDisplayModeFollowsTheUpstreamPref() {
        // "0" = system, "1" = light, "2" = dark, "3" = E-Ink
        XCTAssertEqual(ReaderDisplayMode.resolve(themeMode: "3", systemNightMode: false), .eInk)
        XCTAssertEqual(ReaderDisplayMode.resolve(themeMode: "1", systemNightMode: true), .day)
        XCTAssertEqual(ReaderDisplayMode.resolve(themeMode: "2", systemNightMode: false), .night)
        XCTAssertEqual(ReaderDisplayMode.resolve(themeMode: "0", systemNightMode: true), .night)
        XCTAssertEqual(ReaderDisplayMode.resolve(themeMode: "0", systemNightMode: false), .day)
    }

    // MARK: - The preset

    func testThePresetResolvesTheModeDependentValues() {
        let preset = ReaderBackgroundPreset(
            bgStr: "#FFFFFF",
            bgStrNight: "#000000",
            bgStrEInk: "#EEEEEE",
            bgType: 0,
            bgTypeNight: 1,
            bgTypeEInk: 2,
            textColor: "#111111",
            textColorNight: "#AAAAAA",
            textColorEInk: "#222222"
        )
        XCTAssertEqual(preset.backgroundString(for: .day), "#FFFFFF")
        XCTAssertEqual(preset.backgroundString(for: .night), "#000000")
        XCTAssertEqual(preset.backgroundString(for: .eInk), "#EEEEEE")
        XCTAssertEqual(preset.backgroundType(for: .day), .color)
        XCTAssertEqual(preset.backgroundType(for: .night), .asset)
        XCTAssertEqual(preset.backgroundType(for: .eInk), .file)
        XCTAssertEqual(preset.textColorString(for: .day), "#111111")
        XCTAssertEqual(preset.textColorString(for: .night), "#AAAAAA")
        XCTAssertEqual(preset.textColorString(for: .eInk), "#222222")
    }

    func testTheWeixinPresetIsTheUpstreamDefault() {
        XCTAssertEqual(ReaderBackgroundPreset.weixinRead.name, "微信读书")
        XCTAssertEqual(ReaderBackgroundPreset.weixinRead.bgAlpha, 100)
    }

    func testThePresetDecodesTheUpstreamJson() throws {
        // the field names of `assets/defaultData/readConfig.json`
        let json = """
        {"name":"测试","bgStr":"#123456","bgStrNight":"#654321","bgStrEInk":"#FFFFFF",
         "bgAlpha":80,"bgType":0,"bgTypeNight":1,"bgTypeEInk":2,
         "textColor":"#000000","textColorNight":"#FFFFFF","textColorEInk":"#000000"}
        """
        let preset = try JSONDecoder().decode(ReaderBackgroundPreset.self, from: Data(json.utf8))
        XCTAssertEqual(preset.name, "测试")
        XCTAssertEqual(preset.bgStr, "#123456")
        XCTAssertEqual(preset.bgAlpha, 80)
        XCTAssertEqual(preset.backgroundType(for: .night), .asset)
    }

    // MARK: - The background helpers

    func testTheBackgroundFilePathIsBelowTheBackgroundDirectory() {
        let root = URL(fileURLWithPath: "/tmp/legado")
        let path = ReaderBackground.filePath(for: "cover.jpg", root: root)
        XCTAssertEqual(path.path, "/tmp/legado/bg/cover.jpg")
    }

    func testAnAbsoluteBackgroundPathIsKept() {
        let root = URL(fileURLWithPath: "/tmp/legado")
        let path = ReaderBackground.filePath(for: "/other/cover.jpg", root: root)
        XCTAssertEqual(path.path, "/other/cover.jpg")
    }

    func testTheAlphaIsThePercent() {
        XCTAssertEqual(ReaderBackground.alpha(for: ReaderBackgroundPreset(bgAlpha: 100)), 1.0, accuracy: 0.000_001)
        XCTAssertEqual(ReaderBackground.alpha(for: ReaderBackgroundPreset(bgAlpha: 50)), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(ReaderBackground.alpha(for: ReaderBackgroundPreset(bgAlpha: 0)), 0.0, accuracy: 0.000_001)
    }

    func testTheMeanColorSamplesTheBottomOfTheImage() {
        // a 2×2 image: the top row is red, the bottom row is blue
        var pixels: [UInt8] = []
        pixels += [255, 0, 0, 255, 255, 0, 0, 255]
        pixels += [0, 0, 255, 255, 0, 0, 255, 255]
        let mean = ReaderBackground.meanColor(of: pixels, width: 2, height: 2)
        XCTAssertNotNil(mean)
        if let mean {
            // upstream `BitmapUtils.getMeanColor` adds 3 to every channel
            XCTAssertEqual(mean.b, 258)
            XCTAssertGreaterThan(mean.b, mean.r)
        }
    }

    func testTheMeanColorRejectsATooSmallBuffer() {
        XCTAssertNil(ReaderBackground.meanColor(of: [0, 0, 0], width: 2, height: 2))
    }
}
