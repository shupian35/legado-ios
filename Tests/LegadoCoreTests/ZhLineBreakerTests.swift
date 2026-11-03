import XCTest
@testable import LegadoCore

final class ZhLineBreakerTests: XCTestCase {

    /// The clusters of a CJK text — every character is one unit wide.
    private func clusters(_ text: String, width: Double = 1) -> [TextCluster] {
        text.map { TextCluster(text: String($0), width: width) }
    }

    func testTheEmptyTextHasNoLines() {
        XCTAssertTrue(ZhLineBreaker.breakLines(clusters: [], maxWidth: 10, cnCharWidth: 1).isEmpty)
        XCTAssertTrue(ZhLineBreaker.breakLinesSimple(clusters: [], maxWidth: 10).isEmpty)
    }

    func testTheTextThatFitsIsOneLine() {
        let broken = ZhLineBreaker.breakLines(
            clusters: clusters("你好世界"),
            maxWidth: 10,
            cnCharWidth: 1
        )
        XCTAssertEqual(broken.count, 1)
        XCTAssertEqual(broken[0].startIndex, 0)
        XCTAssertEqual(broken[0].endIndex, 4)
        XCTAssertEqual(broken[0].width, 4)
    }

    func testTheLineIsBrokenAtTheWidth() {
        let broken = ZhLineBreaker.breakLines(
            clusters: clusters("一二三四五六"),
            maxWidth: 4,
            cnCharWidth: 1
        )
        XCTAssertEqual(broken.map(\.startIndex), [0, 4])
        XCTAssertEqual(broken.map(\.endIndex), [4, 6])
    }

    func testAClosingPunctuationDoesNotStartALine() {
        // The `。` would be the first character of the second line, so the
        // `好` moves down with it — the upstream `ZhLayout`.
        let broken = ZhLineBreaker.breakLines(
            clusters: clusters("他说：“你好。”然后走了。"),
            maxWidth: 6,
            cnCharWidth: 1
        )
        let text = "他说：“你好。”然后走了。"
        let characters = Array(text)
        let lines = broken.map { String(characters[$0.startIndex..<$0.endIndex]) }
        XCTAssertEqual(lines, ["他说：“你", "好。”然后走", "了。"])
        // No line starts with a closing punctuation.
        for line in lines {
            XCTAssertFalse(ZhLineBreaker.postPunctuation.contains(String(line.prefix(1))))
        }
    }

    func testAnOpeningPunctuationDoesNotEndALine() {
        // The `（` would be the last character of the first line, so the
        // character after it moves up — the upstream `ZhLayout`.
        let broken = ZhLineBreaker.breakLines(
            clusters: clusters("（你好）"),
            maxWidth: 3,
            cnCharWidth: 1
        )
        let characters = Array("（你好）")
        let lines = broken.map { String(characters[$0.startIndex..<$0.endIndex]) }
        for line in lines {
            XCTAssertFalse(ZhLineBreaker.prePunctuation.contains(String(line.suffix(1))))
        }
    }

    func testTheSimpleBreakerSplitsAtEveryCharacter() {
        let broken = ZhLineBreaker.breakLinesSimple(
            clusters: clusters("一二三四五六"),
            maxWidth: 4
        )
        XCTAssertEqual(broken.map(\.startIndex), [0, 4])
        XCTAssertEqual(broken.map(\.endIndex), [4, 6])
        XCTAssertEqual(broken.map(\.width), [4, 2])
    }

    func testTheZeroWidthCharactersStartTheirOwnCluster() {
        // The upstream `measureTextSplit` stops a cluster at a zero width
        // character (U+200B …), so such a character becomes a cluster of its
        // own with a width of zero.
        let text = "a\u{200B}b"
        let widths: [Double] = [1, 0, 1]
        let result = ZhLineBreaker.clusters(text: text) { index in
            index < widths.count ? widths[index] : 0
        }
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].text, "a")
        XCTAssertEqual(result[0].width, 1)
        XCTAssertEqual(result[1].text, "\u{200B}")
        XCTAssertEqual(result[1].width, 0)
        XCTAssertEqual(result[2].text, "b")
        XCTAssertEqual(result[2].width, 1)
    }

    func testTheCombiningMarksStayWithTheirBaseCharacter() {
        // Swift's `Character` is a grapheme cluster, so the combining mark
        // stays with its base character and the width is measured once.
        let text = "e\u{0301}b"
        let characters = Array(text)
        XCTAssertEqual(characters.count, 2)
        XCTAssertEqual(characters[0], "e\u{0301}")
        let widths: [Double] = [1, 1]
        let result = ZhLineBreaker.clusters(text: text) { index in
            index < widths.count ? widths[index] : 0
        }
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "e\u{0301}")
        XCTAssertEqual(result[0].width, 1)
        XCTAssertEqual(result[1].text, "b")
        XCTAssertEqual(result[1].width, 1)
    }

    func testTheMeasurerUsesTheChineseRules() {
        let measurer = ApproximateTextMeasurer()
        let style = ReaderTextStyle(fontSize: 10, letterSpacing: 0)
        // The CJK characters are one font size wide, the punctuation half of
        // it, so the `。` may not start a line — the `好` moves down with it.
        let lines = measurer.lines(
            of: "他说：“你好。”然后走了。",
            style: style,
            maxWidth: 60,
            useZhLayout: true
        )
        XCTAssertEqual(lines.map(\.text), ["他说：“你", "好。”然后走", "了。"])
    }

    func testTheMeasurerWithoutTheChineseRules() {
        let measurer = ApproximateTextMeasurer()
        let style = ReaderTextStyle(fontSize: 10, letterSpacing: 0)
        let lines = measurer.lines(
            of: "他说：“你好。”然后走了。",
            style: style,
            maxWidth: 60,
            useZhLayout: false
        )
        // The simple breaker splits at every character.
        XCTAssertEqual(lines.map(\.text), ["他说：“你好", "。”然后走了", "。"])
    }

    func testTheLinesKeepTheCharactersOfTheSource() {
        let measurer = ApproximateTextMeasurer()
        let style = ReaderTextStyle(fontSize: 10, letterSpacing: 0)
        let text = "第一段落。第二段落。第三段落。"
        let lines = measurer.lines(of: text, style: style, maxWidth: 60, useZhLayout: true)
        XCTAssertEqual(lines.map(\.text).joined(), text)
        for line in lines {
            XCTAssertEqual(String(Array(text)[line.startIndex..<line.endIndex]), line.text)
        }
    }
}
