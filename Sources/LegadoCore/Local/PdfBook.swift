//
//  PdfBook.swift
//  LegadoCore
//
//  The port of app/src/main/java/io/legado/app/model/localBook/PdfFile.kt.
//
//  Upstream a PDF is imported as an *image* book: every page is rendered to a
//  bitmap by Android's `PdfRenderer` and each page becomes one chapter whose
//  content is the image.
//
//  The port keeps the same model (one chapter per page) but splits the work:
//  the platform-independent part detects the pages of a PDF file and builds the
//  chapter list, while the renderer (PDFKit on Apple platforms) supplies the
//  page text and the page image.
//

import Foundation

// MARK: - The document abstraction

/// A PDF document the port can read.
///
/// The Apple implementation is `PdfKitDocument`
/// (`Local/PdfKitDocument.swift`); on the other platforms the document is
/// opened from the raw file and only the page count is known.
public protocol PdfDocument: AnyObject {
    /// The number of pages.
    var pageCount: Int { get }
    /// The text layer of a page, when the PDF has one.
    func text(atPage index: Int) -> String?
    /// The rendered image of a page (PNG).
    func imageData(atPage index: Int, scale: Double) -> Data?
}

/// The errors of the PDF import.
public enum PdfBookError: Error, Equatable {
    case notAPdf
    case emptyDocument
    case unsupportedPage(Int)
}

// MARK: - The raw file reader

/// Reads a PDF file without any platform PDF framework.
///
/// It only knows the number of pages, which is enough to build the chapter
/// list; the text and the images need a real renderer.
public final class RawPdfDocument: PdfDocument {

    /// The bytes of the file.
    private let data: Data
    /// The number of pages.
    public let pageCount: Int

    public init(data: Data) throws {
        guard data.starts(with: Array("%PDF-".utf8)) else {
            throw PdfBookError.notAPdf
        }
        self.data = data
        self.pageCount = RawPdfDocument.countPages(in: data)
    }

    public func text(atPage index: Int) -> String? { nil }

    public func imageData(atPage index: Int, scale: Double) -> Data? { nil }

    /// Counts the pages of a PDF file.
    ///
    /// The `/Type /Pages` node of the page tree carries the `/Count` of the
    /// whole document; when it is missing the page objects are counted
    /// individually.
    public static func countPages(in data: Data) -> Int {
        let text = String(decoding: data, as: UTF8.self)
        if let range = text.range(
            of: "/Type\\s*/Pages[^>]*?/Count\\s+(\\d+)",
            options: .regularExpression
        ) {
            let digits = text[range].split(separator: " ").last.map(String.init) ?? ""
            if let count = Int(digits) { return count }
        }
        var count = 0
        var searchRange = text.startIndex..<text.endIndex
        while let match = text.range(
            of: "/Type\\s*/Page[^s]",
            options: .regularExpression,
            range: searchRange
        ) {
            count += 1
            searchRange = match.upperBound..<text.endIndex
        }
        return count
    }
}

// MARK: - The importer

/// The PDF importer.
public enum PdfBook {

    /// The file name of a PDF chapter (upstream `PdfFile.getChapterFile`).
    public static func chapterFileName(index: Int) -> String {
        String(format: "%04d", index)
    }

    /// Builds the chapter list of a PDF: one chapter per page.
    public static func chapterList(document: PdfDocument) -> [BookChapter] {
        guard document.pageCount > 0 else { return [] }
        var chapters: [BookChapter] = []
        for index in 0..<document.pageCount {
            var chapter = BookChapter(url: chapterFileName(index: index), title: "第 \(index + 1) 页")
            chapter.index = Int64(index)
            chapters.append(chapter)
        }
        return chapters
    }

    /// Imports a PDF file.
    ///
    /// - Parameters:
    ///   - document: the opened document.
    ///   - fileURL: the file the document was opened from.
    ///   - bookUrl: the stable identity of the book.
    public static func importDocument(
        document: PdfDocument,
        fileURL: URL,
        bookUrl: String? = nil,
        nameAuthorAnalyzer: LocalBook.NameAuthorAnalyzer? = nil
    ) throws -> LocalBook.ImportedBook {
        guard document.pageCount > 0 else { throw PdfBookError.emptyDocument }
        let fileName = fileURL.lastPathComponent
        let nameAuthor = nameAuthorAnalyzer?(fileName) ?? LocalBook.analyzeNameAuthor(fileName: fileName)
        var book = Book()
        book.bookUrl = bookUrl ?? fileURL.absoluteString
        book.originName = fileName
        book.name = nameAuthor.name
        book.author = nameAuthor.author
        // Upstream marks a PDF as an image book (`BookType.image`).
        book.type = BookType.image | BookType.local
        book.origin = BookType.localTag
        let chapters = LocalBook.normalize(chapters: chapterList(document: document))
        book.totalChapterNum = Int64(chapters.count)
        book.latestChapterTime = Int64(Date().timeIntervalSince1970 * 1000)
        let text = (0..<document.pageCount).compactMap { document.text(atPage: $0) }.joined()
        book.wordCount = TextFormat.wordCountFormat(text.count)
        if !text.isEmpty { book.intro = text }
        return LocalBook.ImportedBook(
            book: book,
            chapters: chapters,
            intro: text.isEmpty ? nil : text,
            wordCount: text.count,
            tocPattern: nil
        )
    }

    /// Imports a PDF file from disk (no renderer).
    public static func importFile(
        fileURL: URL,
        bookUrl: String? = nil,
        nameAuthorAnalyzer: LocalBook.NameAuthorAnalyzer? = nil
    ) throws -> LocalBook.ImportedBook {
        let data = try Data(contentsOf: fileURL)
        let document = try RawPdfDocument(data: data)
        return try importDocument(
            document: document,
            fileURL: fileURL,
            bookUrl: bookUrl,
            nameAuthorAnalyzer: nameAuthorAnalyzer
        )
    }
}
