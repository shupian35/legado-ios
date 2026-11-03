//
//  MobiTests.swift
//  LegadoCoreTests
//
//  The MOBI / AZW reader — the port of the upstream `lib/mobi/` library.
//
//  The tests build a synthetic MOBI file (a PalmDB container with a MOBI
//  header record and a few text records) and check the reader against it.
//

import XCTest
@testable import LegadoCore

final class MobiTests: XCTestCase {

    // MARK: - The fixture

    /// A synthetic MOBI file.
    struct Fixture {

        /// The big-endian bytes of an unsigned 16-bit value.
        static func u16(_ value: Int) -> [UInt8] {
            [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
        }

        /// The big-endian bytes of an unsigned 32-bit value.
        static func u32(_ value: Int) -> [UInt8] {
            [
                UInt8((value >> 24) & 0xFF),
                UInt8((value >> 16) & 0xFF),
                UInt8((value >> 8) & 0xFF),
                UInt8(value & 0xFF)
            ]
        }

        /// The bytes of a string.
        static func text(_ value: String) -> [UInt8] {
            Array(value.utf8)
        }

        /// The header record (the PalmDOC header + the MOBI header + the EXTH
        /// + the title).
        static func headerRecord(
            title: String,
            textRecordCount: Int,
            exthRecords: [(type: Int, value: String)] = [],
            version: Int = 6
        ) -> [UInt8] {
            // The PalmDOC header (16 bytes) + the MOBI header (232 bytes).
            var record = [UInt8](repeating: 0, count: 248)
            record.replaceSubrange(0..<2, with: u16(1))                  // the compression: none
            record.replaceSubrange(8..<10, with: u16(textRecordCount))   // the text records
            record.replaceSubrange(10..<12, with: u16(4096))             // the record size
            record.replaceSubrange(16..<20, with: text("MOBI"))
            record.replaceSubrange(20..<24, with: u32(232))              // the header length
            record.replaceSubrange(24..<28, with: u32(2))                // the type: a book
            record.replaceSubrange(28..<32, with: u32(65001))            // the encoding: UTF-8
            record.replaceSubrange(32..<36, with: u32(123456))           // the uid
            record.replaceSubrange(36..<40, with: u32(version))          // the version

            // The EXTH.
            var exth: [UInt8] = []
            if !exthRecords.isEmpty {
                var body: [UInt8] = []
                for item in exthRecords {
                    let payload = text(item.value)
                    body += u32(item.type)
                    body += u32(payload.count + 8)
                    body += payload
                }
                exth = text("EXTH") + u32(0) + u32(exthRecords.count) + body
                record.replaceSubrange(128..<132, with: u32(0x40))       // the EXTH flag
            }

            // The title follows the EXTH.
            let titleOffset = 248 + exth.count
            let titleBytes = text(title)
            record.replaceSubrange(84..<88, with: u32(titleOffset))
            record.replaceSubrange(88..<92, with: u32(titleBytes.count))

            return record + exth + titleBytes
        }

        /// The PalmDB container — upstream `PDBFile`.
        static func pdb(records: [[UInt8]]) -> [UInt8] {
            let headerSize = 78 + records.count * 8
            var data = [UInt8](repeating: 0, count: headerSize)
            let name = text("测试书")
            data.replaceSubrange(0..<name.count, with: name)
            data.replaceSubrange(60..<64, with: text("BOOK"))
            data.replaceSubrange(64..<68, with: text("MOBI"))
            data.replaceSubrange(76..<78, with: u16(records.count))
            var offset = headerSize
            for (index, record) in records.enumerated() {
                data.replaceSubrange(78 + index * 8..<(78 + index * 8 + 4), with: u32(offset))
                data += record
                offset += record.count
            }
            return data
        }

        /// Writes a raw file into the temporary directory.
        static func writeRaw(_ bytes: [UInt8], name: String = "book.mobi") throws -> URL {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(bytes).write(to: url)
            return url
        }

        /// Writes a MOBI file into the temporary directory.
        static func write(
            title: String = "测试书",
            texts: [String],
            exthRecords: [(type: Int, value: String)] = [],
            version: Int = 6,
            name: String = "book.mobi"
        ) throws -> URL {
            let header = headerRecord(
                title: title,
                textRecordCount: texts.count,
                exthRecords: exthRecords,
                version: version
            )
            var records: [[UInt8]] = [header]
            for item in texts {
                records.append(text(item))
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathComponent(name)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data(pdb(records: records)).write(to: url)
            return url
        }
    }

    // MARK: - The container

    func testTheContainerIsRead() throws {
        let url = try Fixture.write(texts: ["hello"])
        defer { try? FileManager.default.removeItem(at: url) }

        let pdb = try PDBFile(url: url)
        XCTAssertEqual(pdb.name, "测试书")
        XCTAssertEqual(pdb.type, "BOOK")
        XCTAssertEqual(pdb.creator, "MOBI")
        XCTAssertEqual(pdb.recordCount, 2)
        XCTAssertEqual(String(decoding: pdb.recordData(1), as: UTF8.self), "hello")
    }

    func testAnEmptyFileIsRejected() throws {
        let url = try Fixture.writeRaw([0x01, 0x02])
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try PDBFile(url: url)) { error in
            XCTAssertEqual(error as? MobiError, .invalidHeader)
        }
    }

    // MARK: - The header

    func testTheHeaderIsParsed() throws {
        let url = try Fixture.write(
            title: "测试书",
            texts: ["<html><body>第一章</body></html>"]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let book = try MobiBook.read(url: url)
        XCTAssertEqual(book.mobi.identifier, "MOBI")
        XCTAssertEqual(book.mobi.title, "测试书")
        XCTAssertEqual(book.mobi.encoding, 65001)
        XCTAssertEqual(book.mobi.version, 6)
        XCTAssertEqual(book.mobi.uid, 123456)
        XCTAssertFalse(book.isKF8)
    }

    func testTheExthRecordsAreParsed() throws {
        let url = try Fixture.write(
            title: "测试书",
            texts: ["<html></html>"],
            exthRecords: [(100, "作者甲"), (103, "这是简介")]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let book = try MobiBook.read(url: url)
        XCTAssertEqual(book.metadata.author, ["作者甲"])
        XCTAssertEqual(book.metadata.description, "这是简介")
        XCTAssertEqual(book.metadata.title, "测试书")
    }

    func testAFileWithoutTheMobiMagicIsRejected() throws {
        var records: [[UInt8]] = [[UInt8](repeating: 0, count: 300)]
        records[0].replaceSubrange(16..<20, with: Fixture.text("XXXX"))
        let url = try Fixture.writeRaw(Fixture.pdb(records: records))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try MobiBook.read(url: url)) { error in
            XCTAssertEqual(error as? MobiError, .invalidHeader)
        }
    }

    // MARK: - The text

    func testTheTextRecordsAreConcatenated() throws {
        let url = try Fixture.write(texts: ["第一段", "第二段"])
        defer { try? FileManager.default.removeItem(at: url) }

        let book = try MobiBook.read(url: url)
        XCTAssertEqual(String(decoding: book.allText(), as: UTF8.self), "第一段第二段")
        XCTAssertEqual(String(decoding: book.textRecord(0), as: UTF8.self), "第一段")
        XCTAssertEqual(String(decoding: book.textRecord(1), as: UTF8.self), "第二段")
    }

    func testTheTextOfARangeIsRead() throws {
        let url = try Fixture.write(texts: ["第一段", "第二段"])
        defer { try? FileManager.default.removeItem(at: url) }

        let book = try MobiBook.read(url: url)
        // The offsets are byte offsets (the upstream works on the byte stream).
        let bytes = book.text(from: 3, length: 3)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self), "一")
    }

    // MARK: - The sections

    func testThePageBreaksSplitTheSections() throws {
        let url = try Fixture.write(
            texts: [
                "<html><body>第一页<mbp:pagebreak/>第二页<mbp:pagebreak/>第三页</body></html>"
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let book = try MobiBook.read(url: url)
        // Two page breaks ⇒ three sections. The offsets are byte offsets:
        // "<html><body>" is 12 bytes, "第一页" is 9 bytes and the page break
        // marker "<mbp:pagebreak/>" is 16 bytes.
        XCTAssertEqual(book.kf6Sections?.count, 3)
        XCTAssertEqual(book.kf6Sections?.first?.href, "filepos:0000000000")
        let second = book.kf6Sections?[1]
        XCTAssertEqual(second?.href, "filepos:0000000037")
        XCTAssertTrue(second.map { book.kf6SectionText($0).contains("第二页") } ?? false)
    }

    func testThePageBreakScanner() {
        let text = Array("a<mbp:pagebreak/>b<PAGEBREAK>c".utf8)
        let breaks = MobiBook.pageBreaks(text)
        XCTAssertEqual(breaks.count, 2)
        XCTAssertEqual(breaks[0].lowerBound, 1)
    }

    func testTheSectionOfAnHrefIsFound() throws {
        let url = try Fixture.write(texts: ["<html>第一页<mbp:pagebreak/>第二页</html>"])
        defer { try? FileManager.default.removeItem(at: url) }

        let book = try MobiBook.read(url: url)
        let section = book.kf6Section(byHref: "filepos:0000000000")
        XCTAssertNotNil(section)
        XCTAssertEqual(book.kf6SectionText(section!).contains("第一页"), true)
        XCTAssertNil(book.kf6Section(byHref: "not-a-href"))
    }

    // MARK: - The local book

    func testTheBookWithoutATableOfContentsHasOneChapter() throws {
        let url = try Fixture.write(
            title: "测试书",
            texts: ["<html><head><title>卷首</title></head><body>内容</body></html>"]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let local = try MobiLocalBook.open(url: url)
        let chapters = local.chapterList(bookUrl: "file:///book.mobi")
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].title, "卷首")
        XCTAssertEqual(chapters[0].bookUrl, "file:///book.mobi")
        XCTAssertTrue(chapters[0].url.hasPrefix("0:filepos:"))
    }

    func testTheBookInfoComesFromTheMetadata() throws {
        let url = try Fixture.write(
            title: "书名",
            texts: ["<html></html>"],
            exthRecords: [(100, "作者甲"), (103, "简介")]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        var book = Book()
        book.originName = "文件名.mobi"
        let local = try MobiLocalBook.open(url: url)
        local.upBookInfo(&book)
        XCTAssertEqual(book.name, "书名")
        XCTAssertEqual(book.author, "作者甲")
        XCTAssertEqual(book.intro, "简介")
    }

    func testTheContentOfAChapterIsCleaned() throws {
        let url = try Fixture.write(
            texts: [
                "<html><head><title>标题</title></head><body><p style=\"display:none\">隐藏</p>正文</body></html>"
            ]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let local = try MobiLocalBook.open(url: url)
        let chapters = local.chapterList(bookUrl: "file:///book.mobi")
        let content = local.content(chapter: chapters[0]) ?? ""
        XCTAssertTrue(content.contains("正文"))
        XCTAssertFalse(content.contains("隐藏"))
        XCTAssertFalse(content.contains("<title>"))
    }

    func testTheMobiFilesAreDetected() {
        XCTAssertEqual(LocalBook.Format.detect(fileName: "book.mobi"), .mobi)
        XCTAssertEqual(LocalBook.Format.detect(fileName: "book.azw3"), .mobi)
        XCTAssertEqual(LocalBook.Format.detect(fileName: "book.AZW"), .mobi)
        XCTAssertEqual(LocalBook.Format.detect(fileName: "book.txt"), .txt)
        XCTAssertNil(LocalBook.Format.detect(fileName: "book.doc"))
    }

    func testTheMobiBookIsImported() throws {
        let url = try Fixture.write(
            title: "书名",
            texts: ["<html><body><mbp:pagebreak/>第二部分</body></html>"],
            exthRecords: [(100, "作者甲")]
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let imported = try LocalBook.importFile(fileURL: url, bookUrl: "file:///book.mobi")
        XCTAssertEqual(imported.book.name, "书名")
        XCTAssertEqual(imported.book.author, "作者甲")
        // Without a table of contents the upstream falls back to the first
        // section as a single "卷首" chapter (`MobiFile.getChapterListKF6`).
        XCTAssertEqual(imported.chapters.count, 1)
        XCTAssertEqual(imported.book.totalChapterNum, 1)
        XCTAssertTrue(imported.book.isLocal)
    }

    // MARK: - The decompressors

    func testTheLz77Decompressor() {
        let decompressor = MobiLz77Decompressor(textRecordSize: 4096)
        // 0x03 = copy three literals, then the literals.
        let compressed: [UInt8] = [0x03, 0x41, 0x42, 0x43]
        XCTAssertEqual(String(decoding: decompressor.decompress(compressed), as: UTF8.self), "ABC")
    }

    func testTheLz77BackReference() {
        let decompressor = MobiLz77Decompressor(textRecordSize: 4096)
        // A literal "A", then a back reference: the marker 0x80 and the second
        // byte (the location << 3) | (the length - 3) = (1 << 3) | 0.
        let compressed: [UInt8] = [0x41, 0x80, 0x08]
        XCTAssertEqual(String(decoding: decompressor.decompress(compressed), as: UTF8.self), "AAAA")
    }

    func testTheLz77BackReferenceOutsideTheOutputIsIgnored() {
        let decompressor = MobiLz77Decompressor(textRecordSize: 4096)
        // The location 0 is invalid — the upstream skips the copy.
        let compressed: [UInt8] = [0x41, 0x80, 0x00]
        XCTAssertEqual(String(decoding: decompressor.decompress(compressed), as: UTF8.self), "A")
    }

    func testThePlainDecompressor() {
        let decompressor = MobiPlainDecompressor()
        XCTAssertEqual(decompressor.decompress([0x41, 0x42]), [0x41, 0x42])
    }
}
