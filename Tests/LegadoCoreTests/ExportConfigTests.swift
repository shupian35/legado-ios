import XCTest

@testable import LegadoCore

/// The export configuration — upstream `CacheActivity.showExportTypeConfig`,
/// `CacheActivity.showCharsetConfig`, `CacheActivity.selectExportFolder`,
/// `CacheActivity.configExportSection` and
/// `ExportBookService.CustomExporter`.
final class ExportConfigTests: XCTestCase {

    // MARK: - Fixtures

    private func makeBook() -> Book {
        var book = Book(
            bookUrl: "https://example.com/book",
            name: "测试书",
            author: "作者甲"
        )
        book.useReplaceRule = false
        return book
    }

    private func makeChapters(_ count: Int) -> [BookChapter] {
        (0..<count).map { index in
            BookChapter(
                url: "https://example.com/chapter/\(index)",
                title: "第\(index + 1)章",
                bookUrl: "https://example.com/book",
                index: Int64(index)
            )
        }
    }

    private func contents(_ map: [Int: String]) -> (BookChapter) async throws -> String? {
        { chapter in map[Int(chapter.index)] }
    }

    // MARK: - The export type

    func testTheExportTypesMatchTheUpstream() {
        XCTAssertEqual(ExportType.allCases.map(\.rawValue), [0, 1])
        XCTAssertEqual(ExportType.allCases.map(\.fileExtension), ["txt", "epub"])
        XCTAssertEqual(ExportType.allCases.map(\.displayName), ["TXT", "EPUB"])
    }

    func testTheExportTypeIsFoundByItsName() {
        XCTAssertEqual(ExportType.named("txt"), .txt)
        XCTAssertEqual(ExportType.named("EPUB"), .epub)
        XCTAssertNil(ExportType.named("pdf"))
    }

    func testThePreferenceKeepsTheExportType() {
        let settings = AppSettings(store: InMemorySettingsStore())
        XCTAssertEqual(settings.exportFormat, .txt)
        settings.exportFormat = .epub
        XCTAssertEqual(settings.exportType, 1)
        XCTAssertEqual(settings.exportFormat, .epub)
    }

    // MARK: - The chapter scope

    func testTheScopeIsValidatedLikeTheUpstream() {
        XCTAssertTrue(ExportScope.isValid("1-5,8,10-18"))
        XCTAssertTrue(ExportScope.isValid("3"))
        XCTAssertFalse(ExportScope.isValid(""))
        XCTAssertFalse(ExportScope.isValid("abc"))
        XCTAssertFalse(ExportScope.isValid("1-"))
        XCTAssertFalse(ExportScope.isValid("1-5,"))
    }

    func testTheScopeIsParsedIntoTheChapterIndexes() {
        let scope = ExportScope.parse("1-5,8,10-18")
        XCTAssertEqual(scope, Set([0, 1, 2, 3, 4, 7, 9, 10, 11, 12, 13, 14, 15, 16, 17]))
    }

    func testASingleChapterIsParsed() {
        XCTAssertEqual(ExportScope.parse("3"), [2])
    }

    func testAReversedRangeIsSkipped() {
        // The upstream logs an error and continues.
        XCTAssertEqual(ExportScope.parse("5-1"), [])
    }

    func testTheScopeIsSplitIntoGroups() {
        let groups = ExportScope.split([0, 1, 2, 3, 4], size: 2)
        XCTAssertEqual(groups, [[0, 1], [2, 3], [4]])
    }

    func testASplitSizeOfOneKeepsEveryChapter() {
        let groups = ExportScope.split([0, 1, 2], size: 1)
        XCTAssertEqual(groups, [[0], [1], [2]])
    }

    // MARK: - The scope filter

    func testTheOptionsSelectTheChaptersOfTheScope() {
        let chapters = makeChapters(5)
        let options = BookExportOptions(chapterIndexes: [1, 3])
        XCTAssertEqual(options.selectChapters(chapters).map(\.title), ["第2章", "第4章"])
    }

    func testWithoutAScopeEveryChapterIsSelected() {
        let chapters = makeChapters(3)
        XCTAssertEqual(BookExportOptions().selectChapters(chapters).count, 3)
    }

    func testTheTxtExportOnlyWritesTheSelectedChapters() async throws {
        let options = BookExportOptions(chapterIndexes: [1])
        let result = try await BookExporter.exportTxt(
            book: makeBook(),
            chapters: makeChapters(3),
            options: options,
            content: contents([0: "内容一", 1: "内容二", 2: "内容三"])
        )
        let text = String(decoding: result.file.data, as: UTF8.self)
        XCTAssertTrue(text.contains("内容二"))
        XCTAssertFalse(text.contains("内容一"))
        XCTAssertFalse(text.contains("内容三"))
    }

    // MARK: - The split EPUB export

    func testTheEpubIsSplitIntoSeveralFiles() async throws {
        let options = BookExportOptions(chapterIndexes: [0, 1, 2, 3, 4])
        let files = try await BookExporter.exportEpubParts(
            book: makeBook(),
            chapters: makeChapters(5),
            options: options,
            splitSize: 2,
            content: contents([0: "内容一", 1: "内容二", 2: "内容三", 3: "内容四", 4: "内容五"])
        )
        XCTAssertEqual(files.count, 3)
        XCTAssertEqual(files[0].fileName, "测试书 作者：作者甲 [1].epub")
        XCTAssertEqual(files[2].fileName, "测试书 作者：作者甲 [3].epub")
    }

    func testEveryPartHoldsOnlyItsOwnChapters() async throws {
        let options = BookExportOptions(chapterIndexes: [0, 1, 2, 3])
        let files = try await BookExporter.exportEpubParts(
            book: makeBook(),
            chapters: makeChapters(4),
            options: options,
            splitSize: 2,
            content: contents([0: "内容一", 1: "内容二", 2: "内容三", 3: "内容四"])
        )
        XCTAssertEqual(files.count, 2)
        let first = String(decoding: files[0].data, as: UTF8.self)
        let second = String(decoding: files[1].data, as: UTF8.self)
        XCTAssertTrue(first.contains("内容一"))
        XCTAssertFalse(first.contains("内容三"))
        XCTAssertTrue(second.contains("内容三"))
    }

    func testWithoutAScopeTheWholeBookIsOneFile() async throws {
        let files = try await BookExporter.exportEpubParts(
            book: makeBook(),
            chapters: makeChapters(3),
            splitSize: 2,
            content: contents([0: "内容一", 1: "内容二", 2: "内容三"])
        )
        XCTAssertEqual(files.count, 2)
    }

    // MARK: - The export folder

    func testTheConfiguredFolderIsUsed() {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("export-folder-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let resolved = BookExportFileWriter.exportDirectory(configuredPath: directory.path)
        XCTAssertEqual(resolved.standardizedFileURL, directory.standardizedFileURL)
    }

    func testAMissingFolderFallsBackToTheDefault() {
        let resolved = BookExportFileWriter.exportDirectory(
            configuredPath: "/tmp/does-not-exist-\(UUID().uuidString)"
        )
        XCTAssertEqual(resolved.lastPathComponent, "导出")
    }

    func testAnEmptyFolderFallsBackToTheDefault() {
        let resolved = BookExportFileWriter.exportDirectory(configuredPath: "")
        XCTAssertEqual(resolved.lastPathComponent, "导出")
    }
}
