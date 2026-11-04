//
//  LocalFileStoreTests.swift
//  LegadoCoreTests
//
//  Tests for the import of the files the user picks — the port of upstream
//  `GroupEditDialog`'s image picker.
//
//

import XCTest
@testable import LegadoCore

final class LocalFileStoreTests: XCTestCase {

    func testTheDataIsWrittenIntoTheDirectory() throws {
        let data = Data("hello".utf8)
        let path = try LocalFileStore.importData(data, suffix: "png", into: "covers")
        XCTAssertTrue(path.hasSuffix(".png"))
        let url = URL(fileURLWithPath: path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url), data)
        try? FileManager.default.removeItem(at: url)
    }

    func testTheSameDataGetsTheSameName() throws {
        let data = Data("same".utf8)
        let first = try LocalFileStore.importData(data, suffix: "jpg", into: "covers")
        let second = try LocalFileStore.importData(data, suffix: "jpg", into: "covers")
        XCTAssertEqual(first, second)
        try? FileManager.default.removeItem(atPath: first)
    }

    func testTheNameIsTheDigestOfTheData() throws {
        let data = Data("digest".utf8)
        let path = try LocalFileStore.importData(data, suffix: "", into: "covers")
        let name = URL(fileURLWithPath: path).lastPathComponent
        XCTAssertEqual(name, ScriptDigest.md5Hex(data))
        try? FileManager.default.removeItem(atPath: path)
    }

    func testTheFileIsRemoved() throws {
        let path = try LocalFileStore.importData(Data("remove".utf8), suffix: "png", into: "covers")
        XCTAssertTrue(LocalFileStore.removeFile(at: path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
        // Removing it twice is harmless.
        XCTAssertFalse(LocalFileStore.removeFile(at: path))
    }

    func testAForeignFileIsNotRemoved() {
        XCTAssertFalse(LocalFileStore.removeFile(at: "/etc/hosts"))
        XCTAssertFalse(LocalFileStore.removeFile(at: nil))
    }
}
