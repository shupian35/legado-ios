import XCTest

@testable import LegadoCore

/// The shared export of the library (the iOS analogue of the upstream
/// `ContentProvider`).
final class SharedDataTests: XCTestCase {

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        return store
    }

    func testTheExportContainsTheBookshelf() throws {
        let store = try makeStore()
        var book = Book(bookUrl: "https://example.com/1", origin: "https://example.com", name: "测试书", author: "作者")
        book.durChapterIndex = 3
        book.durChapterPos = 120
        try store.insert([book])
        let library = try SharedDataExporter.export(store: store, exportedAt: 42)
        XCTAssertEqual(library.books.count, 1)
        XCTAssertEqual(library.books.first?.name, "测试书")
        XCTAssertEqual(library.books.first?.chapterIndex, 3)
        XCTAssertEqual(library.books.first?.chapterPos, 120)
        XCTAssertEqual(library.exportedAt, 42)
    }

    func testTheExportContainsTheSources() throws {
        let store = try makeStore()
        try store.insert([BookSource(bookSourceUrl: "https://example.com/src", bookSourceName: "书源")])
        try store.insert(RssSource(sourceUrl: "https://example.com/rss", sourceName: "订阅"))
        let library = try SharedDataExporter.export(store: store, exportedAt: 1)
        XCTAssertEqual(library.sources.count, 1)
        XCTAssertEqual(library.rssSources.count, 1)
    }

    func testTheJSONExportCanBeParsedBack() throws {
        let store = try makeStore()
        var book = Book(bookUrl: "https://example.com/1", origin: "https://example.com", name: "测试书", author: "作者")
        book.durChapterIndex = 2
        try store.insert([book])
        try store.insert([BookSource(bookSourceUrl: "https://example.com/src", bookSourceName: "书源")])
        try store.insert(RssSource(sourceUrl: "https://example.com/rss", sourceName: "订阅"))
        let library = try SharedDataExporter.export(store: store, exportedAt: 7)
        let json = SharedDataExporter.json(library)
        let parsed = try JSONValue.parse(json)
        XCTAssertEqual(parsed["version"]?.intValue, 1)
        XCTAssertEqual(parsed["exportedAt"]?.intValue, 7)
        let books = parsed["books"]
        if case .array(let items) = books {
            XCTAssertEqual(items.count, 1)
            XCTAssertEqual(items.first?["name"]?.textValue, "测试书")
            XCTAssertEqual(items.first?["chapterIndex"]?.intValue, 2)
        } else {
            XCTFail("the books are missing")
        }
        XCTAssertNotNil(parsed["bookSources"])
        XCTAssertNotNil(parsed["rssSources"])
    }

    func testTheAppGroupIdentifierIsStable() {
        XCTAssertEqual(AppGroup.identifier, "group.io.legado.ios.Legado")
        XCTAssertEqual(AppGroup.databaseFileName, "legado.sqlite")
        // On Linux (no App Groups) the container is not available.
        XCTAssertNil(AppGroup.containerURL())
    }
}
