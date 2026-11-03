import XCTest

@testable import LegadoCore

final class ExportTests: XCTestCase {

    // MARK: - Fixtures

    private func makeBook(
        name: String = "测试书",
        author: String = "作者甲",
        intro: String? = "这是简介"
    ) -> Book {
        var book = Book(
            bookUrl: "https://example.com/book",
            name: name,
            author: author,
            intro: intro
        )
        book.useReplaceRule = false
        return book
    }

    private func makeChapter(
        index: Int,
        title: String,
        isVolume: Bool = false
    ) -> BookChapter {
        BookChapter(
            url: "https://example.com/chapter/\(index)",
            title: title,
            isVolume: isVolume,
            bookUrl: "https://example.com/book",
            index: Int64(index)
        )
    }

    private func makeChapters() -> [BookChapter] {
        [
            makeChapter(index: 0, title: "第一章 开端"),
            makeChapter(index: 1, title: "第二章 发展")
        ]
    }

    /// Returns the content of a chapter by index.
    private func contents(_ map: [Int: String]) -> (BookChapter) async throws -> String? {
        { chapter in map[Int(chapter.index)] }
    }

    // MARK: - TXT

    func testTxtExportHeaderAndChapters() async throws {
        let result = try await BookExporter.exportTxt(
            book: makeBook(),
            chapters: makeChapters(),
            content: contents([0: "内容一", 1: "内容二"])
        )

        let text = String(decoding: result.file.data, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("测试书\n作者：作者甲\n简介：\n这是简介"))
        XCTAssertTrue(text.contains("第一章 开端"))
        XCTAssertTrue(text.contains("内容一"))
        XCTAssertTrue(text.contains("内容二"))
        XCTAssertTrue(result.images.isEmpty)
        XCTAssertEqual(result.file.fileName, "测试书 作者：作者甲.txt")
    }

    func testTxtExportOmitsTitleWhenAsked() async throws {
        let options = BookExportOptions(includeChapterTitle: false)
        let result = try await BookExporter.exportTxt(
            book: makeBook(),
            chapters: makeChapters(),
            options: options,
            content: contents([0: "内容一", 1: "内容二"])
        )

        let text = String(decoding: result.file.data, as: UTF8.self)
        XCTAssertFalse(text.contains("第一章 开端"))
        XCTAssertTrue(text.contains("内容一"))
    }

    func testTxtExportVolumeChapterWithNoContent() async throws {
        let chapters = [makeChapter(index: 0, title: "第一卷", isVolume: true)]
        let result = try await BookExporter.exportTxt(
            book: makeBook(),
            chapters: chapters,
            content: contents([:])
        )

        let text = String(decoding: result.file.data, as: UTF8.self)
        // A volume chapter contributes its title only, never the "null" stub.
        XCTAssertTrue(text.contains("第一卷"))
        XCTAssertFalse(text.contains("null"))
    }

    func testTxtExportEmptyBookThrows() async {
        do {
            _ = try await BookExporter.exportTxt(
                book: makeBook(),
                chapters: [],
                content: contents([:])
            )
            XCTFail("expected an error")
        } catch {
            XCTAssertEqual(error as? BookExportError, .emptyBook)
        }
    }

    func testTxtExportFileNameOverride() async throws {
        let options = BookExportOptions(fileName: "custom.txt")
        let result = try await BookExporter.exportTxt(
            book: makeBook(),
            chapters: makeChapters(),
            options: options,
            content: contents([0: "a", 1: "b"])
        )
        XCTAssertEqual(result.file.fileName, "custom.txt")
    }

    // MARK: - EPUB

    func testEpubArchiveStructure() async throws {
        let file = try await BookExporter.exportEpub(
            book: makeBook(),
            chapters: makeChapters(),
            content: contents([0: "第一段\n第二段", 1: "第二章内容"])
        )

        let archive = try ZipArchive(data: file.data)
        XCTAssertTrue(archive.contains("mimetype"))
        XCTAssertTrue(archive.contains("META-INF/container.xml"))
        XCTAssertTrue(archive.contains("OEBPS/content.opf"))
        XCTAssertTrue(archive.contains("OEBPS/toc.ncx"))
        XCTAssertTrue(archive.contains("OEBPS/Text/cover.html"))
        XCTAssertTrue(archive.contains("OEBPS/Text/intro.html"))
        XCTAssertTrue(archive.contains("OEBPS/Text/chapter_0.html"))
        XCTAssertTrue(archive.contains("OEBPS/Text/chapter_1.html"))

        let mimetype = try archive.data(for: XCTUnwrap(archive.entry(named: "mimetype")))
        XCTAssertEqual(String(decoding: mimetype, as: UTF8.self), "application/epub+zip")
    }

    func testEpubChapterUsesParagraphs() async throws {
        let file = try await BookExporter.exportEpub(
            book: makeBook(),
            chapters: [makeChapter(index: 0, title: "第一章")],
            content: contents([0: "第一段\n第二段"])
        )

        let archive = try ZipArchive(data: file.data)
        let page = try archive.data(for: XCTUnwrap(archive.entry(named: "OEBPS/Text/chapter_0.html")))
        let html = String(decoding: page, as: UTF8.self)

        XCTAssertTrue(html.contains("<p>第一段</p>"))
        XCTAssertTrue(html.contains("<p>第二段</p>"))
        XCTAssertTrue(html.contains("第一章"))
    }

    func testEpubImageOnlyLineBecomesDuokanBlock() {
        let html = EpubTemplates.formatHtml("<img src=\"a.jpg\"/>")
        XCTAssertTrue(html.contains("duokan-image-single"))
        XCTAssertTrue(html.contains("picture-80"))
        XCTAssertFalse(html.contains("<p>"))
    }

    func testEpubOPFListsChapters() async throws {
        let file = try await BookExporter.exportEpub(
            book: makeBook(),
            chapters: makeChapters(),
            content: contents([0: "a", 1: "b"])
        )

        let archive = try ZipArchive(data: file.data)
        let opf = try archive.data(for: XCTUnwrap(archive.entry(named: "OEBPS/content.opf")))
        let xml = String(decoding: opf, as: UTF8.self)

        XCTAssertTrue(xml.contains("<dc:title>测试书</dc:title>"))
        XCTAssertTrue(xml.contains("作者甲"))
        XCTAssertTrue(xml.contains("Text/chapter_0.html"))
        XCTAssertTrue(xml.contains("Text/chapter_1.html"))
        XCTAssertTrue(xml.contains("<spine toc=\"ncx\">"))

        let ncx = try archive.data(for: XCTUnwrap(archive.entry(named: "OEBPS/toc.ncx")))
        let nav = String(decoding: ncx, as: UTF8.self)
        XCTAssertTrue(nav.contains("<navMap>"))
        XCTAssertTrue(nav.contains("第一章 开端"))
    }

    func testEpubVolumeNestsFollowingChapters() async throws {
        let chapters = [
            makeChapter(index: 0, title: "第一卷", isVolume: true),
            makeChapter(index: 1, title: "第一章"),
            makeChapter(index: 2, title: "第二章")
        ]
        let file = try await BookExporter.exportEpub(
            book: makeBook(),
            chapters: chapters,
            content: contents([0: nil, 1: "a", 2: "b"].compactMapValues { $0 })
        )

        let archive = try ZipArchive(data: file.data)
        let ncx = try archive.data(for: XCTUnwrap(archive.entry(named: "OEBPS/toc.ncx")))
        let nav = String(decoding: ncx, as: UTF8.self)
        // The volume opens a navPoint that the following chapters close.
        XCTAssertTrue(nav.contains("<meta name=\"dtb:depth\" content=\"2\"/>"))
    }

    // MARK: - Helpers

    func testImageSuffix() {
        XCTAssertEqual(BookExporter.imageSuffix(for: "https://a.com/x/1.png"), "png")
        XCTAssertEqual(BookExporter.imageSuffix(for: "https://a.com/x/1.jpg?v=2"), "jpg")
        XCTAssertEqual(BookExporter.imageSuffix(for: "https://a.com/x/1"), "jpg")
    }

    func testFileNameAndAuthor() {
        let book = makeBook(name: "书", author: "作 者：某人")
        XCTAssertEqual(BookExporter.realAuthor(of: book), "某人")
        XCTAssertEqual(
            BookExporter.fileName(book: book, suffix: "epub"),
            "书 作者：某人.epub"
        )
    }

    func testDisplayIntroPrefersCustom() {
        var book = makeBook(intro: "原简介")
        book.customIntro = "自定义简介"
        XCTAssertEqual(BookExporter.displayIntro(of: book), "自定义简介")
    }
}
