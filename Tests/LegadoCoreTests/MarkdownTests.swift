//
//  MarkdownTests.swift
//  LegadoCoreTests
//
//  The Markdown parser — the port of the upstream's Markwon rendering.
//

import XCTest
@testable import LegadoCore

final class MarkdownTests: XCTestCase {

    func testTheHeadings() {
        let blocks = Markdown.parse("# One\n## Two\n###### Six")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0], .heading(level: 1, text: "One"))
        XCTAssertEqual(blocks[1], .heading(level: 2, text: "Two"))
        XCTAssertEqual(blocks[2], .heading(level: 6, text: "Six"))
    }

    func testTheParagraphs() {
        let blocks = Markdown.parse("The first.\nThe second.\n\nThe third.")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0], .paragraph("The first.\nThe second."))
        XCTAssertEqual(blocks[1], .paragraph("The third."))
    }

    func testTheBullets() {
        let blocks = Markdown.parse("- one\n* two\n+ three")
        XCTAssertEqual(blocks.count, 3)
        XCTAssertEqual(blocks[0], .bullet("one"))
        XCTAssertEqual(blocks[1], .bullet("two"))
        XCTAssertEqual(blocks[2], .bullet("three"))
    }

    func testTheNumberedItems() {
        let blocks = Markdown.parse("1. one\n2. two")
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0], .numbered(1, "one"))
        XCTAssertEqual(blocks[1], .numbered(2, "two"))
    }

    func testTheQuotes() {
        let blocks = Markdown.parse("> the quote")
        XCTAssertEqual(blocks, [.quote("the quote")])
    }

    func testTheDividers() {
        let blocks = Markdown.parse("---")
        XCTAssertEqual(blocks, [.divider])
    }

    func testTheCodeBlocks() {
        let blocks = Markdown.parse("```\nlet a = 1\n```")
        XCTAssertEqual(blocks, [.code("let a = 1")])
    }

    func testTheLinks() {
        let blocks = Markdown.parse("[the text](https://example.com)")
        XCTAssertEqual(blocks, [.link(text: "the text", url: "https://example.com")])
    }

    func testThePlainText() {
        let text = Markdown.plainText("# Title\n\nThe text.")
        XCTAssertEqual(text, "Title\nThe text.")
    }

    func testTheUpstreamUpdateLogIsParsed() {
        let blocks = Markdown.parse(AboutDocumentText.updateLog)
        XCTAssertFalse(blocks.isEmpty)
        XCTAssertEqual(blocks.first, .heading(level: 1, text: "更新日志"))
    }

    func testTheUpstreamDisclaimerIsParsed() {
        let blocks = Markdown.parse(AboutDocumentText.disclaimer)
        XCTAssertFalse(blocks.isEmpty)
        XCTAssertEqual(blocks.first, .heading(level: 1, text: "免责声明（Disclaimer）"))
    }
}

/// The upstream documents — the copies of the upstream assets.
enum AboutDocumentText {
    static let updateLog = """
    # 更新日志

    * 关注公众号 **[开源阅读]** 菜单•软件下载 提前享受新版本。

    **2025/03/26**
    * 目前阅读被恶意注册软著，并建立了多个公众号

    ----

    * [2023年日志](https://github.com/gedoor/legado/blob/record2023/app/src/main/assets/updateLog.md)
    """

    static let disclaimer = """
    # 免责声明（Disclaimer）

    * 阅读是一款解析指定规则并获取内容的工具。
    """
}
