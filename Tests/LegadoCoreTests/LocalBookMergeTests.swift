//
//  LocalBookMergeTests.swift
//  LegadoCoreTests
//
//  The tests of the merge of the information of an online book into the
//  imported local book — upstream `LocalBook.mergeBook`.
//

import XCTest
@testable import LegadoCore

final class LocalBookMergeTests: XCTestCase {

    private func makeBook(
        bookUrl: String = "loc_book://a",
        name: String = "本地名",
        author: String = "本地作者",
        coverUrl: String? = "local-cover",
        intro: String? = "本地简介"
    ) -> Book {
        Book(
            bookUrl: bookUrl,
            tocUrl: "",
            origin: "loc_book://a",
            originName: "a.txt",
            name: name,
            author: author,
            coverUrl: coverUrl,
            intro: intro
        )
    }

    func testTheOnlineNameWins() {
        let merged = LocalBookMerge.merge(
            local: makeBook(),
            online: makeBook(bookUrl: "https://example.com", name: "在线名", author: "")
        )
        XCTAssertEqual(merged.name, "在线名")
    }

    func testAnEmptyOnlineNameKeepsTheLocalOne() {
        let merged = LocalBookMerge.merge(
            local: makeBook(),
            online: makeBook(bookUrl: "https://example.com", name: "", author: "")
        )
        XCTAssertEqual(merged.name, "本地名")
    }

    func testTheOnlineAuthorWins() {
        let merged = LocalBookMerge.merge(
            local: makeBook(),
            online: makeBook(bookUrl: "https://example.com", name: "", author: "在线作者")
        )
        XCTAssertEqual(merged.author, "在线作者")
    }

    func testTheCoverAlwaysComesFromTheOnlineBook() {
        let merged = LocalBookMerge.merge(
            local: makeBook(),
            online: makeBook(bookUrl: "https://example.com", name: "", author: "", coverUrl: "online-cover")
        )
        XCTAssertEqual(merged.coverUrl, "online-cover")
    }

    func testAnEmptyOnlineIntroductionKeepsTheLocalOne() {
        let merged = LocalBookMerge.merge(
            local: makeBook(),
            online: makeBook(bookUrl: "https://example.com", name: "", author: "", intro: "")
        )
        XCTAssertEqual(merged.intro, "本地简介")
    }

    func testTheOnlineIntroductionWins() {
        let merged = LocalBookMerge.merge(
            local: makeBook(),
            online: makeBook(bookUrl: "https://example.com", name: "", author: "", intro: "在线简介")
        )
        XCTAssertEqual(merged.intro, "在线简介")
    }

    func testWithoutAnOnlineBookNothingChanges() {
        let local = makeBook()
        let merged = LocalBookMerge.merge(local: local, online: nil)
        XCTAssertEqual(merged, local)
    }

    func testTheBookUrlOfTheLocalBookIsKept() {
        let merged = LocalBookMerge.merge(
            local: makeBook(),
            online: makeBook(bookUrl: "https://example.com")
        )
        XCTAssertEqual(merged.bookUrl, "loc_book://a")
    }
}
