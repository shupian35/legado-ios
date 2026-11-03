//
//  ReaderTextTests.swift
//  LegadoCoreTests
//
//  The font resolver and the text selection.
//

import XCTest
@testable import LegadoCore

final class FontResolverTests: XCTestCase {

    func testTheDefaultIsTheSansSerifFace() {
        let resolved = FontResolver.resolve(
            textBold: 0,
            textSize: 20,
            titleSize: 4,
            systemTypeface: 0
        )
        XCTAssertEqual(resolved.body.family, .system)
        XCTAssertEqual(resolved.title.family, .system)
    }

    func testTheSystemTypefacesMapToTheUpstreamFaces() {
        XCTAssertEqual(SystemTypeface(rawValue: 1)?.family, .serif)
        XCTAssertEqual(SystemTypeface(rawValue: 2)?.family, .monospace)
        XCTAssertNil(SystemTypeface(rawValue: 3))
    }

    func testTheTitleSizeIsAddedToTheTextSize() {
        let resolved = FontResolver.resolve(
            textBold: 0,
            textSize: 20,
            titleSize: 6,
            systemTypeface: 0
        )
        XCTAssertEqual(resolved.title.size, 26)
        XCTAssertEqual(resolved.body.size, 20)
    }

    func testTheBoldModesMatchTheUpstream() {
        // 0 = the title is bold, the body is regular
        var resolved = FontResolver.resolve(
            textBold: 0, textSize: 20, titleSize: 0, systemTypeface: 0
        )
        XCTAssertEqual(resolved.title.weight, .bold)
        XCTAssertEqual(resolved.body.weight, .regular)

        // 1 = the title is black, the body is bold
        resolved = FontResolver.resolve(
            textBold: 1, textSize: 20, titleSize: 0, systemTypeface: 0
        )
        XCTAssertEqual(resolved.title.weight, .black)
        XCTAssertEqual(resolved.body.weight, .bold)

        // 2 = the title is regular, the body is light
        resolved = FontResolver.resolve(
            textBold: 2, textSize: 20, titleSize: 0, systemTypeface: 0
        )
        XCTAssertEqual(resolved.title.weight, .regular)
        XCTAssertEqual(resolved.body.weight, .light)
    }

    func testAFontFileWinsOverTheSystemTypeface() {
        let resolved = FontResolver.resolve(
            textBold: 0,
            textSize: 20,
            titleSize: 0,
            systemTypeface: 1,
            fontPath: "/tmp/fonts/reader.ttf"
        )
        XCTAssertEqual(resolved.body.family, .file)
        XCTAssertEqual(resolved.body.filePath, "/tmp/fonts/reader.ttf")
    }

    func testAnUnknownBoldModeFallsBackToTheDefault() {
        let resolved = FontResolver.resolve(
            textBold: 9, textSize: 20, titleSize: 0, systemTypeface: 0
        )
        XCTAssertEqual(resolved.title.weight, .bold)
        XCTAssertEqual(resolved.body.weight, .regular)
    }
}

final class SelectionEngineTests: XCTestCase {

    func testTheWordRangeOfALatinWord() {
        let text = "hello world"
        let range = SelectionEngine.wordRange(around: 2, in: text)
        XCTAssertEqual(range, 0..<5)
    }

    func testTheWordRangeOfACjkCharacter() {
        let text = "你好世界"
        let range = SelectionEngine.wordRange(around: 1, in: text)
        XCTAssertEqual(range, 1..<2)
    }

    func testTheWordRangeOfWhitespaceIsTheCharacterItself() {
        let text = "a b"
        let range = SelectionEngine.wordRange(around: 1, in: text)
        XCTAssertEqual(range, 1..<2)
    }

    func testTheParagraphRangeCoversTheWholeLine() {
        let text = "第一段\n第二段"
        let range = SelectionEngine.paragraphRange(containing: 2, in: text)
        XCTAssertEqual(range, 0..<3)
    }

    func testTheParagraphSelectionOfTheSecondParagraph() {
        let text = "第一段\n第二段"
        let selection = SelectionEngine.paragraphSelection(containing: 5, in: text)
        XCTAssertEqual(selection.start, 4)
        XCTAssertEqual(selection.end, 7)
    }

    func testTheSelectionSnapsToTheWordBoundaries() {
        let text = "hello world"
        let selection = ReaderSelection(start: 1, end: 4)
        let snapped = SelectionEngine.snap(selection, in: text)
        XCTAssertEqual(snapped.start, 0)
        XCTAssertEqual(snapped.end, 5)
    }

    func testTheSelectedTextIsExtracted() {
        let text = "hello world"
        let selection = ReaderSelection(start: 0, end: 5)
        XCTAssertEqual(selection.text(in: text), "hello")
    }

    func testAnEmptySelectionHasNoText() {
        let selection = ReaderSelection(start: 3, end: 3)
        XCTAssertTrue(selection.isEmpty)
        XCTAssertEqual(selection.text(in: "hello"), "")
    }

    func testTheSelectionIsNormalisedWhenTheEndsAreSwapped() {
        let selection = ReaderSelection(start: 5, end: 0)
        XCTAssertEqual(selection.range, 0..<5)
    }

    func testTheWordRangesOfAMixedText() {
        let text = "ab 你好 cd"
        let ranges = SelectionEngine.wordRanges(in: text)
        XCTAssertEqual(ranges.count, 4)
        XCTAssertEqual(ranges[0], 0..<2)
        XCTAssertEqual(ranges[1], 3..<4)
        XCTAssertEqual(ranges[2], 4..<5)
        XCTAssertEqual(ranges[3], 6..<8)
    }
}
