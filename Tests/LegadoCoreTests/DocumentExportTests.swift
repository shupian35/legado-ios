//
//  DocumentExportTests.swift
//  LegadoCoreTests
//
//  The export of the stored objects into files — the port of the upstream
//  `GSON.toJson(...)` exports:
//
//  app/src/main/java/io/legado/app/ui/book/bookmark/AllBookmarkViewModel.kt
//  app/src/main/java/io/legado/app/ui/book/toc/rule/TxtTocRuleActivity.kt
//  app/src/main/java/io/legado/app/ui/dict/rule/DictRuleActivity.kt
//

import XCTest
@testable import LegadoCore

final class DocumentExportTests: XCTestCase {

    // MARK: - The bookmarks

    private func makeBookmark(
        name: String = "书名",
        author: String = "作者",
        chapter: String = "第一章",
        text: String = "原文",
        summary: String = "摘要"
    ) -> Bookmark {
        Bookmark(
            time: 1_700_000_000,
            bookName: name,
            bookAuthor: author,
            chapterIndex: 0,
            chapterPos: 0,
            chapterName: chapter,
            bookText: text,
            content: summary
        )
    }

    func testBookmarkFileName() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let name = BookmarkExport.fileName(date, markdown: false)
        XCTAssertTrue(name.hasPrefix("bookmark-"), name)
        XCTAssertTrue(name.hasSuffix(".json"), name)
        let md = BookmarkExport.fileName(date, markdown: true)
        XCTAssertTrue(md.hasSuffix(".md"), md)
        // The upstream `SimpleDateFormat("yyMMddHHmmss")` — 12 characters.
        let stamp = name
            .replacingOccurrences(of: "bookmark-", with: "")
            .replacingOccurrences(of: ".json", with: "")
        XCTAssertEqual(stamp.count, 12, stamp)
    }

    func testBookmarkMarkdown() {
        let text = BookmarkExport.markdown([makeBookmark()])
        XCTAssertTrue(text.contains("## 书名 作者"), text)
        XCTAssertTrue(text.contains("#### 第一章"), text)
        XCTAssertTrue(text.contains("原文"), text)
        XCTAssertTrue(text.contains("摘要"), text)
    }

    func testBookmarkMarkdownGroupsByBook() {
        // The upstream only writes the heading when the book or the author
        // changed.
        let text = BookmarkExport.markdown([
            makeBookmark(chapter: "第一章"),
            makeBookmark(chapter: "第二章"),
            makeBookmark(name: "另一本", chapter: "第一章")
        ])
        // The book headings are the lines that start with exactly "## ".
        let headings = text
            .components(separatedBy: "\n")
            .filter { $0.hasPrefix("## ") && !$0.hasPrefix("###") }
        XCTAssertEqual(headings.count, 2, text)
    }

    func testBookmarkJSON() throws {
        let json = BookmarkExport.json([makeBookmark()])
        let value = try JSONValue.parse(json)
        let rows = try XCTUnwrap(value.arrayValue)
        XCTAssertEqual(rows.count, 1)
        let first = try XCTUnwrap(rows.first?.objectValue)
        XCTAssertEqual(first["bookName"]?.textValue, "书名", json)
        XCTAssertEqual(first["chapterName"]?.textValue, "第一章", json)
    }

    // MARK: - The rules

    func testTxtTocRuleJSON() throws {
        let rule = TxtTocRule(id: 1, name: "规则", rule: "第一章", serialNumber: 2, enable: true)
        let json = DocumentExport.json([rule], row: { $0.row })
        let value = try JSONValue.parse(json)
        let rows = try XCTUnwrap(value.arrayValue)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.objectValue?["name"]?.textValue, "规则", json)
    }

    func testDictRuleJSON() throws {
        let rule = DictRule(name: "字典", urlRule: "https://a/%s", showRule: "body")
        let json = DocumentExport.json([rule], row: { $0.row })
        let value = try JSONValue.parse(json)
        let rows = try XCTUnwrap(value.arrayValue)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.objectValue?["name"]?.textValue, "字典", json)
    }

    func testEmptyExport() {
        XCTAssertEqual(DocumentExport.json([] as [StorageRow]), "[]")
        XCTAssertEqual(BookmarkExport.markdown([]), "")
    }
}
