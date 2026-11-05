//
//  RemoteBookOriginTests.swift
//  LegadoCoreTests
//
//  The tests of the origin of a book that lives on the WebDAV server —
//  upstream `Book.getRemoteUrl` and the `CustomUrl` attribute block.
//

import XCTest
@testable import LegadoCore

final class RemoteBookOriginTests: XCTestCase {

    private func makeBook(origin: String) -> Book {
        Book(
            bookUrl: "loc_book://a",
            tocUrl: "",
            origin: origin,
            originName: "a.txt",
            name: "书",
            author: "作者"
        )
    }

    func testANonRemoteBookHasNoRemoteURL() {
        let book = makeBook(origin: "loc_book://a")
        XCTAssertNil(RemoteBookOrigin.remoteURL(of: book))
        XCTAssertNil(RemoteBookOrigin.remotePath(of: book))
        XCTAssertNil(RemoteBookOrigin.serverID(of: book))
    }

    func testTheRemoteURLIsTheOriginWithoutTheTag() {
        let book = makeBook(origin: "webDav::books/我的书.txt")
        XCTAssertEqual(RemoteBookOrigin.remoteURL(of: book), "books/我的书.txt")
    }

    func testTheRemotePathDropsTheOptionBlock() {
        let book = makeBook(origin: "webDav::books/我的书.txt,{\"serverID\":5}")
        XCTAssertEqual(RemoteBookOrigin.remotePath(of: book), "books/我的书.txt")
    }

    func testTheServerIDIsRead() {
        let book = makeBook(origin: "webDav::books/我的书.txt,{\"serverID\":5}")
        XCTAssertEqual(RemoteBookOrigin.serverID(of: book), 5)
    }

    func testWithoutTheServerIDThereIsNone() {
        let book = makeBook(origin: "webDav::books/我的书.txt")
        XCTAssertNil(RemoteBookOrigin.serverID(of: book))
    }

    func testTheFileNameIsTheLastComponent() {
        let book = makeBook(origin: "webDav::books/小说/我的书.txt,{\"serverID\":5}")
        XCTAssertEqual(RemoteBookOrigin.remoteFileName(of: book), "我的书.txt")
    }

    func testThePathOfALocalBookIsNil() {
        let book = makeBook(origin: "loc_book://a")
        XCTAssertNil(RemoteBookOrigin.remotePath(of: book))
    }
}
