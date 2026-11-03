//
//  EpubTests.swift
//  LegadoCoreTests
//
//  Tests for the pure-Swift ZIP reader and the EPUB 2/3 reader.
//
//  Upstream reference:
//    * `modules/book/src/main/java/me/ag2s/epublib/**` (the vendored epublib fork)
//    * `app/src/main/java/io/legado/app/model/localBook/EpubFile.kt`
//

import Foundation
import XCTest
import CZlib
@testable import LegadoCore

/// Builds an uncompressed (STORED) ZIP archive in memory so the reader can be
/// exercised without shipping a binary fixture.
enum ZipBuilder {
    struct Entry {
        let name: String
        let data: Data
    }

    static func build(_ entries: [Entry]) -> Data {
        var output = Data()
        var central = Data()
        var offsets: [Int] = []

        func appendUInt16(_ value: UInt16) {
            output.append(UInt8(value & 0xff))
            output.append(UInt8((value >> 8) & 0xff))
        }
        func appendUInt32(_ value: UInt32) {
            output.append(UInt8(value & 0xff))
            output.append(UInt8((value >> 8) & 0xff))
            output.append(UInt8((value >> 16) & 0xff))
            output.append(UInt8((value >> 24) & 0xff))
        }

        for entry in entries {
            let nameData = Data(entry.name.utf8)
            let crc = entry.data.withUnsafeBytes { CZlib.cz_crc32($0.bindMemory(to: UInt8.self).baseAddress, entry.data.count) }
            offsets.append(output.count)

            // local file header
            appendUInt32(0x0403_4b50)
            appendUInt16(20)        // version needed
            appendUInt16(0)         // flags
            appendUInt16(0)         // method: stored
            appendUInt16(0)         // mod time
            appendUInt16(0)         // mod date
            appendUInt32(crc)
            appendUInt32(UInt32(entry.data.count))
            appendUInt32(UInt32(entry.data.count))
            appendUInt16(UInt16(nameData.count))
            appendUInt16(0)         // extra length
            output.append(nameData)
            output.append(entry.data)
        }

        let centralStart = output.count
        for (index, entry) in entries.enumerated() {
            let nameData = Data(entry.name.utf8)
            let crc = entry.data.withUnsafeBytes { CZlib.cz_crc32($0.bindMemory(to: UInt8.self).baseAddress, entry.data.count) }

            central.append(contentsOf: [0x50, 0x4b, 0x01, 0x02])
            central.append(contentsOf: [20, 0])        // version made by
            central.append(contentsOf: [20, 0])        // version needed
            central.append(contentsOf: [0, 0])         // flags
            central.append(contentsOf: [0, 0])         // method: stored
            central.append(contentsOf: [0, 0])         // mod time
            central.append(contentsOf: [0, 0])         // mod date
            central.append(contentsOf: [
                UInt8(crc & 0xff), UInt8((crc >> 8) & 0xff),
                UInt8((crc >> 16) & 0xff), UInt8((crc >> 24) & 0xff)
            ])
            central.append(contentsOf: [
                UInt8(entry.data.count & 0xff), UInt8((entry.data.count >> 8) & 0xff),
                UInt8((entry.data.count >> 16) & 0xff), UInt8((entry.data.count >> 24) & 0xff)
            ])
            central.append(contentsOf: [
                UInt8(entry.data.count & 0xff), UInt8((entry.data.count >> 8) & 0xff),
                UInt8((entry.data.count >> 16) & 0xff), UInt8((entry.data.count >> 24) & 0xff)
            ])
            central.append(contentsOf: [UInt8(nameData.count & 0xff), UInt8((nameData.count >> 8) & 0xff)])
            central.append(contentsOf: [0, 0])         // extra length
            central.append(contentsOf: [0, 0])         // comment length
            central.append(contentsOf: [0, 0])         // disk number
            central.append(contentsOf: [0, 0])         // internal attributes
            central.append(contentsOf: [0, 0, 0, 0])   // external attributes
            let offset = UInt32(offsets[index])
            central.append(contentsOf: [
                UInt8(offset & 0xff), UInt8((offset >> 8) & 0xff),
                UInt8((offset >> 16) & 0xff), UInt8((offset >> 24) & 0xff)
            ])
            central.append(nameData)
        }

        output.append(central)

        // end of central directory
        output.append(contentsOf: [0x50, 0x4b, 0x05, 0x06])
        output.append(contentsOf: [0, 0])             // disk number
        output.append(contentsOf: [0, 0])             // disk with the central directory
        let count = UInt16(entries.count)
        output.append(contentsOf: [UInt8(count & 0xff), UInt8((count >> 8) & 0xff)])
        output.append(contentsOf: [UInt8(count & 0xff), UInt8((count >> 8) & 0xff)])
        let centralSize = UInt32(central.count)
        output.append(contentsOf: [
            UInt8(centralSize & 0xff), UInt8((centralSize >> 8) & 0xff),
            UInt8((centralSize >> 16) & 0xff), UInt8((centralSize >> 24) & 0xff)
        ])
        let centralOffset = UInt32(centralStart)
        output.append(contentsOf: [
            UInt8(centralOffset & 0xff), UInt8((centralOffset >> 8) & 0xff),
            UInt8((centralOffset >> 16) & 0xff), UInt8((centralOffset >> 24) & 0xff)
        ])
        output.append(contentsOf: [0, 0])             // comment length
        return output
    }
}

final class ZipArchiveTests: XCTestCase {
    func testReadsStoredEntries() throws {
        let data = ZipBuilder.build([
            .init(name: "a.txt", data: Data("hello".utf8)),
            .init(name: "dir/b.txt", data: Data("world".utf8))
        ])
        let archive = try ZipArchive(data: data)
        XCTAssertEqual(archive.entries.count, 2)
        XCTAssertTrue(archive.contains("a.txt"))
        XCTAssertTrue(archive.contains("dir/b.txt"))
        XCTAssertFalse(archive.contains("missing.txt"))
        let entry = try XCTUnwrap(archive.entry(named: "dir/b.txt"))
        XCTAssertEqual(String(decoding: try archive.data(for: entry), as: UTF8.self), "world")
    }

    func testReturnsNilForAnUnknownEntry() throws {
        let data = ZipBuilder.build([.init(name: "a.txt", data: Data("hello".utf8))])
        let archive = try ZipArchive(data: data)
        XCTAssertNil(archive.entry(named: "nope"))
    }

    func testThrowsForANonArchive() throws {
        XCTAssertThrowsError(try ZipArchive(data: Data("not a zip".utf8)))
    }
}

final class EpubBookTests: XCTestCase {
    private func makeArchive() -> Data {
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>测试书名</dc:title>
            <dc:creator>测试作者</dc:creator>
            <dc:language>zh-CN</dc:language>
            <dc:description>书籍简介</dc:description>
          </metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
            <item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="c1"/>
            <itemref idref="c2"/>
          </spine>
        </package>
        """
        let ncx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head><meta name="dtb:uid" content="book-id"/></head>
          <docTitle><text>测试书名</text></docTitle>
          <navMap>
            <navPoint id="n1" playOrder="1">
              <navLabel><text>第一章</text></navLabel>
              <content src="ch1.xhtml"/>
            </navPoint>
            <navPoint id="n2" playOrder="2">
              <navLabel><text>第二章</text></navLabel>
              <content src="ch2.xhtml"/>
            </navPoint>
          </navMap>
        </ncx>
        """
        let chapter1 = """
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head>
        <body><p>第一段正文</p><p>第二段正文</p></body></html>
        """
        let chapter2 = """
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>第二章</title></head>
        <body><p>第三章正文</p></body></html>
        """
        return ZipBuilder.build([
            .init(name: "mimetype", data: Data("application/epub+zip".utf8)),
            .init(name: "META-INF/container.xml", data: Data(container.utf8)),
            .init(name: "OEBPS/content.opf", data: Data(opf.utf8)),
            .init(name: "OEBPS/toc.ncx", data: Data(ncx.utf8)),
            .init(name: "OEBPS/ch1.xhtml", data: Data(chapter1.utf8)),
            .init(name: "OEBPS/ch2.xhtml", data: Data(chapter2.utf8))
        ])
    }

    func testReadsTheMetadata() throws {
        let book = try EpubBook(archive: ZipArchive(data: makeArchive()))
        XCTAssertEqual(book.title, "测试书名")
        XCTAssertEqual(book.authors, ["测试作者"])
        XCTAssertEqual(book.description, "书籍简介")
        XCTAssertEqual(book.language, "zh-CN")
        XCTAssertEqual(book.packageDirectory, "OEBPS")
    }

    func testReadsTheSpineInOrder() throws {
        let book = try EpubBook(archive: ZipArchive(data: makeArchive()))
        XCTAssertEqual(book.contents.map(\.href), ["ch1.xhtml", "ch2.xhtml"])
    }

    func testReadsTheNavigationTree() throws {
        let book = try EpubBook(archive: ZipArchive(data: makeArchive()))
        XCTAssertEqual(book.tableOfContents.count, 2)
        XCTAssertEqual(book.tableOfContents[0].title, "第一章")
        // The navigation href is the path inside the archive (the NCX href resolved
        // against the NCX directory).
        XCTAssertEqual(book.tableOfContents[0].href, "OEBPS/ch1.xhtml")
        XCTAssertEqual(book.tableOfContents[1].title, "第二章")
    }

    func testThrowsWithoutAContainer() {
        let data = ZipBuilder.build([.init(name: "a.txt", data: Data("x".utf8))])
        XCTAssertThrowsError(try EpubBook(archive: ZipArchive(data: data))) { error in
            XCTAssertEqual(error as? EpubError, .missingContainer)
        }
    }
}

final class EpubFileTests: XCTestCase {
    private func makeBook() throws -> Book {
        var book = Book()
        book.bookUrl = "content://local/epub"
        book.origin = "content://local/epub"
        book.name = "测试书名"
        return book
    }

    private func makeArchive() -> Data {
        let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>测试书名</dc:title>
            <dc:creator>测试作者</dc:creator>
          </metadata>
          <manifest>
            <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
            <item id="c2" href="ch2.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="c1"/>
            <itemref idref="c2"/>
          </spine>
        </package>
        """
        let ncx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
          <head><meta name="dtb:uid" content="book-id"/></head>
          <navMap>
            <navPoint id="n1"><navLabel><text>第一章</text></navLabel><content src="ch1.xhtml"/></navPoint>
            <navPoint id="n2"><navLabel><text>第二章</text></navLabel><content src="ch2.xhtml"/></navPoint>
          </navMap>
        </ncx>
        """
        let chapter1 = """
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>第一章</title></head>
        <body><p>第一段正文</p><p>第二段正文</p></body></html>
        """
        let chapter2 = """
        <html xmlns="http://www.w3.org/1999/xhtml"><head><title>第二章</title></head>
        <body><p>第三章正文</p></body></html>
        """
        return ZipBuilder.build([
            .init(name: "mimetype", data: Data("application/epub+zip".utf8)),
            .init(name: "META-INF/container.xml", data: Data(container.utf8)),
            .init(name: "OEBPS/content.opf", data: Data(opf.utf8)),
            .init(name: "OEBPS/toc.ncx", data: Data(ncx.utf8)),
            .init(name: "OEBPS/ch1.xhtml", data: Data(chapter1.utf8)),
            .init(name: "OEBPS/ch2.xhtml", data: Data(chapter2.utf8))
        ])
    }

    func testBuildsTheChapterListFromTheNavigation() throws {
        let file = EpubFile(book: try EpubBook(archive: ZipArchive(data: makeArchive())))
        let chapters = try file.chapterList()
        XCTAssertEqual(chapters.map(\.title), ["第一章", "第二章"])
        XCTAssertEqual(chapters.map(\.index), [0, 1])
    }

    func testEveryChapterPointsAtTheNextOne() throws {
        let file = EpubFile(book: try EpubBook(archive: ZipArchive(data: makeArchive())))
        let chapters = try file.chapterList()
        XCTAssertEqual(chapters[0].variableBox.getVariable("nextUrl"), chapters[1].url)
        XCTAssertEqual(chapters[1].variableBox.getVariable("nextUrl"), "")
    }

    func testReadsTheChapterContent() throws {
        let file = EpubFile(book: try EpubBook(archive: ZipArchive(data: makeArchive())))
        let chapters = try file.chapterList()
        let content = try file.content(chapter: chapters[0])
        XCTAssertTrue(content.contains("第一段正文"))
        XCTAssertTrue(content.contains("第二段正文"))
        // The <title> element is removed by the upstream cleanup.
        XCTAssertFalse(content.contains("<title>"))
    }

    func testExposesTheMetadata() throws {
        let file = EpubFile(book: try EpubBook(archive: ZipArchive(data: makeArchive())))
        XCTAssertEqual(file.title, "测试书名")
        XCTAssertEqual(file.authors, ["测试作者"])
    }
}
