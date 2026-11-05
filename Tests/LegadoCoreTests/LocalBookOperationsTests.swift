//
//  LocalBookOperationsTests.swift
//  LegadoCoreTests
//
//  The local book operations — upstream `model/localBook/LocalBook.kt:377-392`
//  (`deleteBook`), `ui/book/info/BookInfoViewModel.kt:462` (`delBook`) and
//  `help/config/AppConfig.kt:209` (`defaultBookTreeUri`).
//

import XCTest
@testable import LegadoCore

final class LocalBookOperationsTests: XCTestCase {

    private var workDirectory: URL!
    private var store: LegadoStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("legado-local-ops-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
        store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    // MARK: - Fixtures

    private func makeLocalBook() throws -> (Book, URL) {
        var book = Book(
            bookUrl: workDirectory.appendingPathComponent("示例书.txt").path,
            name: "示例书",
            author: "作者"
        )
        book.type = BookType.local
        book.originName = "示例书.txt"
        let file = workDirectory.appendingPathComponent("示例书.txt")
        try "第一章".write(to: file, atomically: true, encoding: .utf8)
        return (book, file)
    }

    private func makeEnvironment(
        localFileResolver: @escaping (Book) -> URL?,
        cacheStorage: BookCacheStorage? = nil
    ) -> AppEnvironment {
        AppEnvironment(
            store: store,
            settings: AppSettings(store: InMemorySettingsStore()),
            cacheStorage: cacheStorage,
            localFileResolver: localFileResolver
        )
    }

    // MARK: - The deletion

    func testDeletingABookRemovesItsRowAndItsChapters() throws {
        let (book, _) = try makeLocalBook()
        let chapter = BookChapter(url: "c1", title: "第一章", bookUrl: book.bookUrl, index: 0)
        try store.insert(book)
        try store.insert([chapter])

        let environment = makeEnvironment(localFileResolver: { _ in nil })
        try environment.deleteBook(book)

        XCTAssertNil(try store.book(url: book.bookUrl))
        XCTAssertTrue(try store.chapters(bookUrl: book.bookUrl).isEmpty)
    }

    func testTheFileOfALocalBookSurvivesWithoutTheDeleteOriginalFlag() throws {
        let (book, file) = try makeLocalBook()
        try store.insert(book)

        let environment = makeEnvironment(localFileResolver: { _ in file })
        try environment.deleteBook(book, deleteOriginal: false)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testTheFileOfALocalBookIsDeletedWithTheDeleteOriginalFlag() throws {
        let (book, file) = try makeLocalBook()
        try store.insert(book)

        let environment = makeEnvironment(localFileResolver: { _ in file })
        try environment.deleteBook(book, deleteOriginal: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testANetworkBookNeverLosesAFile() throws {
        var book = Book(bookUrl: "https://example.com/book/1", name: "网络书", author: "作者")
        book.type = 0
        let file = workDirectory.appendingPathComponent("网络书.txt")
        try "内容".write(to: file, atomically: true, encoding: .utf8)
        try store.insert(book)

        let environment = makeEnvironment(localFileResolver: { _ in file })
        try environment.deleteBook(book, deleteOriginal: true)

        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testTheCacheOfTheBookIsCleared() throws {
        // A network book — a local TXT book always "has" its content.
        var book = Book(bookUrl: "https://example.com/book/1", name: "网络书", author: "作者")
        book.type = 0
        let chapter = BookChapter(url: "c1", title: "第一章", bookUrl: book.bookUrl, index: 0)
        try store.insert(book)
        try store.insert([chapter])
        let cache = BookCacheStorage(layout: BookCacheLayout(root: workDirectory.appendingPathComponent("cache")))
        try cache.saveText(book: book, chapter: chapter, content: "缓存内容")
        XCTAssertTrue(cache.hasContent(book: book, chapter: chapter))

        let environment = makeEnvironment(localFileResolver: { _ in nil }, cacheStorage: cache)
        try environment.deleteBook(book)

        XCTAssertFalse(cache.hasContent(book: book, chapter: chapter))
    }

    // MARK: - The importer

    func testTheImporterKeepsTheFileWhenTheOriginalIsNotDeleted() throws {
        let booksDirectory = workDirectory.appendingPathComponent("books", isDirectory: true)
        try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        let importer = LocalBookImporter(store: store, booksDirectory: booksDirectory)
        var book = Book(bookUrl: "u1", name: "示例书", author: "作者")
        book.type = BookType.local
        book.originName = "示例书.txt"
        let file = booksDirectory.appendingPathComponent("示例书.txt")
        try "内容".write(to: file, atomically: true, encoding: .utf8)
        try store.insert(book)

        try importer.removeBook(book, deleteOriginal: false)

        XCTAssertNil(try store.book(url: "u1"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testTheImporterDeletesTheFileWithTheOriginal() throws {
        let booksDirectory = workDirectory.appendingPathComponent("books", isDirectory: true)
        try FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        let importer = LocalBookImporter(store: store, booksDirectory: booksDirectory)
        var book = Book(bookUrl: "u1", name: "示例书", author: "作者")
        book.type = BookType.local
        book.originName = "示例书.txt"
        let file = booksDirectory.appendingPathComponent("示例书.txt")
        try "内容".write(to: file, atomically: true, encoding: .utf8)
        try store.insert(book)

        try importer.removeBook(book, deleteOriginal: true)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    // MARK: - The storage folder

    func testTheStorageFolderIsKeptInThePreferences() {
        let settings = AppSettings(store: InMemorySettingsStore())
        XCTAssertTrue(settings.defaultBookTreeUri.isEmpty)
        settings.defaultBookTreeUri = "/tmp/books"
        XCTAssertEqual(settings.defaultBookTreeUri, "/tmp/books")
    }
}
