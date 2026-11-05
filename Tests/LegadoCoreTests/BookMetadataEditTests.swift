//
//  BookMetadataEditTests.swift
//  LegadoCoreTests
//
//  The editor of the book metadata — upstream
//  `ui/book/info/edit/BookInfoEditActivity`.
//

import XCTest
@testable import LegadoCore

final class BookMetadataEditTests: XCTestCase {

    private func book(type: Int64, origin: String = "https://example.com/book") -> Book {
        Book(
            bookUrl: "https://example.com/book",
            origin: origin,
            originName: "book",
            name: "测试书",
            author: "作者",
            type: type
        )
    }

    // MARK: - The kind

    func testATextBookIsTheTextKind() {
        XCTAssertEqual(BookMetadataEdit.kind(of: book(type: BookType.text)), .text)
    }

    func testAnAudioBookIsTheAudioKind() {
        XCTAssertEqual(BookMetadataEdit.kind(of: book(type: BookType.audio)), .audio)
    }

    func testAnImageBookIsTheImageKind() {
        XCTAssertEqual(BookMetadataEdit.kind(of: book(type: BookType.image)), .image)
    }

    // MARK: - The type

    func testTheTextKindReplacesTheType() {
        let updated = BookMetadataEdit.type(.text, book: book(type: BookType.image))
        XCTAssertTrue(BookType.contains(updated, BookType.text))
        XCTAssertFalse(BookType.contains(updated, BookType.image))
        XCTAssertFalse(BookType.contains(updated, BookType.audio))
    }

    func testTheAudioKindSetsTheAudioBit() {
        let updated = BookMetadataEdit.type(.audio, book: book(type: BookType.text))
        XCTAssertTrue(BookType.contains(updated, BookType.audio))
        XCTAssertFalse(BookType.contains(updated, BookType.text))
    }

    func testTheImageKindSetsTheImageBit() {
        let updated = BookMetadataEdit.type(.image, book: book(type: BookType.text))
        XCTAssertTrue(BookType.contains(updated, BookType.image))
        XCTAssertFalse(BookType.contains(updated, BookType.text))
    }

    func testANetworkBookHasNoLocalBit() {
        let updated = BookMetadataEdit.type(.text, book: book(type: BookType.text))
        XCTAssertFalse(BookType.contains(updated, BookType.local))
    }

    func testALocalBookKeepsTheLocalBit() {
        let local = book(type: BookType.text | BookType.local, origin: BookType.localTag)
        let updated = BookMetadataEdit.type(.image, book: local)
        XCTAssertTrue(BookType.contains(updated, BookType.local))
        XCTAssertTrue(BookType.contains(updated, BookType.image))
    }

    func testTheOtherBitsAreKept() {
        // The upstream's `removeType` only clears the four content bits.
        let source = book(type: BookType.text | BookType.notShelf)
        let updated = BookMetadataEdit.type(.audio, book: source)
        XCTAssertTrue(BookType.contains(updated, BookType.notShelf))
    }

    // MARK: - The custom cover and the introduction

    func testTheCustomCoverIsTheUrl() {
        let source = book(type: BookType.text)
        XCTAssertEqual(
            BookMetadataEdit.customCoverUrl("https://example.com/c.jpg", book: source),
            "https://example.com/c.jpg"
        )
    }

    func testTheCustomCoverIsNilWhenItIsTheCoverOfTheBook() {
        var source = book(type: BookType.text)
        source.coverUrl = "https://example.com/c.jpg"
        XCTAssertNil(
            BookMetadataEdit.customCoverUrl("https://example.com/c.jpg", book: source)
        )
    }

    func testTheCustomCoverIsNilWhenItIsEmpty() {
        XCTAssertNil(BookMetadataEdit.customCoverUrl("   ", book: book(type: BookType.text)))
    }

    func testTheCustomIntroIsTheIntro() {
        let source = book(type: BookType.text)
        XCTAssertEqual(BookMetadataEdit.customIntro("一段简介", book: source), "一段简介")
    }

    func testTheCustomIntroIsNilWhenItIsEmpty() {
        XCTAssertNil(BookMetadataEdit.customIntro("", book: book(type: BookType.text)))
    }

    // MARK: - The displayed cover

    func testTheDisplayedCoverIsTheCustomOne() {
        var source = book(type: BookType.text)
        source.coverUrl = "https://example.com/c.jpg"
        source.customCoverUrl = "https://example.com/custom.jpg"
        XCTAssertEqual(
            BookMetadataEdit.displayCover(source),
            "https://example.com/custom.jpg"
        )
    }

    func testTheDisplayedCoverFallsBackToTheCover() {
        var source = book(type: BookType.text)
        source.coverUrl = "https://example.com/c.jpg"
        XCTAssertEqual(BookMetadataEdit.displayCover(source), "https://example.com/c.jpg")
    }
}
