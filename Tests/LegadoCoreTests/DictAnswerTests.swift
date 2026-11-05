//
//  DictAnswerTests.swift
//  LegadoCoreTests
//
//  The answer of a dictionary rule — upstream `ui/dict/DictDialog.kt:65`
//  (`binding.tvDict.setHtml(it)`).
//

import XCTest
@testable import LegadoCore

final class DictAnswerTests: XCTestCase {

    func testAnHTMLDocumentIsKept() {
        let html = "<html><body><p>你好</p></body></html>"
        XCTAssertTrue(DictAnswer.isHTML(html))
        XCTAssertEqual(DictAnswer.html(html), html)
    }

    func testAPlainTextIsNotHTML() {
        XCTAssertFalse(DictAnswer.isHTML("你好"))
        XCTAssertFalse(DictAnswer.isHTML("1 < 2"))
        XCTAssertFalse(DictAnswer.isHTML(""))
    }

    func testAPlainTextIsEscaped() {
        XCTAssertEqual(DictAnswer.html("a < b & c"), "a &lt; b &amp; c")
    }

    func testTheLineBreaksOfAPlainTextBecomeBr() {
        XCTAssertEqual(DictAnswer.html("一\n二"), "一<br>\n二")
    }

    func testTheQuotesAreEscaped() {
        XCTAssertEqual(DictAnswer.escape("\"x\" 'y'"), "&quot;x&quot; &#39;y&#39;")
    }

    func testTheTagsAreDetected() {
        XCTAssertTrue(DictAnswer.isHTML("<br/>"))
        XCTAssertTrue(DictAnswer.isHTML("</div>"))
        XCTAssertTrue(DictAnswer.isHTML("<a href=\"x\">link</a>"))
    }
}
