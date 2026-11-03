//
//  FileAssociationTests.swift
//  LegadoCoreTests
//
//  The port of
//  `app/src/main/java/io/legado/app/ui/association/FileAssociationViewModel.kt`.
//

import XCTest
@testable import LegadoCore

final class FileAssociationTests: XCTestCase {

    func testABookFileIsABook() {
        XCTAssertEqual(FileAssociation.kind(fileName: "novel.txt", content: nil), .book)
        XCTAssertEqual(FileAssociation.kind(fileName: "novel.epub", content: nil), .book)
        XCTAssertEqual(FileAssociation.kind(fileName: "novel.umd", content: nil), .book)
        XCTAssertEqual(FileAssociation.kind(fileName: "novel.pdf", content: nil), .book)
        XCTAssertEqual(FileAssociation.kind(fileName: "novel.mobi", content: nil), .book)
    }

    func testTheExtensionIsCaseInsensitive() {
        XCTAssertEqual(FileAssociation.kind(fileName: "NOVEL.EPUB", content: nil), .book)
    }

    func testAnArchiveIsAnArchive() {
        XCTAssertEqual(FileAssociation.kind(fileName: "books.zip", content: nil), .archive)
        XCTAssertEqual(FileAssociation.kind(fileName: "books.rar", content: nil), .archive)
        XCTAssertEqual(FileAssociation.kind(fileName: "books.7z", content: nil), .archive)
    }

    func testAnUnknownFileIsUnsupported() {
        XCTAssertEqual(FileAssociation.kind(fileName: "photo.png", content: nil), .unsupported)
        XCTAssertEqual(FileAssociation.kind(fileName: "noextension", content: nil), .unsupported)
    }

    func testTheJSONDetectionUsesTheContent() {
        let json = Data("[{\"bookSourceUrl\":\"https://example.com\"}]".utf8)
        XCTAssertEqual(FileAssociation.kind(fileName: "whatever.txt", content: json), .json)
    }

    func testTheJSONDetectionIgnoresTheLeadingWhitespace() {
        let json = Data("  \n [{}]".utf8)
        XCTAssertTrue(FileAssociation.looksLikeJSON(json))
    }

    func testAPlainTextIsNotJSON() {
        XCTAssertFalse(FileAssociation.looksLikeJSON(Data("hello".utf8)))
    }

    func testTheFileExtensionIsTakenFromTheName() {
        XCTAssertEqual(FileAssociation.fileExtension(of: "/tmp/dir/book.epub"), "epub")
        XCTAssertEqual(FileAssociation.fileExtension(of: "book"), "")
        XCTAssertEqual(FileAssociation.fileExtension(of: "a.b.txt"), "txt")
    }

    func testTheImportKindOfABookSourceJSON() {
        let json = "[{\"bookSourceUrl\":\"https://example.com\",\"bookSourceName\":\"测试源\"}]"
        XCTAssertEqual(FileAssociation.importKind(ofJSON: json), .bookSource)
    }

    func testTheImportKindOfARSSSourceJSON() {
        let json = "[{\"sourceUrl\":\"https://example.com/rss\",\"sourceName\":\"订阅\"}]"
        XCTAssertEqual(FileAssociation.importKind(ofJSON: json), .rssSource)
    }

    func testAnUnknownJSONHasNoImportKind() {
        XCTAssertNil(FileAssociation.importKind(ofJSON: "[{\"foo\":1}]"))
    }
}
