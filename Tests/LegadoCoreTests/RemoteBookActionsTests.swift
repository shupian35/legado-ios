//
//  RemoteBookActionsTests.swift
//  LegadoCoreTests
//
//  What a tap in the remote-book browser does — upstream
//  `RemoteBookActivity.startRead`.
//

import XCTest
@testable import LegadoCore

final class RemoteBookActionsTests: XCTestCase {

    private func remote(_ fileName: String) -> RemoteBook {
        RemoteBook(
            filename: fileName,
            path: "books/" + fileName,
            size: 1024,
            lastModify: 0,
            contentType: (fileName as NSString).pathExtension
        )
    }

    private func localBook(fileName: String) -> Book {
        Book(
            bookUrl: "file:///books/\(fileName)",
            origin: fileName,
            originName: fileName,
            name: "测试书",
            author: "作者"
        )
    }

    // MARK: - The archive test

    func testAZipIsAnArchive() {
        XCTAssertTrue(RemoteBookActions.isArchive(remote("book.zip")))
    }

    func testABookIsNoArchive() {
        XCTAssertFalse(RemoteBookActions.isArchive(remote("book.txt")))
    }

    // MARK: - The action

    func testABookOnTheShelfIsOpened() {
        let action = RemoteBookActions.startRead(
            remote: remote("book.txt"),
            bookOnShelf: localBook(fileName: "book.txt"),
            archiveExists: false
        )
        XCTAssertEqual(action, .openBook(bookUrl: "file:///books/book.txt"))
    }

    func testABookThatIsNotOnTheShelfDoesNothing() {
        let action = RemoteBookActions.startRead(
            remote: remote("book.txt"),
            bookOnShelf: nil,
            archiveExists: false
        )
        XCTAssertEqual(action, .nothing)
    }

    func testAnArchiveThatIsMissingIsDownloaded() {
        let action = RemoteBookActions.startRead(
            remote: remote("book.zip"),
            bookOnShelf: nil,
            archiveExists: false
        )
        XCTAssertEqual(action, .downloadArchive)
    }

    func testAnArchiveThatIsThereIsUnpacked() {
        let action = RemoteBookActions.startRead(
            remote: remote("book.zip"),
            bookOnShelf: nil,
            archiveExists: true
        )
        XCTAssertEqual(action, .openArchive(fileName: "book.zip"))
    }

    func testTheLocalFileNameIsTheFileName() {
        XCTAssertEqual(RemoteBookActions.localFileName(remote("book.zip")), "book.zip")
    }
}
