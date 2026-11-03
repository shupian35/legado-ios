//
//  BookProgressSyncTests.swift
//  LegadoCoreTests
//
//  Upstream references:
//  app/src/main/java/io/legado/app/ui/book/read/ReadBookViewModel.kt:240-262
//  (syncBookProgress), app/src/main/java/io/legado/app/model/ReadBook.kt:237-247
//  (uploadProgress) and
//  app/src/main/java/io/legado/app/data/entities/Server.kt:51-58 (the WebDAV
//  credentials of a server).
//

import XCTest
@testable import LegadoCore

// MARK: - BookProgressSync

final class BookProgressSyncTests: XCTestCase {

    private func progress(chapter: Int, pos: Int) -> BookProgress {
        BookProgress(
            name: "Novel",
            author: "Author",
            durChapterIndex: chapter,
            durChapterPos: pos,
            durChapterTime: 1_700_000_000,
            durChapterTitle: "Chapter \(chapter)"
        )
    }

    func testTheSameProgressIsReportedAsSame() {
        let outcome = BookProgressSync.resolve(
            remote: progress(chapter: 12, pos: 34),
            local: progress(chapter: 12, pos: 34),
            totalChapters: 100
        )
        XCTAssertEqual(outcome, .same)
    }

    func testANewerRemoteProgressIsApplied() {
        let remote = progress(chapter: 20, pos: 5)
        let outcome = BookProgressSync.resolve(
            remote: remote,
            local: progress(chapter: 12, pos: 34),
            totalChapters: 100
        )
        XCTAssertEqual(outcome, .remoteNewer(remote))
    }

    func testARemoteProgressInTheSameChapterButBehindIsOlder() {
        let remote = progress(chapter: 12, pos: 10)
        let outcome = BookProgressSync.resolve(
            remote: remote,
            local: progress(chapter: 12, pos: 34),
            totalChapters: 100
        )
        XCTAssertEqual(outcome, .remoteOlder(remote))
    }

    func testAnOlderChapterIsOlder() {
        let remote = progress(chapter: 3, pos: 100)
        let outcome = BookProgressSync.resolve(
            remote: remote,
            local: progress(chapter: 12, pos: 34),
            totalChapters: 100
        )
        XCTAssertEqual(outcome, .remoteOlder(remote))
    }

    func testAProgressBeyondTheBookIsIgnored() {
        let remote = progress(chapter: 500, pos: 0)
        let outcome = BookProgressSync.resolve(
            remote: remote,
            local: progress(chapter: 12, pos: 34),
            totalChapters: 100
        )
        XCTAssertEqual(outcome, .beyondTheBook(remote))
    }

    func testTheProgressOfABookIsBuiltFromItsState() {
        let book = Book(
            bookUrl: "u1",
            name: "Novel",
            author: "Author",
            durChapterIndex: 7,
            durChapterPos: 99
        )
        let progress = BookProgress(book: book)
        XCTAssertEqual(progress.durChapterIndex, 7)
        XCTAssertEqual(progress.durChapterPos, 99)
        XCTAssertEqual(progress.name, "Novel")
    }

    func testTheProgressFileNameIsNormalized() {
        let progress = BookProgress(
            name: "Novel: Part 1",
            author: "Author/2",
            durChapterIndex: 0,
            durChapterPos: 0,
            durChapterTime: 0,
            durChapterTitle: nil
        )
        XCTAssertEqual(progress.fileName, "Novel Part 1_Author2.json")
    }
}

// MARK: - WebDavCredentials

final class WebDavCredentialsTests: XCTestCase {

    func testTheJsonRoundTrip() throws {
        let credentials = WebDavCredentials(
            url: "https://dav.example.com",
            username: "me",
            password: "secret"
        )
        let parsed = try XCTUnwrap(WebDavCredentials.parse(credentials.json))
        XCTAssertEqual(parsed, credentials)
    }

    func testAnEmptyJsonIsNotParsed() {
        XCTAssertNil(WebDavCredentials.parse(nil))
        XCTAssertNil(WebDavCredentials.parse(""))
    }

    func testABrokenJsonIsNotParsed() {
        XCTAssertNil(WebDavCredentials.parse("{"))
    }

    func testTheServerIsConfiguredWhenTheUrlIsNotEmpty() {
        XCTAssertTrue(WebDavCredentials(url: "https://dav", username: "", password: "").isConfigured)
        XCTAssertFalse(WebDavCredentials(url: "  ", username: "", password: "").isConfigured)
    }

    func testTheServiceConfigurationUsesTheProgressDirectory() {
        let configuration = WebDavCredentials(
            url: "https://dav",
            username: "me",
            password: "secret"
        ).serviceConfiguration()
        XCTAssertEqual(configuration.url, "https://dav")
        XCTAssertEqual(configuration.username, "me")
        XCTAssertEqual(configuration.password, "secret")
        XCTAssertEqual(configuration.bookProgressDirectory, "bookProgress/")
    }
}

// MARK: - The chapter update (the content editor)

final class ChapterUpdateTests: XCTestCase {

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        return store
    }

    func testTheTitleOfAChapterCanBeChanged() throws {
        let store = try makeStore()
        let chapter = BookChapter(url: "c1", title: "Chapter 1", bookUrl: "u1")
        try store.insert([chapter])
        var changed = chapter
        changed.title = "第一章"
        try store.update(changed)
        let chapters = try store.chapters(bookUrl: "u1")
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters.first?.title, "第一章")
        XCTAssertEqual(chapters.first?.url, "c1")
    }
}
