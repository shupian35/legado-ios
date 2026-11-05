//
//  FileBrowserTests.swift
//  LegadoCoreTests
//
//  The file manager — upstream `ui/file/FileManageViewModel`.
//

import XCTest
@testable import LegadoCore

final class FileBrowserTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("legado-browser-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFolder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeFile(_ name: String, size: Int = 3) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 0x41, count: size).write(to: url)
        return url
    }

    // MARK: - The listing

    func testTheFoldersComeBeforeTheFiles() throws {
        try makeFolder("bFolder")
        try makeFile("aFile.txt")
        let entries = FileBrowser.list(root)
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertFalse(entries[1].isDirectory)
    }

    func testTheEntriesAreSortedByName() throws {
        try makeFile("c.txt")
        try makeFile("a.txt")
        try makeFile("b.txt")
        let names = FileBrowser.list(root).map { $0.name }
        XCTAssertEqual(names, ["a.txt", "b.txt", "c.txt"])
    }

    func testTheSizeIsRead() throws {
        try makeFile("a.txt", size: 42)
        let entries = FileBrowser.list(root)
        XCTAssertEqual(entries.first?.size, 42)
    }

    func testAMissingFolderIsEmpty() {
        let missing = root.appendingPathComponent("missing", isDirectory: true)
        XCTAssertTrue(FileBrowser.list(missing).isEmpty)
    }

    // MARK: - The search

    func testTheSearchKeepsTheMatchingEntries() throws {
        try makeFile("alpha.txt")
        try makeFile("beta.txt")
        let entries = FileBrowser.list(root)
        let filtered = FileBrowser.filtered(entries, query: "alp")
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.name, "alpha.txt")
    }

    func testAnEmptySearchKeepsEverything() throws {
        try makeFile("alpha.txt")
        try makeFile("beta.txt")
        let entries = FileBrowser.list(root)
        XCTAssertEqual(FileBrowser.filtered(entries, query: "  ").count, 2)
    }

    func testTheSearchIgnoresTheCase() throws {
        try makeFile("Alpha.txt")
        let entries = FileBrowser.list(root)
        XCTAssertEqual(FileBrowser.filtered(entries, query: "alpha").count, 1)
    }

    // MARK: - The deletion

    func testAFileIsDeleted() throws {
        let url = try makeFile("a.txt")
        let entry = BrowserEntry(name: "a.txt", url: url, isDirectory: false)
        XCTAssertTrue(FileBrowser.delete(entry))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testAMissingFileIsNotDeleted() {
        let url = root.appendingPathComponent("missing.txt")
        let entry = BrowserEntry(name: "missing.txt", url: url, isDirectory: false)
        XCTAssertFalse(FileBrowser.delete(entry))
    }

    // MARK: - The folder size

    func testTheFolderSizeIsTheSumOfTheFiles() throws {
        try makeFile("a.txt", size: 10)
        try makeFile("b.txt", size: 5)
        XCTAssertEqual(FileBrowser.folderSize(root), 15)
    }
}
