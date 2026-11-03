//
//  LocalBookScannerTests.swift
//  LegadoCoreTests
//
//  The scan of a folder for the local books — upstream
//  `ImportBookViewModel.scanDoc`.
//

import XCTest
import Foundation
@testable import LegadoCore

final class LocalBookScannerTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("legado-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeFile(_ name: String, in directory: URL? = nil) throws -> URL {
        let target = (directory ?? root).appendingPathComponent(name)
        try Data("content".utf8).write(to: target)
        return target
    }

    func testTheScanFindsTheBookFiles() throws {
        _ = try makeFile("a.txt")
        _ = try makeFile("b.epub")
        _ = try makeFile("c.pdf")
        let result = LocalBookScanner.scan(directory: root)
        XCTAssertEqual(result.books.count, 3)
        XCTAssertEqual(result.archives.count, 0)
    }

    func testTheScanFindsTheArchives() throws {
        _ = try makeFile("a.zip")
        _ = try makeFile("b.rar")
        _ = try makeFile("c.7z")
        let result = LocalBookScanner.scan(directory: root)
        XCTAssertEqual(result.archives.count, 3)
        XCTAssertEqual(result.books.count, 0)
    }

    func testTheScanWalksTheSubFolders() throws {
        let sub = root.appendingPathComponent("sub")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        _ = try makeFile("a.txt")
        _ = try makeFile("b.txt", in: sub)
        let result = LocalBookScanner.scan(directory: root)
        XCTAssertEqual(result.books.count, 2)
    }

    func testTheScanIgnoresTheOtherFiles() throws {
        _ = try makeFile("a.txt")
        _ = try makeFile("notes.docx")
        _ = try makeFile("image.png")
        let result = LocalBookScanner.scan(directory: root)
        XCTAssertEqual(result.books.count, 1)
    }

    func testTheScanOfAnEmptyFolderIsEmpty() {
        let result = LocalBookScanner.scan(directory: root)
        XCTAssertTrue(result.isEmpty)
    }

    func testTheScanOfAMissingFolderIsEmpty() {
        let missing = root.appendingPathComponent("missing")
        let result = LocalBookScanner.scan(directory: missing)
        XCTAssertTrue(result.isEmpty)
    }

    /// The extension is matched without the case.
    func testTheExtensionIsMatchedWithoutTheCase() throws {
        _ = try makeFile("A.TXT")
        let result = LocalBookScanner.scan(directory: root)
        XCTAssertEqual(result.books.count, 1)
    }

    /// The port cannot decode MOBI and AZW yet.
    func testTheUnsupportedBooksAreReported() throws {
        let mobi = try makeFile("a.mobi")
        XCTAssertFalse(LocalBookScanner.isSupportedBook(mobi))
        let txt = try makeFile("b.txt")
        XCTAssertTrue(LocalBookScanner.isSupportedBook(txt))
    }
}
