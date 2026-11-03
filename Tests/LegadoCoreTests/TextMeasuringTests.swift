//
//  TextMeasuringTests.swift
//  LegadoCoreTests
//
//  Tests for the text measurement: the character widths, the letter spacing
//  (the upstream stores it in ems) and the clusters.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/TextMeasure.kt
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/TextChapterLayout.kt
//

import XCTest
@testable import LegadoCore

final class TextMeasuringTests: XCTestCase {

    /// The CJK character is as wide as the font.
    func testTheCjkCharacterIsAsWideAsTheFont() {
        let measurer = ApproximateTextMeasurer()
        let style = ReaderTextStyle(fontSize: 20, letterSpacing: 0)
        XCTAssertEqual(measurer.width(of: "我", style: style), 20, accuracy: 0.0001)
    }

    /// The latin character is half as wide.
    func testTheLatinCharacterIsHalfAsWide() {
        let measurer = ApproximateTextMeasurer()
        let style = ReaderTextStyle(fontSize: 20, letterSpacing: 0)
        XCTAssertEqual(measurer.width(of: "a", style: style), 10, accuracy: 0.0001)
    }

    /// The space is narrower.
    func testTheSpaceIsNarrow() {
        let measurer = ApproximateTextMeasurer()
        let style = ReaderTextStyle(fontSize: 20, letterSpacing: 0)
        XCTAssertEqual(measurer.width(of: " ", style: style), 6, accuracy: 0.0001)
    }

    /// The letter spacing is in ems — `paint.letterSpacing * paint.textSize`.
    func testTheLetterSpacingIsInEms() {
        let measurer = ApproximateTextMeasurer()
        let style = ReaderTextStyle(fontSize: 20, letterSpacing: 0.1)
        XCTAssertEqual(measurer.width(of: "我", style: style), 22, accuracy: 0.0001)
        XCTAssertEqual(measurer.width(of: "我我", style: style), 44, accuracy: 0.0001)
    }

    /// The zero width characters have no width of their own.
    func testTheZeroWidthCharactersAreFree() {
        let measurer = ApproximateTextMeasurer()
        let style = ReaderTextStyle(fontSize: 20, letterSpacing: 0)
        XCTAssertEqual(measurer.width(of: "\u{200B}", style: style), 0, accuracy: 0.0001)
    }

    /// The zero width character forms a cluster of its own — the upstream
    /// `measureTextSplit` stops at it.
    func testTheZeroWidthCharacterIsItsOwnCluster() {
        let measurer = ApproximateTextMeasurer()
        let style = ReaderTextStyle(fontSize: 20, letterSpacing: 0)
        let clusters = measurer.clusterWidths(of: "a\u{200B}b", style: style)
        XCTAssertEqual(clusters.count, 3)
        XCTAssertEqual(clusters[0].text, "a")
        XCTAssertEqual(clusters[1].text, "\u{200B}")
        XCTAssertEqual(clusters[2].text, "b")
        XCTAssertEqual(clusters[2].width, 10, accuracy: 0.0001)
    }

    /// The line breaking keeps every character.
    func testTheLinesKeepTheOriginalText() {
        let measurer = ApproximateTextMeasurer()
        let style = ReaderTextStyle(fontSize: 20, letterSpacing: 0)
        let lines = measurer.lines(of: "一二三四五", style: style, maxWidth: 45)
        XCTAssertEqual(lines.map(\.text).joined(), "一二三四五")
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0].startIndex, 0)
        XCTAssertEqual(lines[0].endIndex, 2)
    }

    /// The vertical metrics follow the font size.
    func testTheVerticalMetrics() {
        let measurer = ApproximateTextMeasurer()
        let style = ReaderTextStyle(fontSize: 20, letterSpacing: 0)
        let metrics = measurer.metrics(for: style)
        XCTAssertEqual(metrics.ascent, 16, accuracy: 0.0001)
        XCTAssertEqual(metrics.descent, 4, accuracy: 0.0001)
        XCTAssertEqual(metrics.lineHeight, 24, accuracy: 0.0001)
    }
}
