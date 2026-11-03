//
//  TocOperationsTests.swift
//  LegadoCoreTests
//
//  The table-of-contents operations — the port of
//  `ui/book/toc/TocViewModel.kt`.
//

import XCTest
@testable import LegadoCore

final class TocOperationsTests: XCTestCase {

    private func makeBook(name: String = "测试书", author: String = "作者") -> Book {
        Book(bookUrl: "https://example.com/book/1", name: name, author: author)
    }

    private func makeChapters() -> [BookChapter] {
        [
            BookChapter(url: "c1", title: "第一章", isVolume: false, baseUrl: "", bookUrl: "b", index: 0),
            BookChapter(url: "c2", title: "第二章", isVolume: false, baseUrl: "", bookUrl: "b", index: 1),
            BookChapter(url: "c3", title: "第三章", isVolume: false, baseUrl: "", bookUrl: "b", index: 2)
        ]
    }

    func testTheReverseFlipsTheOrderAndReindexes() {
        let reversed = TocOperations.reverse(chapters: makeChapters())
        XCTAssertEqual(reversed.map(\.title), ["第三章", "第二章", "第一章"])
        XCTAssertEqual(reversed.map(\.index), [0, 1, 2])
    }

    func testTheReverseOfAnEmptyListIsEmpty() {
        XCTAssertTrue(TocOperations.reverse(chapters: []).isEmpty)
    }

    func testTheReverseOfASingleChapterKeepsIt() {
        let reversed = TocOperations.reverse(chapters: [makeChapters()[1]])
        XCTAssertEqual(reversed.count, 1)
        XCTAssertEqual(reversed[0].title, "第二章")
        XCTAssertEqual(reversed[0].index, 0)
    }

    func testTheBookmarkFileNameFollowsTheUpstream() {
        XCTAssertEqual(TocOperations.bookmarkFileName(book: makeBook()), "bookmark-测试书 作者.json")
        XCTAssertEqual(TocOperations.bookmarkFileName(book: makeBook(), fileExtension: "md"), "bookmark-测试书 作者.md")
    }

    func testTheBookmarkJSONOnlyHoldsTheBookmarksOfTheBook() {
        let book = makeBook()
        let bookmarks = [
            Bookmark(time: 1, bookName: "测试书", bookAuthor: "作者", chapterIndex: 3, chapterPos: 120, chapterName: "第四章"),
            Bookmark(time: 2, bookName: "别的书", bookAuthor: "别人", chapterIndex: 1, chapterPos: 0, chapterName: "第一章")
        ]
        let json = TocOperations.bookmarkJSON(book: book, bookmarks: bookmarks)
        XCTAssertTrue(json.contains("第四章"))
        XCTAssertFalse(json.contains("别的书"))
    }

    func testTheBookmarkJSONIsAnArray() {
        let json = TocOperations.bookmarkJSON(book: makeBook(), bookmarks: [])
        XCTAssertTrue(json.hasPrefix("["))
    }

    func testTheBookmarkMarkdownListsTheHeadings() {
        let book = makeBook()
        let bookmarks = [
            Bookmark(time: 1, bookName: "测试书", bookAuthor: "作者", chapterIndex: 1, chapterPos: 10, chapterName: "第一章"),
            Bookmark(time: 2, bookName: "测试书", bookAuthor: "作者", chapterIndex: 0, chapterPos: 0, chapterName: "序章")
        ]
        let markdown = TocOperations.bookmarkMarkdown(book: book, bookmarks: bookmarks)
        XCTAssertTrue(markdown.contains("## 序章"))
        XCTAssertTrue(markdown.contains("## 第一章"))
        // The upstream sorts the bookmarks by the chapter index.
        let firstIndex = markdown.range(of: "## 序章")!.lowerBound
        let secondIndex = markdown.range(of: "## 第一章")!.lowerBound
        XCTAssertLessThan(firstIndex, secondIndex)
    }

    func testTheFilterMatchesTheChapterName() {
        let chapters = makeChapters()
        XCTAssertEqual(TocOperations.filter(chapters: chapters, keyword: "第二").map(\.title), ["第二章"])
        XCTAssertEqual(TocOperations.filter(chapters: chapters, keyword: "章").count, 3)
    }

    func testAnEmptyKeywordKeepsEveryChapter() {
        let chapters = makeChapters()
        XCTAssertEqual(TocOperations.filter(chapters: chapters, keyword: "   ").count, 3)
    }
}
