//
//  UmdTests.swift
//  LegadoCoreTests
//
//  Tests for the UMD reader.
//
//  Upstream reference:
//    * modules/book/src/main/java/me/ag2s/umdlib/umd/UmdReader.java
//    * modules/book/src/main/java/me/ag2s/umdlib/domain/UmdChapters.java
//    * app/src/main/java/io/legado/app/model/localBook/UmdFile.kt
//

import Foundation
import XCTest
import CZlib
@testable import LegadoCore

/// Builds a UMD file in memory so the reader can be exercised without a
/// binary fixture. The layout follows the format description that the
/// upstream reader implements.
enum UmdBuilder {
    static func build(title: String, author: String, bookType: String, chapters: [String]) -> Data {
        var output = Data()

        func appendUInt8(_ value: UInt8) { output.append(value) }
        func appendUInt16LE(_ value: UInt16) {
            output.append(UInt8(value & 0xff))
            output.append(UInt8((value >> 8) & 0xff))
        }
        func appendUInt32LE(_ value: UInt32) {
            output.append(UInt8(value & 0xff))
            output.append(UInt8((value >> 8) & 0xff))
            output.append(UInt8((value >> 16) & 0xff))
            output.append(UInt8((value >> 24) & 0xff))
        }
        func appendInt32LE(_ value: Int32) { appendUInt32LE(UInt32(bitPattern: value)) }

        // The magic number.
        appendUInt32LE(0xde9a_9b89)

        /// A '#' section: the type, the flag, the length byte and the body.
        func appendSection(_ type: UInt16, _ body: Data) {
            appendUInt8(0x23)              // '#'
            appendUInt16LE(type)
            appendUInt8(0x00)              // the flag
            appendUInt8(UInt8(body.count + 5))
            output.append(body)
        }

        /// A '$' additional section: the check number, the length and the payload.
        func appendAdditional(_ check: UInt32, _ payload: Data) {
            appendUInt8(0x24)              // '$'
            appendUInt32LE(check)
            appendUInt32LE(UInt32(payload.count + 9))
            output.append(payload)
        }

        func utf16(_ text: String) -> Data {
            var data = Data()
            for unit in text.utf16 {
                data.append(UInt8(unit & 0xff))
                data.append(UInt8((unit >> 8) & 0xff))
            }
            return data
        }

        // The metadata sections.
        appendSection(2, utf16(title))
        appendSection(3, utf16(author))
        appendSection(7, utf16(bookType))

        // The chapter contents, concatenated — the offsets address them.
        var content = Data()
        var offsets: [Int] = []
        var titlePayload = Data()
        for chapter in chapters {
            offsets.append(content.count)
            let bytes = utf16(chapter)
            content.append(bytes)
            titlePayload.append(UInt8(bytes.count))
            titlePayload.append(bytes)
        }

        // Section 11 — the total content length.
        var lengthSection = Data()
        lengthSection.append(contentsOf: withUnsafeBytes(of: Int32(content.count).littleEndian, Array.init))
        appendSection(11, lengthSection)

        // Section 131 — the chapter offsets.
        let offsetsCheck: UInt32 = 0x1122_3344
        var offsetsSection = Data()
        offsetsSection.append(contentsOf: withUnsafeBytes(of: Int32(bitPattern: offsetsCheck).littleEndian, Array.init))
        appendSection(131, offsetsSection)
        var offsetsPayload = Data()
        for offset in offsets {
            offsetsPayload.append(contentsOf: withUnsafeBytes(of: Int32(offset).littleEndian, Array.init))
        }
        appendAdditional(offsetsCheck, offsetsPayload)

        // Section 132 — the chapter titles and the compressed text.
        let titlesCheck: UInt32 = 0x5566_7788
        let contentCheck: UInt32 = 0x99aa_bbcc
        var titlesSection = Data()
        titlesSection.append(contentsOf: withUnsafeBytes(of: Int32(bitPattern: titlesCheck).littleEndian, Array.init))
        appendSection(132, titlesSection)
        appendAdditional(titlesCheck, titlePayload)

        var compressed = Data(count: max(content.count * 2, 1024))
        var compressedLength = 0
        let compressedCapacity = compressed.count
        let status = content.withUnsafeBytes { source -> Int32 in
            compressed.withUnsafeMutableBytes { destination -> Int32 in
                CZlib.cz_compress_zlib(
                    source.bindMemory(to: UInt8.self).baseAddress,
                    content.count,
                    destination.bindMemory(to: UInt8.self).baseAddress,
                    compressedCapacity,
                    &compressedLength
                )
            }
        }
        XCTAssertEqual(status, 0)
        compressed.count = compressedLength
        appendAdditional(contentCheck, compressed)

        // Section 12 — the end of the file.
        var endSection = Data()
        endSection.append(contentsOf: withUnsafeBytes(of: Int32(0).littleEndian, Array.init))
        appendSection(12, endSection)

        return output
    }
}

final class UmdReaderTests: XCTestCase {
    func testReadsTheMetadata() throws {
        let data = UmdBuilder.build(
            title: "测试书名", author: "测试作者", bookType: "小说",
            chapters: ["第一章内容", "第二章内容"]
        )
        let book = try UmdReader.read(data)
        XCTAssertEqual(book.header.title, "测试书名")
        XCTAssertEqual(book.header.author, "测试作者")
        XCTAssertEqual(book.header.bookType, "小说")
    }

    func testReadsTheChapterList() throws {
        let data = UmdBuilder.build(
            title: "书", author: "作者", bookType: "小说",
            chapters: ["第一章", "第二章", "第三章"]
        )
        let file = try UmdFile(data: data)
        let chapters = file.chapterList(bookUrl: "content://local/umd")
        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章", "第三章"])
        XCTAssertEqual(chapters.map(\.index), [0, 1, 2])
        XCTAssertEqual(chapters.map(\.url), ["0", "1", "2"])
        XCTAssertEqual(chapters.map(\.bookUrl), ["content://local/umd", "content://local/umd", "content://local/umd"])
    }

    func testReadsTheChapterContent() throws {
        let data = UmdBuilder.build(
            title: "书", author: "作者", bookType: "小说",
            chapters: ["第一章内容", "第二章内容"]
        )
        let file = try UmdFile(data: data)
        let chapters = file.chapterList(bookUrl: "content://local/umd")
        XCTAssertEqual(file.content(chapter: chapters[0]), "第一章内容")
        XCTAssertEqual(file.content(chapter: chapters[1]), "第二章内容")
    }

    func testUpdatesTheBookInfo() throws {
        let data = UmdBuilder.build(title: "书名", author: "作者名", bookType: "类型", chapters: ["正文"])
        let file = try UmdFile(data: data)
        let book = file.updateBookInfo(Book())
        XCTAssertEqual(book.name, "书名")
        XCTAssertEqual(book.author, "作者名")
        XCTAssertEqual(book.kind, "类型")
    }

    func testThrowsForAWrongHeader() {
        XCTAssertThrowsError(try UmdReader.read(Data([0x00, 0x01, 0x02, 0x03]))) { error in
            XCTAssertEqual(error as? UmdError, .wrongHeader)
        }
    }
}
