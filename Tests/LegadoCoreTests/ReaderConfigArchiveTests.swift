//
//  ReaderConfigArchiveTests.swift
//  LegadoCoreTests
//
//  The import and the export of the reader style — upstream `readConfig.zip`
//  (`app/src/main/java/io/legado/app/ui/book/read/config/BgTextConfigDialog.kt`
//  and `app/src/main/java/io/legado/app/help/config/ReadBookConfig.kt`).
//

import XCTest
@testable import LegadoCore

final class ReaderConfigArchiveTests: XCTestCase {

    private func makeConfig() -> ReaderConfig {
        var config = ReaderConfig()
        config.backgroundColor = "#ffc0edc6"
        config.backgroundColorNight = "#ff000000"
        config.backgroundColorEInk = "#ffffffff"
        config.backgroundAlpha = 80
        config.textColor = "#ff0b0b0b"
        config.textColorNight = "#ffadadad"
        config.textColorEInk = "#ff000000"
        config.pageAnim = 3
        config.textBold = 1
        config.textSize = 22.5
        config.letterSpacing = 0.25
        config.lineSpacingExtra = 15
        config.paragraphSpacing = 3.5
        config.titleMode = 1
        config.titleSize = 26
        config.titleTopSpacing = 12
        config.titleBottomSpacing = 14
        config.paragraphIndent = "　　"
        config.underline = true
        config.paddingTop = 7
        config.paddingBottom = 8
        config.paddingLeft = 17
        config.paddingRight = 18
        config.tipHeaderLeft = 1
        config.tipHeaderMiddle = 2
        config.tipHeaderRight = 3
        config.tipFooterLeft = 4
        config.tipFooterMiddle = 5
        config.tipFooterRight = 6
        config.tipColor = 7
        config.tipDividerColor = 8
        config.headerMode = 1
        config.footerMode = 2
        config.textFullJustify = true
        config.textBottomJustify = true
        config.useZhLayout = true
        config.doublePage = true
        config.styleIndex = 3
        return config
    }

    /// The JSON uses the field names of the upstream, so that an archive of
    /// the Android app can be read by the port.
    func testTheJsonUsesTheFieldNamesOfTheUpstream() throws {
        let json = ReaderConfigArchive.json(of: makeConfig(), fontName: "font.ttf")
        let value = try JSONValue.parse(json)
        let object = try XCTUnwrap(value.objectValue)
        for key in [
            "name", "bgStr", "bgStrNight", "bgStrEInk", "bgAlpha", "bgType",
            "textColor", "textColorNight", "textColorEInk", "pageAnim",
            "textFont", "textBold", "textSize", "letterSpacing",
            "lineSpacingExtra", "paragraphSpacing", "titleMode", "titleSize",
            "titleTopSpacing", "titleBottomSpacing", "paragraphIndent",
            "underline", "paddingTop", "paddingBottom", "paddingLeft",
            "paddingRight", "tipHeaderLeft", "tipHeaderMiddle", "tipHeaderRight",
            "tipFooterLeft", "tipFooterMiddle", "tipFooterRight", "tipColor",
            "tipDividerColor", "headerMode", "footerMode"
        ] {
            XCTAssertNotNil(object[key], "the field \(key) is missing")
        }
        XCTAssertEqual(object["bgStr"], .string("#ffc0edc6"))
        XCTAssertEqual(object["textFont"], .string("font.ttf"))
        XCTAssertEqual(object["textSize"], .number(22.5))
        XCTAssertEqual(object["underline"], .bool(true))
    }

    /// The configuration survives the round trip.
    func testTheConfigurationSurvivesTheRoundTrip() throws {
        let config = makeConfig()
        let json = ReaderConfigArchive.json(of: config)
        let restored = try ReaderConfigArchive.parse(json)
        XCTAssertEqual(restored.backgroundColor, config.backgroundColor)
        XCTAssertEqual(restored.backgroundColorNight, config.backgroundColorNight)
        XCTAssertEqual(restored.backgroundColorEInk, config.backgroundColorEInk)
        XCTAssertEqual(restored.backgroundAlpha, config.backgroundAlpha)
        XCTAssertEqual(restored.textColor, config.textColor)
        XCTAssertEqual(restored.textColorNight, config.textColorNight)
        XCTAssertEqual(restored.textColorEInk, config.textColorEInk)
        XCTAssertEqual(restored.pageAnim, config.pageAnim)
        XCTAssertEqual(restored.textBold, config.textBold)
        XCTAssertEqual(restored.textSize, config.textSize)
        XCTAssertEqual(restored.letterSpacing, config.letterSpacing)
        XCTAssertEqual(restored.lineSpacingExtra, config.lineSpacingExtra)
        XCTAssertEqual(restored.paragraphSpacing, config.paragraphSpacing)
        XCTAssertEqual(restored.titleMode, config.titleMode)
        XCTAssertEqual(restored.titleSize, config.titleSize)
        XCTAssertEqual(restored.titleTopSpacing, config.titleTopSpacing)
        XCTAssertEqual(restored.titleBottomSpacing, config.titleBottomSpacing)
        XCTAssertEqual(restored.paragraphIndent, config.paragraphIndent)
        XCTAssertEqual(restored.underline, config.underline)
        XCTAssertEqual(restored.paddingTop, config.paddingTop)
        XCTAssertEqual(restored.paddingBottom, config.paddingBottom)
        XCTAssertEqual(restored.paddingLeft, config.paddingLeft)
        XCTAssertEqual(restored.paddingRight, config.paddingRight)
        XCTAssertEqual(restored.tipHeaderLeft, config.tipHeaderLeft)
        XCTAssertEqual(restored.tipHeaderRight, config.tipHeaderRight)
        XCTAssertEqual(restored.tipFooterMiddle, config.tipFooterMiddle)
        XCTAssertEqual(restored.tipColor, config.tipColor)
        XCTAssertEqual(restored.tipDividerColor, config.tipDividerColor)
        XCTAssertEqual(restored.headerMode, config.headerMode)
        XCTAssertEqual(restored.footerMode, config.footerMode)
        XCTAssertEqual(restored.textFullJustify, config.textFullJustify)
        XCTAssertEqual(restored.textBottomJustify, config.textBottomJustify)
        XCTAssertEqual(restored.useZhLayout, config.useZhLayout)
        XCTAssertEqual(restored.doublePage, config.doublePage)
        XCTAssertEqual(restored.styleIndex, config.styleIndex)
    }

    /// The archive holds the configuration, the font and the background
    /// images — upstream `BgTextConfigDialog.exportConfig`.
    func testTheArchiveHoldsTheConfigurationTheFontAndTheBackgrounds() throws {
        let font = ReaderConfigArchive.File(name: "font.ttf", data: Data([1, 2, 3]))
        let background = ReaderConfigArchive.File(name: "bg.png", data: Data([4, 5, 6]))
        let data = try ReaderConfigArchive.archive(
            config: makeConfig(),
            font: font,
            backgrounds: [background]
        )
        let payload = try ReaderConfigArchive.read(data)
        XCTAssertEqual(payload.config.textSize, 22.5)
        XCTAssertEqual(payload.fontName, "font.ttf")
        XCTAssertEqual(payload.font?.name, "font.ttf")
        XCTAssertEqual(payload.font?.data, Data([1, 2, 3]))
        XCTAssertEqual(payload.backgrounds.map(\.name), ["bg.png"])
        XCTAssertEqual(payload.backgrounds.first?.data, Data([4, 5, 6]))
    }

    /// An archive without `readConfig.json` cannot be imported.
    func testAnArchiveWithoutTheConfigurationIsRejected() throws {
        let data = try ZipWriter.archive([
            ZipWriteEntry(name: "other.txt", data: Data("hello".utf8))
        ])
        XCTAssertThrowsError(try ReaderConfigArchive.read(data)) { error in
            XCTAssertEqual(error as? ReaderConfigArchiveError, .missingConfigFile)
        }
    }

    /// A broken `readConfig.json` cannot be imported.
    func testABrokenConfigurationIsRejected() {
        XCTAssertThrowsError(try ReaderConfigArchive.parse("{not json")) { error in
            XCTAssertEqual(error as? ReaderConfigArchiveError, .brokenConfigFile)
        }
    }

    /// The name of the font is read back from the JSON.
    func testTheFontNameIsReadFromTheJson() {
        let json = ReaderConfigArchive.json(of: ReaderConfig(), fontName: "my-font.ttf")
        XCTAssertEqual(ReaderConfigArchive.fontName(in: json), "my-font.ttf")
        let empty = ReaderConfigArchive.json(of: ReaderConfig())
        XCTAssertNil(ReaderConfigArchive.fontName(in: empty))
    }

    /// The JSON of the upstream is understood — the port reads the archive of
    /// the Android app.
    func testTheJsonOfTheUpstreamIsUnderstood() throws {
        let upstream = """
        {
          "name": "微信读书",
          "bgStr": "#ffc0edc6",
          "bgStrNight": "#ff000000",
          "bgStrEInk": "#ffffffff",
          "bgAlpha": 100,
          "bgType": 0,
          "textColor": "#ff0b0b0b",
          "textColorNight": "#ffadadad",
          "textColorEInk": "#ff000000",
          "pageAnim": 4,
          "textFont": "",
          "textBold": 0,
          "textSize": 20,
          "letterSpacing": 0.1,
          "lineSpacingExtra": 12,
          "paragraphSpacing": 2,
          "titleMode": 0,
          "titleSize": 20,
          "titleTopSpacing": 10,
          "titleBottomSpacing": 10,
          "paragraphIndent": "　　",
          "underline": false,
          "paddingTop": 6,
          "paddingBottom": 6,
          "paddingLeft": 16,
          "paddingRight": 16,
          "tipHeaderLeft": 1,
          "tipHeaderMiddle": 0,
          "tipHeaderRight": 2,
          "tipFooterLeft": 3,
          "tipFooterMiddle": 0,
          "tipFooterRight": 4,
          "tipColor": 0,
          "tipDividerColor": -1,
          "headerMode": 0,
          "footerMode": 0
        }
        """
        let config = try ReaderConfigArchive.parse(upstream)
        XCTAssertEqual(config.backgroundColor, "#ffc0edc6")
        XCTAssertEqual(config.textSize, 20)
        XCTAssertEqual(config.pageAnim, 4)
        XCTAssertEqual(config.tipHeaderRight, 2)
        XCTAssertEqual(config.tipDividerColor, -1)
        XCTAssertEqual(config.paragraphIndent, "　　")
    }
}
