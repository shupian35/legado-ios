//
//  LocalBookBrowserTests.swift
//  LegadoCoreTests
//
//  The local book browser — upstream
//  `ui/book/import/local/ImportBookViewModel.kt` and
//  `utils/AlphanumComparator.kt`.
//

import XCTest
@testable import LegadoCore

// MARK: - The stub of the script engine

/// A JavaScript runtime stub that answers with a fixed JSON.
private final class JsonScriptEngine: RuleScriptEngine {
    var lastScript: String?
    var lastBindings: [String: RuleValue] = [:]
    var json = "{\"author\":\"作者\",\"name\":\"书名\"}"
    var fails = false

    func evaluate(_ script: String, bindings: [String: RuleValue]) throws -> RuleValue {
        lastScript = script
        lastBindings = bindings
        if fails { throw ScriptEngineError.unsupportedPlatform("no") }
        return .text(json)
    }
}

// MARK: - The name comparison

final class LocalBookBrowserCompareTests: XCTestCase {

    func testTheDigitChunksAreComparedByTheirLength() {
        // The upstream compares the length of the digit chunk first, so
        // "10" sorts AFTER "9".
        XCTAssertTrue(LocalBookBrowser.alphanumericLess("book9", "book10"))
        XCTAssertFalse(LocalBookBrowser.alphanumericLess("book10", "book9"))
    }

    func testTheEqualLengthDigitChunksAreComparedByTheirDigits() {
        XCTAssertTrue(LocalBookBrowser.alphanumericLess("book2", "book3"))
        XCTAssertFalse(LocalBookBrowser.alphanumericLess("book3", "book2"))
    }

    func testTheTextChunksAreComparedAsText() {
        XCTAssertTrue(LocalBookBrowser.alphanumericLess("apple", "banana"))
        XCTAssertFalse(LocalBookBrowser.alphanumericLess("banana", "apple"))
    }

    func testThePrefixSortsFirst() {
        XCTAssertTrue(LocalBookBrowser.alphanumericLess("book", "book2"))
    }

    func testTheLengthIsTheFallback() {
        XCTAssertTrue(LocalBookBrowser.alphanumericLess("ab", "abc"))
        XCTAssertEqual(LocalBookBrowser.compare("abc", "abc"), 0)
    }
}

// MARK: - The list

final class LocalBookBrowserListTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("browser-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("sub", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data("book".utf8).write(to: directory.appendingPathComponent("a.txt"))
        try Data("book".utf8).write(to: directory.appendingPathComponent("b.epub"))
        try Data("book".utf8).write(to: directory.appendingPathComponent("c.png"))
        try Data("book".utf8).write(to: directory.appendingPathComponent(".hidden"))
        try Data("book".utf8).write(
            to: directory.appendingPathComponent("sub/d.txt")
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testOnlyTheFoldersAndTheBooksAreListed() {
        let entries = LocalBookBrowser.list(directory: directory)
        let names = entries.map(\.name).sorted()
        XCTAssertEqual(names, ["a.txt", "b.epub", "sub"])
    }

    func testTheFoldersAreMarked() {
        let entries = LocalBookBrowser.list(directory: directory)
        let folder = entries.first { $0.name == "sub" }
        XCTAssertEqual(folder?.isDirectory, true)
        let file = entries.first { $0.name == "a.txt" }
        XCTAssertEqual(file?.isDirectory, false)
    }

    func testTheSortPutsTheFoldersFirst() {
        let entries = LocalBookBrowser.list(directory: directory)
        let sorted = LocalBookBrowser.sort(entries, by: .name)
        XCTAssertEqual(sorted.first?.name, "sub")
    }

    func testTheSortBySizePutsTheBiggestFileFirst() {
        let listed = LocalBookBrowser.list(directory: directory)
        let entries = listed.map { entry -> LocalBookEntry in
            LocalBookEntry(
                url: entry.url,
                name: entry.name,
                isDirectory: entry.isDirectory,
                size: entry.name == "a.txt" ? 100 : 10,
                modified: entry.modified
            )
        }
        let sorted = LocalBookBrowser.sort(entries, by: .size)
        // The folder always comes first.
        XCTAssertEqual(sorted.first?.isDirectory, true)
        XCTAssertEqual(sorted[1].size, 100)
    }

    func testTheFilterKeepsTheNamesThatContainTheKey() {
        let entries = LocalBookBrowser.list(directory: directory)
        let filtered = LocalBookBrowser.filter(entries, key: "a.")
        XCTAssertEqual(filtered.map(\.name), ["a.txt"])
    }

    func testAnEmptyFilterKeepsEverything() {
        let entries = LocalBookBrowser.list(directory: directory)
        XCTAssertEqual(LocalBookBrowser.filter(entries, key: "  ").count, entries.count)
    }
}

// MARK: - The JavaScript rule of the file names

final class LocalBookFileNameRuleTests: XCTestCase {

    func testTheRuleDecidesTheNameAndTheAuthor() {
        let engine = JsonScriptEngine()
        let result = LocalBook.analyzeNameAuthor(
            fileName: "任意名字.txt",
            fileNameRule: "name = '书名'; author = '作者';",
            scriptEngine: engine
        )
        XCTAssertEqual(result.name, "书名")
        XCTAssertEqual(result.author, "作者")
    }

    func testTheRuleGetsTheNameOfTheFileWithoutTheExtension() {
        let engine = JsonScriptEngine()
        _ = LocalBook.analyzeNameAuthor(
            fileName: "三体.txt",
            fileNameRule: "name = '书名';",
            scriptEngine: engine
        )
        XCTAssertEqual(engine.lastBindings["src"], .text("三体"))
    }

    func testTheRuleIsAppendedWithTheCapture() {
        let engine = JsonScriptEngine()
        _ = LocalBook.analyzeNameAuthor(
            fileName: "a.txt",
            fileNameRule: "name = '书名';",
            scriptEngine: engine
        )
        XCTAssertEqual(
            engine.lastScript,
            "name = '书名';\nJSON.stringify({author:author,name:name})"
        )
    }

    func testAFailingRuleFallsBackToThePatterns() {
        let engine = JsonScriptEngine()
        engine.fails = true
        let result = LocalBook.analyzeNameAuthor(
            fileName: "《三体》作者：刘慈欣.txt",
            fileNameRule: "name = '书名';",
            scriptEngine: engine
        )
        XCTAssertEqual(result.name, "三体")
    }

    func testWithoutTheRuleThePatternsAreUsed() {
        let result = LocalBook.analyzeNameAuthor(fileName: "《三体》作者：刘慈欣.txt")
        XCTAssertEqual(result.name, "三体")
        XCTAssertEqual(result.author, "刘慈欣")
    }
}
