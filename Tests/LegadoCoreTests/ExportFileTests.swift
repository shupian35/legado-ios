import XCTest
@testable import LegadoCore

/// The export-to-file layer — upstream `service/ExportBookService.kt` +
/// `help/book/BookExtensions.kt`.
final class ExportFileTests: XCTestCase {

    private func makeBook(name: String = "书名", author: String = "作者") -> Book {
        Book(bookUrl: "https://example.com/book/1", name: name, author: author)
    }

    private func makeTemporaryDirectory() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("export-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - The character set

    func testTheUtf8CharsetWritesTheTextUnchanged() {
        let data = ExportCharset.utf8.encode("书名")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "书名")
    }

    func testTheAsciiCharsetReplacesWhatItCannotEncode() {
        let data = ExportCharset.ascii.encode("ab书")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "ab?")
    }

    func testTheUnicodeCharsetIsUtf16() {
        let data = ExportCharset.unicode.encode("书")
        // The big endian UTF-16 of U+4E66 is 0x4E 0x66.
        XCTAssertEqual(Array(data.prefix(2)), [0x4E, 0x66])
    }

    func testTheCharsetListMatchesTheUpstream() {
        XCTAssertEqual(
            ExportCharset.allCases.map(\.rawValue),
            ["UTF-8", "GBK", "GB2312", "GB18030", "Unicode", "UTF-16", "ASCII"]
        )
    }

    // MARK: - The writer

    func testTheWriterCreatesTheDirectoryAndTheFile() throws {
        let directory = makeTemporaryDirectory().appendingPathComponent("导出", isDirectory: true)
        let file = ExportedFile(fileName: "书名.txt", data: Data("内容".utf8))
        let written = try BookExportFileWriter.write(file: file, to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(FileManager.default.fileExists(atPath: written.url.path))
        XCTAssertEqual(written.fileName, "书名.txt")
        XCTAssertEqual(try String(decoding: Data(contentsOf: written.url), as: UTF8.self), "内容")
    }

    func testTheWriterReEncodesATxtFile() throws {
        let directory = makeTemporaryDirectory()
        let file = ExportedFile(fileName: "书名.txt", data: Data("内容".utf8))
        let written = try BookExportFileWriter.write(
            file: file,
            to: directory,
            charset: .ascii
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(try String(decoding: Data(contentsOf: written.url), as: UTF8.self), "??")
    }

    func testTheWriterLeavesAnEpubAlone() throws {
        let directory = makeTemporaryDirectory()
        let bytes = Data([0x50, 0x4B, 0x03, 0x04])
        let file = ExportedFile(fileName: "书名.epub", data: bytes)
        let written = try BookExportFileWriter.write(
            file: file,
            to: directory,
            charset: .ascii
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(try Data(contentsOf: written.url), bytes)
    }

    func testTheWriterWritesTheSidecarImages() throws {
        let directory = makeTemporaryDirectory()
        let file = ExportedFile(fileName: "书名.txt", data: Data("内容".utf8))
        let image = ExportedImage(
            directory: "书名/images/第一章",
            fileName: "0-a.jpg",
            data: Data([0xFF, 0xD8])
        )
        let written = try BookExportFileWriter.write(file: file, images: [image], to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertEqual(written.imageURLs.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: written.imageURLs[0].path))
        XCTAssertTrue(written.imageURLs[0].path.contains("第一章"))
    }

    func testTheWriterRemovesTheIllegalCharactersOfTheFileName() throws {
        let directory = makeTemporaryDirectory()
        let file = ExportedFile(fileName: "书/名:测试.txt", data: Data())
        let written = try BookExportFileWriter.write(file: file, to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertFalse(written.fileName.contains("/"))
        XCTAssertFalse(written.fileName.contains(":"))
    }

    func testTheExportDirectoryLivesInTheDocuments() {
        let directory = BookExportFileWriter.exportDirectory()
        XCTAssertEqual(directory.lastPathComponent, "导出")
    }

    // MARK: - The file name

    func testTheDefaultNameFollowsTheUpstream() {
        let name = ExportFileName.defaultName(book: makeBook(), suffix: "txt")
        XCTAssertEqual(name, "书名 作者：作者.txt")
    }

    func testTheEmptyTemplateUsesTheDefaultName() {
        let name = ExportFileName.name(
            book: makeBook(),
            suffix: "txt",
            template: "",
            engine: nil
        )
        XCTAssertEqual(name, "书名 作者：作者.txt")
    }

    #if canImport(JavaScriptCore)
    func testTheTemplateIsEvaluatedAsJavaScript() {
        let engine = JavaScriptCoreEngine(environment: ScriptEnvironment())
        let name = ExportFileName.name(
            book: makeBook(),
            suffix: "txt",
            // The template is JavaScript: the bindings are the variables
            // `name`, `author` and `epubIndex` (the `$name` of the default
            // name is Kotlin interpolation, not JavaScript).
            template: "name + '-' + author",
            engine: engine
        )
        XCTAssertEqual(name, "书名-作者.txt")
    }

    func testAFailingTemplateFallsBackToTheDefaultName() {
        let engine = JavaScriptCoreEngine(environment: ScriptEnvironment())
        let name = ExportFileName.name(
            book: makeBook(),
            suffix: "txt",
            template: "this is not javascript(",
            engine: engine
        )
        XCTAssertEqual(name, "书名 作者：作者.txt")
    }
    #endif
}
