//
//  ReaderImageTests.swift
//  LegadoCoreTests
//
//  The inline images of a chapter — the port of the upstream's
//  `AppPattern.imgPattern` handling and of `ChapterProvider.setTypeImage`.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/constant/AppPattern.kt:12
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/ChapterProvider.kt:200-463
//

import XCTest
@testable import LegadoCore

// MARK: - Helpers

/// A PNG header of the given size — the IHDR chunk at 16...24.
private func pngHeader(width: UInt32, height: UInt32) -> Data {
    var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    bytes += [0x00, 0x00, 0x00, 0x0D]
    bytes += [0x49, 0x48, 0x44, 0x52]
    bytes += [UInt8((width >> 24) & 0xFF), UInt8((width >> 16) & 0xFF),
              UInt8((width >> 8) & 0xFF), UInt8(width & 0xFF)]
    bytes += [UInt8((height >> 24) & 0xFF), UInt8((height >> 16) & 0xFF),
              UInt8((height >> 8) & 0xFF), UInt8(height & 0xFF)]
    return Data(bytes)
}

/// A GIF header of the given size (the little-endian size at 6...10).
private func gifHeader(width: UInt16, height: UInt16) -> Data {
    var bytes = Array("GIF89a".utf8)
    bytes += [UInt8(width & 0xFF), UInt8((width >> 8) & 0xFF)]
    bytes += [UInt8(height & 0xFF), UInt8((height >> 8) & 0xFF)]
    return Data(bytes)
}

/// A JPEG with a SOF0 marker — the size at the marker + 5 and + 7.
private func jpegHeader(width: UInt16, height: UInt16) -> Data {
    var bytes: [UInt8] = [0xFF, 0xD8]
    // The APP0 segment.
    bytes += [0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00]
    // The SOF0 segment.
    bytes += [0xFF, 0xC0, 0x00, 0x11, 0x08]
    bytes += [UInt8((height >> 8) & 0xFF), UInt8(height & 0xFF)]
    bytes += [UInt8((width >> 8) & 0xFF), UInt8(width & 0xFF)]
    bytes += [0x03]
    return Data(bytes)
}

// MARK: - The size detector

final class ImageSizeDetectorTests: XCTestCase {

    func testThePngSizeIsSniffedFromTheHeader() {
        let size = ImageSizeDetector.size(of: pngHeader(width: 320, height: 240))
        XCTAssertEqual(size?.width, 320)
        XCTAssertEqual(size?.height, 240)
    }

    func testTheGifSizeIsSniffedFromTheHeader() {
        let size = ImageSizeDetector.size(of: gifHeader(width: 64, height: 32))
        XCTAssertEqual(size?.width, 64)
        XCTAssertEqual(size?.height, 32)
    }

    func testTheJpegSizeIsSniffedFromTheSofMarker() {
        let size = ImageSizeDetector.size(of: jpegHeader(width: 800, height: 600))
        XCTAssertEqual(size?.width, 800)
        XCTAssertEqual(size?.height, 600)
    }

    func testAnUnknownFormatHasNoSize() {
        XCTAssertNil(ImageSizeDetector.size(of: Data([0x01, 0x02, 0x03, 0x04])))
    }

    func testTooShortDataHasNoSize() {
        XCTAssertNil(ImageSizeDetector.size(of: Data()))
    }
}

// MARK: - The splitter

final class ChapterImageSplitterTests: XCTestCase {

    func testTheContentIsSplitIntoTextAndImageSegments() {
        let segments = ChapterImageSplitter.split("abc<img src=\"https://a/b.png\">def")
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0], .text("abc"))
        XCTAssertEqual(segments[1], .image("https://a/b.png"))
        XCTAssertEqual(segments[2], .text("def"))
    }

    func testTheSrcOfTheTagIsTheGroupOfThePattern() {
        let segments = ChapterImageSplitter.split("<img src='x.jpg' width='2'>")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0], .image("x.jpg"))
    }

    func testTheSourcesAreListedInOrder() {
        let sources = ChapterImageSplitter.sources(
            in: "<img src=\"1.png\">a<img src=\"2.png\">"
        )
        XCTAssertEqual(sources, ["1.png", "2.png"])
    }

    func testAContentWithoutAnImageIsOneTextSegment() {
        let segments = ChapterImageSplitter.split("just text")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0], .text("just text"))
    }

    func testTheTextStyleReplacesTheImageWithThePlaceholder() {
        let text = ChapterImageSplitter.textEmbedded("a<img src=\"1.png\">b")
        XCTAssertEqual(text, "a▣b")
    }

    func testAnEmptyContentHasNoSegment() {
        XCTAssertTrue(ChapterImageSplitter.split("").isEmpty)
    }
}

// MARK: - The layout

final class ReaderImageLayoutTests: XCTestCase {

    private func makeChapter() -> TextChapter {
        TextChapter(
            chapter: BookChapter(url: "https://example.com/1", title: "第一章"),
            position: 0,
            title: "第一章",
            chaptersSize: 1,
            sameTitleRemoved: false,
            isVip: false,
            isPay: false
        )
    }

    private func makeLayout(width: Double = 200, height: Double = 300) -> ReaderLayout {
        var config = ReaderConfig()
        config.textSize = 20
        config.titleSize = 20
        config.paddingTop = 0
        config.paddingBottom = 0
        config.paddingLeft = 0
        config.paddingRight = 0
        config.titleTopSpacing = 0
        config.titleBottomSpacing = 0
        config.paragraphSpacing = 0
        return ReaderLayout(
            config: config,
            size: CGSizeLike(width: width, height: height),
            measurer: ApproximateTextMeasurer()
        )
    }

    private func layout(
        content: String,
        images: [String: ReaderImage] = [:],
        imageStyle: BookImageStyle = .standard
    ) -> TextChapterLayout {
        TextChapterLayout(
            chapter: makeChapter(),
            content: content,
            config: ReaderConfig(),
            layout: makeLayout(),
            measurer: ApproximateTextMeasurer(),
            images: images,
            imageStyle: imageStyle
        )
    }

    func testAnImageBecomesALineOfItsOwn() {
        let image = ReaderImage(
            src: "https://a/b.png",
            size: CGSizeLike(width: 100, height: 50),
            data: pngHeader(width: 100, height: 50)
        )
        let engine = layout(
            content: "abc<img src=\"https://a/b.png\">def",
            images: ["https://a/b.png": image]
        )
        let pages = engine.paginate()
        let lines = pages.flatMap { $0.lines }
        XCTAssertEqual(lines.filter { $0.isImage }.count, 1)
        // The image line carries the image column with its source.
        let column = lines.first { $0.isImage }?.columns.first { $0 is ImageColumn } as? ImageColumn
        XCTAssertEqual(column?.src, "https://a/b.png")
    }

    func testAnImageWithoutAResolvedSizeIsSkipped() {
        let engine = layout(content: "abc<img src=\"https://a/b.png\">def")
        let pages = engine.paginate()
        let lines = pages.flatMap { $0.lines }
        XCTAssertEqual(lines.filter { $0.isImage }.count, 0)
    }

    func testTheFullStyleFillsTheWidthOfThePage() {
        let image = ReaderImage(
            src: "a.png",
            size: CGSizeLike(width: 100, height: 50),
            data: pngHeader(width: 100, height: 50)
        )
        let engine = layout(
            content: "<img src=\"a.png\">",
            images: ["a.png": image],
            imageStyle: .full
        )
        let pages = engine.paginate()
        let line = pages.flatMap { $0.lines }.first { $0.isImage }
        let column = line?.columns.first { $0 is ImageColumn } as? ImageColumn
        XCTAssertEqual((column?.end ?? 0) - (column?.start ?? 0), 200)
        XCTAssertEqual(line?.height ?? 0, 100)
    }

    func testTheTextStyleLaysTheImageOutAsText() {
        let image = ReaderImage(
            src: "a.png",
            size: CGSizeLike(width: 100, height: 50),
            data: pngHeader(width: 100, height: 50)
        )
        let engine = layout(
            content: "abc<img src=\"a.png\">def",
            images: ["a.png": image],
            imageStyle: .text
        )
        let pages = engine.paginate()
        let lines = pages.flatMap { $0.lines }
        XCTAssertEqual(lines.filter { $0.isImage }.count, 0)
        XCTAssertTrue(pages.flatMap { $0.lines }.map(\.text).joined().contains("▣"))
    }

    func testThePageTextCountsAnImageAsOneCharacter() {
        // Upstream `ChapterProvider.kt:459` appends a space for an image so
        // that the chapter position and the page text stay in sync.
        let image = ReaderImage(
            src: "a.png",
            size: CGSizeLike(width: 100, height: 50),
            data: pngHeader(width: 100, height: 50)
        )
        let engine = layout(
            content: "abc<img src=\"a.png\">",
            images: ["a.png": image]
        )
        let pages = engine.paginate()
        XCTAssertTrue(pages.first?.text.contains(" ") ?? false)
    }
}

// MARK: - The image style of the book

final class ReaderImageStyleTests: XCTestCase {

    func testTheDefaultStyleIsUsedWhenTheBookHasNoStyle() {
        var book = Book(bookUrl: "https://a/1", name: "书", author: "作者")
        book.readConfigBox = BookReadConfig()
        XCTAssertEqual(ReadBook.imageStyle(of: book), .standard)
    }

    func testTheStyleOfTheReadConfigurationIsUsed() {
        var book = Book(bookUrl: "https://a/1", name: "书", author: "作者")
        var config = BookReadConfig()
        config.imageStyle = BookImageStyle.full.rawValue
        book.readConfigBox = config
        XCTAssertEqual(ReadBook.imageStyle(of: book), .full)
    }

    func testAnUnknownStyleFallsBackToTheDefault() {
        var book = Book(bookUrl: "https://a/1", name: "书", author: "作者")
        var config = BookReadConfig()
        config.imageStyle = "NONSENSE"
        book.readConfigBox = config
        XCTAssertEqual(ReadBook.imageStyle(of: book), .standard)
    }
}
