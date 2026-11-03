//
//  LocalBookImporterTests.swift
//  LegadoCoreTests
//
//  The local book import — upstream `model/localBook/LocalBook.kt:231-262`.
//

import XCTest
@testable import LegadoCore

final class LocalBookImporterTests: XCTestCase {

    private var workDirectory: URL!
    private var booksDirectory: URL!
    private var store: LegadoStore!
    private var importer: LocalBookImporter!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("legado-importer-\(UUID().uuidString)")
        booksDirectory = workDirectory.appendingPathComponent("books", isDirectory: true)
        try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        importer = LocalBookImporter(store: store, booksDirectory: booksDirectory)
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    private func makeTxt(_ name: String = "示例书 作者.txt") throws -> URL {
        let content = """
        第一章 起点
        这是第一章的内容。
        第二章 发展
        这是第二章的内容。
        """
        let url = workDirectory.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeRule() -> TxtTocRule {
        var rule = TxtTocRule(row: [:])
        rule.id = 1
        rule.name = "章节"
        rule.rule = "第.章\\s.*"
        rule.serialNumber = 1
        rule.enable = true
        return rule
    }

    // MARK: - Tests

    func testImportsATxtFile() throws {
        try store.insert(makeRule())
        let file = try makeTxt()

        let book = try importer.importBook(from: file)

        XCTAssertTrue(book.isLocal)
        XCTAssertEqual(book.originName, "示例书 作者.txt")
        XCTAssertEqual(book.name, "示例书")
        XCTAssertEqual(book.author, "作者")
        XCTAssertEqual(book.totalChapterNum, 2)

        let stored = try store.allBooks()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.bookUrl, book.bookUrl)

        let chapters = try store.chapters(bookUrl: book.bookUrl)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters.map(\.title), ["第一章 起点", "第二章 发展"])
    }

    func testCopiesTheFileIntoTheAppStorage() throws {
        try store.insert(makeRule())
        let file = try makeTxt()

        let book = try importer.importBook(from: file)

        let copy = importer.fileURL(for: book)
        XCTAssertNotNil(copy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copy!.path))
        XCTAssertTrue(copy!.path.hasPrefix(booksDirectory.path))
        // The original is left alone.
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testReimportingReplacesTheChapters() throws {
        try store.insert(makeRule())
        let file = try makeTxt()

        let first = try importer.importBook(from: file)
        let second = try importer.importBook(from: file)

        XCTAssertEqual(first.bookUrl, second.bookUrl)
        XCTAssertEqual(try store.allBooks().count, 1)
        XCTAssertEqual(try store.chapters(bookUrl: second.bookUrl).count, 2)
    }

    func testDeletingRemovesTheBookAndTheFile() throws {
        try store.insert(makeRule())
        let file = try makeTxt()
        let book = try importer.importBook(from: file)

        try importer.removeBook(book)

        XCTAssertTrue(try store.allBooks().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: booksDirectory.appendingPathComponent(book.originName).path))
    }

    func testAnUnsupportedFormatIsRejected() throws {
        let file = workDirectory.appendingPathComponent("picture.png")
        try Data("x".utf8).write(to: file)

        XCTAssertThrowsError(try importer.importBook(from: file)) { error in
            guard case LocalBookImporter.ImportError.unsupportedFormat = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testAnEmptyFileIsRejected() throws {
        let file = workDirectory.appendingPathComponent("empty.txt")
        try Data().write(to: file)

        XCTAssertThrowsError(try importer.importBook(from: file)) { error in
            guard case LocalBookImporter.ImportError.emptyFile = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testTheLocalBooksAreListed() throws {
        try store.insert(makeRule())
        _ = try importer.importBook(from: try makeTxt())

        let books = try importer.localBooks()
        XCTAssertEqual(books.count, 1)
        XCTAssertTrue(books[0].isLocal)
    }
}
