//
//  WebFileBookTests.swift
//  LegadoCoreTests
//
//  The books of a source that only offers a download service — upstream
//  `BookInfoViewModel.WebFile`.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/info/BookInfoViewModel.kt:273-292
//  app/src/main/java/io/legado/app/utils/UrlUtil.kt
//

import XCTest
@testable import LegadoCore

final class WebFileBookTests: XCTestCase {

    private func makeBook(name: String = "测试书", author: String = "作者甲") -> Book {
        Book(
            bookUrl: "https://example.com/book/1",
            origin: "https://example.com",
            name: name,
            author: author,
            type: BookType.text | BookType.webFile
        )
    }

    // MARK: - The file names

    func testTheNameComesFromThePath() {
        let book = makeBook()
        let name = WebFileBook.fileName(
            url: "https://example.com/files/测试书.txt",
            book: book
        )
        XCTAssertEqual(name, "测试书.txt")
    }

    func testTheQueryIsNotPartOfTheName() {
        let book = makeBook()
        let name = WebFileBook.fileName(
            url: "https://example.com/download.php?filename=测试书.txt",
            book: book
        )
        // The upstream refuses the "php" suffix (the file name is often in the
        // query), so the name of the book is used.
        XCTAssertEqual(name, "测试书 作者：作者甲.php")
    }

    func testTheNameOfTheBookIsUsedWhenThePathHasNoName() {
        let book = makeBook()
        let name = WebFileBook.fileName(url: "https://example.com/", book: book)
        XCTAssertEqual(name, "测试书 作者：作者甲.ext")
    }

    func testTheAuthorIsLeftOutWhenItIsEmpty() {
        let book = makeBook(author: "")
        let name = WebFileBook.fileName(url: "https://example.com/", book: book)
        XCTAssertEqual(name, "测试书.ext")
    }

    func testTheTypeOfTheAddressIsUsedAsTheExtension() {
        let book = makeBook()
        let name = WebFileBook.fileName(
            url: "https://example.com/",
            book: book,
            type: "epub"
        )
        XCTAssertEqual(name, "测试书 作者：作者甲.epub")
    }

    // MARK: - The suffixes

    func testTheSuffixOfAName() {
        XCTAssertEqual(WebFileBook.suffix(of: "测试书.txt"), "txt")
        XCTAssertEqual(WebFileBook.suffix(of: "a/b/c.epub?token=1"), "epub")
        XCTAssertEqual(WebFileBook.suffix(of: "a/b/c.epub#anchor"), "epub")
    }

    func testAnIllegalSuffixBecomesExt() {
        XCTAssertEqual(WebFileBook.suffix(of: "book"), "ext")
        XCTAssertEqual(WebFileBook.suffix(of: "book.not-a-suffix"), "ext")
        XCTAssertEqual(WebFileBook.suffix(of: "book.verylongsuffix"), "ext")
    }

    // MARK: - The kinds of the files

    func testABookFileIsSupported() {
        let file = WebFile(url: "https://example.com/a.txt", name: "a.txt")
        XCTAssertTrue(file.isSupported)
        XCTAssertFalse(file.isSupportDecompress)
    }

    func testAnArchiveIsDecompressed() {
        let file = WebFile(url: "https://example.com/a.zip", name: "a.zip")
        XCTAssertFalse(file.isSupported)
        XCTAssertTrue(file.isSupportDecompress)
    }

    func testAnUnknownFileIsNeither() {
        let file = WebFile(url: "https://example.com/a.exe", name: "a.exe")
        XCTAssertFalse(file.isSupported)
        XCTAssertFalse(file.isSupportDecompress)
    }

    func testTheMobiFilesAreSupported() {
        let file = WebFile(url: "https://example.com/a.mobi", name: "a.mobi")
        XCTAssertTrue(file.isSupported)
        let other = WebFile(url: "https://example.com/a.azw3", name: "a.azw3")
        XCTAssertTrue(other.isSupported)
    }

    // MARK: - The list of the files

    func testEveryAddressBecomesAFile() {
        let book = makeBook()
        let files = WebFileBook.files(
            book: book,
            urls: [
                "https://example.com/一.txt",
                "https://example.com/二.epub"
            ]
        )
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].name, "一.txt")
        XCTAssertEqual(files[1].name, "二.epub")
    }

    func testTheFilesKeepTheirAddress() {
        let book = makeBook()
        let files = WebFileBook.files(
            book: book,
            urls: ["https://example.com/a.txt"]
        )
        XCTAssertEqual(files[0].url, "https://example.com/a.txt")
    }
}
