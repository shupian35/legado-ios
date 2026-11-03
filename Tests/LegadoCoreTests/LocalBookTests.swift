//
//  LocalBookTests.swift
//  LegadoCoreTests
//
//  Tests for the local-book layer: the encoding detector, the TXT parser
//  and the file-name analysis.
//

import XCTest
@testable import LegadoCore

final class LocalBookTests: XCTestCase {

    // MARK: - Helpers

    private var workDirectory: URL!

    override func setUpWithError() throws {
        workDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("legado-local-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let workDirectory {
            try? FileManager.default.removeItem(at: workDirectory)
        }
    }

    private func makeFile(_ name: String, _ content: String) throws -> URL {
        let url = workDirectory.appendingPathComponent(name)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func makeBinaryFile(_ name: String, _ data: Data) throws -> URL {
        let url = workDirectory.appendingPathComponent(name)
        try data.write(to: url)
        return url
    }

    private func tocRule(_ name: String, _ rule: String, serial: Int64 = 1) -> TxtTocRule {
        var value = TxtTocRule(row: [:])
        value.id = serial
        value.name = name
        value.rule = rule
        value.serialNumber = serial
        value.enable = true
        return value
    }

    // MARK: - EncodingDetector

    func testDetectsUtf8Bom() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(contentsOf: Array("内容".utf8))
        XCTAssertEqual(EncodingDetector.detect(data), .utf8)
    }

    func testDetectsPlainUtf8() {
        let data = Data("这是一本中文书的开头内容。".utf8)
        XCTAssertEqual(EncodingDetector.detect(data), .utf8)
    }

    func testDecodesUtf8() {
        let data = Data("第一章 开始".utf8)
        XCTAssertEqual(EncodingDetector.decode(data, encoding: String.Encoding.utf8), "第一章 开始")
    }

    func testDetectsBigEndianUtf16Bom() {
        var data = Data([0xFE, 0xFF, 0x00, 0x41])
        data.append(contentsOf: [0x00, 0x42])
        XCTAssertEqual(EncodingDetector.detect(data), .utf16BigEndian)
    }

    // MARK: - TextBook

    func testParsesTheChapterListWithARule() throws {
        let text = """
        第一章 起点
        这是第一章的内容。
        第二章 发展
        这是第二章的内容。
        第三章 结局
        这是第三章的内容。
        """
        let url = try makeFile("book.txt", text)
        let book = TextBook(fileURL: url)
        let parsed = try book.chapterList(tocRules: [tocRule("章节", "第.章\\s.*")])

        XCTAssertEqual(parsed.chapters.count, 3)
        XCTAssertEqual(parsed.chapters.map(\.title), ["第一章 起点", "第二章 发展", "第三章 结局"])
        // The chapter offsets must be monotonically increasing.
        let starts = parsed.chapters.compactMap(\.start)
        XCTAssertEqual(starts, starts.sorted())
        XCTAssertEqual(parsed.tocPattern, "第.章\\s.*")
    }

    func testReadsTheChapterContent() throws {
        let text = """
        第一章 起点
        第一章的正文内容。
        第二章 发展
        第二章的正文内容。
        """
        let url = try makeFile("book.txt", text)
        let book = TextBook(fileURL: url)
        let parsed = try book.chapterList(tocRules: [tocRule("章节", "第.章\\s.*")])
        let chapter = parsed.chapters[0]
        let content = try book.content(chapter: chapter, start: chapter.start ?? 0, end: chapter.end ?? 0)
        XCTAssertTrue(content.contains("第一章的正文内容"), content)
        XCTAssertFalse(content.contains("第二章"), content)
    }

    func testDetectsTheBestTocRule() throws {
        let text = """
        第一章 起点
        内容
        第二章 发展
        内容
        第三章 结局
        内容
        """
        let url = try makeFile("book.txt", text)
        let book = TextBook(fileURL: url)
        let parsed = try book.chapterList(
            tocRules: [
                tocRule("错误", "不存在的规则", serial: 1),
                tocRule("正确", "第.章\\s.*", serial: 2)
            ]
        )
        XCTAssertEqual(parsed.tocPattern, "第.章\\s.*")
        XCTAssertEqual(parsed.chapters.count, 3)
    }

    func testFallsBackToTheSyntheticChaptersWithoutARule() throws {
        let text = String(repeating: "内容内容内容。\n", count: 40)
        let url = try makeFile("book.txt", text)
        let book = TextBook(fileURL: url)
        let parsed = try book.chapterList(tocRules: [tocRule("不匹配", "永远不会匹配")])
        XCTAssertFalse(parsed.chapters.isEmpty)
        XCTAssertTrue(parsed.chapters[0].title.hasPrefix("第1章("), parsed.chapters[0].title)
    }

    func testThrowsOnAnEmptyFile() throws {
        let url = try makeBinaryFile("empty.txt", Data())
        let book = TextBook(fileURL: url)
        XCTAssertThrowsError(try book.chapterList(tocRules: [])) { error in
            XCTAssertEqual(error as? TextBook.TextBookError, .emptyFile)
        }
    }

    func testComputesTheWordCount() throws {
        let text = """
        第一章 起点
        0123456789
        第二章 发展
        0123456789
        """
        let url = try makeFile("book.txt", text)
        let book = TextBook(fileURL: url)
        let parsed = try book.chapterList(tocRules: [tocRule("章节", "第.章\\s.*")])
        XCTAssertGreaterThan(parsed.wordCount, 0)
    }

    // MARK: - Name / author

    func testAnalyzesThePlainFileName() {
        let result = LocalBook.analyzeNameAuthor(fileName: "斗破苍穹.txt")
        XCTAssertEqual(result.name, "斗破苍穹")
    }

    func testAnalyzesTheBookBracketFileName() {
        let result = LocalBook.analyzeNameAuthor(fileName: "《三体》作者：刘慈欣.txt")
        XCTAssertEqual(result.name, "三体")
        XCTAssertEqual(result.author, "刘慈欣")
    }

    func testAnalyzesTheBookBracketFileNameWithoutAuthor() {
        let result = LocalBook.analyzeNameAuthor(fileName: "《三体》.txt")
        XCTAssertEqual(result.name, "三体")
    }

    func testAnalyzesTheEnglishFileName() {
        let result = LocalBook.analyzeNameAuthor(fileName: "The Hobbit by J.R.R. Tolkien.txt")
        XCTAssertEqual(result.name, "The Hobbit")
        XCTAssertEqual(result.author, "J.R.R. Tolkien")
    }

    // MARK: - Import

    func testImportsALocalTxtFile() throws {
        let text = """
        第一章 起点
        内容
        第二章 发展
        内容
        """
        let url = try makeFile("我的书.txt", text)
        let imported = try LocalBook.importFile(
            fileURL: url,
            tocRules: [tocRule("章节", "第.章\\s.*")]
        )
        XCTAssertEqual(imported.book.name, "我的书")
        XCTAssertEqual(imported.book.originName, "我的书.txt")
        XCTAssertEqual(imported.chapters.count, 2)
        XCTAssertEqual(imported.chapters[0].index, 0)
        XCTAssertEqual(imported.chapters[1].index, 1)
        XCTAssertEqual(imported.book.totalChapterNum, 2)
    }

    func testRejectsAnUnsupportedFile() throws {
        let url = try makeFile("book.docx", "x")
        XCTAssertThrowsError(try LocalBook.importFile(fileURL: url)) { error in
            XCTAssertEqual(error as? LocalBook.LocalBookError, .unsupportedFormat("book.docx"))
        }
    }

    func testNormalizesTheChapterList() {
        var first = BookChapter()
        first.url = "a"
        first.title = ""
        var second = BookChapter()
        second.url = "a"
        second.title = "x"
        var third = BookChapter()
        third.url = "b"
        third.title = "y"

        let list = LocalBook.normalize(chapters: [first, second, third])
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].title, "无标题章节")
        XCTAssertEqual(list[0].index, 0)
        XCTAssertEqual(list[1].index, 1)
    }
}
