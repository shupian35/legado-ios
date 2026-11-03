//
//  PdfBookTests.swift
//  LegadoCoreTests
//
//  Tests for the PDF import — the port of
//  app/src/main/java/io/legado/app/model/localBook/PdfFile.kt — and for the
//  local-book format dispatcher.
//

import XCTest
@testable import LegadoCore

final class PdfBookTests: XCTestCase {

    // MARK: - Helpers

    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("legado-pdf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    /// A minimal PDF file with a page tree.
    private func makePdf(pageCount: Int) -> Data {
        var text = "%PDF-1.4\n"
        for index in 0..<pageCount {
            text += "1 0 obj << /Type /Page /Parent 2 0 R >> endobj\n"
            text += "content \(index) stream\nBT /F1 12 Tf 72 720 Td (page \(index)) Tj ET\nendstream\n"
        }
        text += "2 0 obj << /Type /Pages /Kids ["
        for index in 0..<pageCount {
            text += index == 0 ? "1 0 R" : "1 0 R"
        }
        text += "] /Count \(pageCount) >> endobj\n"
        text += "trailer << /Root 2 0 R >>\n%%EOF\n"
        return Data(text.utf8)
    }

    private func makeFile(_ name: String, _ data: Data) throws -> URL {
        let url = workDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    // MARK: - The raw reader

    func testCountsThePagesOfThePageTree() {
        XCTAssertEqual(RawPdfDocument.countPages(in: makePdf(pageCount: 7)), 7)
    }

    func testCountsThePageObjectsWhenTheTreeHasNoCount() {
        let text = "%PDF-1.4\n1 0 obj << /Type /Page >> endobj\n2 0 obj << /Type /Page >> endobj\n%%EOF\n"
        XCTAssertEqual(RawPdfDocument.countPages(in: Data(text.utf8)), 2)
    }

    func testRejectsAFileThatIsNotAPdf() {
        let document = try? RawPdfDocument(data: Data("hello".utf8))
        XCTAssertNil(document)
    }

    func testOpensAPdfFile() throws {
        let document = try RawPdfDocument(data: makePdf(pageCount: 3))
        XCTAssertEqual(document.pageCount, 3)
    }

    // MARK: - The chapter list

    func testEveryPageBecomesAChapter() {
        let document = try! RawPdfDocument(data: makePdf(pageCount: 3))
        let chapters = PdfBook.chapterList(document: document)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0].title, "第 1 页")
        XCTAssertEqual(chapters[2].title, "第 3 页")
        XCTAssertEqual(chapters[1].index, 1)
        XCTAssertEqual(chapters[0].url, "0000")
    }

    // MARK: - The import

    func testImportsAPdfAsALocalImageBook() throws {
        let url = try makeFile("某本pdf.pdf", makePdf(pageCount: 4))
        let imported = try LocalBook.importFile(fileURL: url)
        XCTAssertEqual(imported.book.originName, "某本pdf.pdf")
        XCTAssertTrue(imported.book.type & BookType.local != 0)
        XCTAssertTrue(imported.book.type & BookType.image != 0)
        XCTAssertEqual(imported.chapters.count, 4)
        XCTAssertEqual(imported.book.totalChapterNum, 4)
    }

    func testTheChapterFileNameIsPadded() {
        XCTAssertEqual(PdfBook.chapterFileName(index: 0), "0000")
        XCTAssertEqual(PdfBook.chapterFileName(index: 12), "0012")
    }

    // MARK: - The dispatcher

    func testTheFormatIsDetectedFromTheFileName() {
        XCTAssertEqual(LocalBook.Format.detect(fileName: "a.txt"), .txt)
        XCTAssertEqual(LocalBook.Format.detect(fileName: "a.EPUB"), .epub)
        XCTAssertEqual(LocalBook.Format.detect(fileName: "a.umd"), .umd)
        XCTAssertEqual(LocalBook.Format.detect(fileName: "a.pdf"), .pdf)
        XCTAssertEqual(LocalBook.Format.detect(fileName: "a.mobi"), .mobi)
        XCTAssertNil(LocalBook.Format.detect(fileName: "a.doc"))
    }

    func testTheTxtBranchStillWorks() throws {
        let url = workDirectory.appendingPathComponent("书.txt")
        let content = "第一章 开始\n正文内容\n第二章 后续\n更多内容\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
        let imported = try LocalBook.importFile(
            fileURL: url,
            tocRules: [TxtTocRule(row: [:])]
        )
        XCTAssertEqual(imported.book.name, "书")
        XCTAssertFalse(imported.chapters.isEmpty)
    }

    func testAnUnsupportedFormatIsReported() throws {
        let url = workDirectory.appendingPathComponent("a.doc")
        try Data("x".utf8).write(to: url)
        XCTAssertThrowsError(try LocalBook.importFile(fileURL: url)) { error in
            guard case .unsupportedFormat = error as? LocalBook.LocalBookError else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testABrokenMobiFileIsReported() throws {
        let url = workDirectory.appendingPathComponent("a.mobi")
        try Data("x".utf8).write(to: url)
        XCTAssertThrowsError(try LocalBook.importFile(fileURL: url)) { error in
            // The MOBI format is supported — a broken file is a header error.
            XCTAssertEqual(error as? MobiError, .invalidHeader)
        }
    }
}
