//
//  LocalBook.swift
//  LegadoCore
//
//  Local-book import helpers.
//
//  Upstream: app/src/main/java/io/legado/app/model/localBook/LocalBook.kt
//
//  The upstream object dispatches the chapter/content parsing to the file
//  specific parsers (EPUB / UMD / PDF / MOBI / TXT), derives the book title
//  and author from the file name and imports the file into the library.
//
//  The port covers the TXT parser plus the shared behaviour: the file name
//  analysis, the chapter list normalisation (de-duplication, index, empty
//  titles) and the content post-processing.
//

import Foundation

#if canImport(PDFKit)
import PDFKit
#endif

public enum LocalBook {

    public enum LocalBookError: Error, Equatable {
        case emptyFile
        case tocEmpty
        case unsupportedFormat(String)
        case fileNotFound(String)
    }

    /// The formats the port can read.
    public enum Format: String, CaseIterable {
        case txt
        case epub
        case umd
        case pdf
        case mobi

        /// Upstream `AppPattern.bookFileRegex` — `.*\.(txt|epub|umd|pdf|mobi|azw3|azw)`.
        public static let supportedExtensions = ["txt", "epub", "umd", "pdf", "mobi", "azw3", "azw"]

        /// Detect the format from a file name.
        public static func detect(fileName: String) -> Format? {
            let ext = (fileName as NSString).pathExtension.lowercased()
            switch ext {
            case "txt": return .txt
            case "mobi", "azw3", "azw": return .mobi
            case "epub": return .epub
            case "umd": return .umd
            case "pdf": return .pdf
            default: return nil
            }
        }
    }

    /// The upstream name/author patterns (upstream `LocalBook.nameAuthorPatterns`).
    private static let nameAuthorPatterns = [
        "(.*?)《([^《》]+)》.*?作者：(.*)",
        "(.*?)《([^《》]+)》(.*)",
        "(^)(.+) 作者：(.+)$",
        "(^)(.+) by (.+)$"
    ]

    // MARK: - Name / author

    /// Derive the book title and author from a file name.
    ///
    /// Upstream `analyzeNameAuthor(fileName)`.
    ///
    /// - Parameters:
    ///   - fileName: the name of the file.
    ///   - fileNameRule: the JavaScript rule of the upstream
    ///     `AppConfig.bookImportFileName` — the script gets the name of the
    ///     file (without the extension) as `src` and assigns `name` and
    ///     `author`; when it assigns nothing the four patterns are used.
    ///   - scriptEngine: the engine that runs the rule.
    public static func analyzeNameAuthor(
        fileName: String,
        fileNameRule: String? = nil,
        scriptEngine: RuleScriptEngine? = nil
    ) -> (name: String, author: String) {
        let tempFileName = (fileName as NSString).deletingPathExtension
        if let rule = fileNameRule?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rule.isEmpty,
            let scriptEngine {
            // The upstream appends the capture to the user's script, so that
            // the values of the variables are returned.
            let script = rule + "\nJSON.stringify({author:author,name:name})"
            do {
                let result = try scriptEngine.evaluate(script, bindings: ["src": .text(tempFileName)])
                if case let .text(json) = result,
                    let parsed = try? JSONValue.parse(json),
                    case let .object(values) = parsed {
                    let name = values["name"]?.stringValue ?? ""
                    let author = values["author"]?.stringValue ?? ""
                    if !name.isEmpty {
                        // The upstream drops an author that is the whole file
                        // name (that means the script did not set it).
                        let author = author.count == tempFileName.count ? "" : author
                        return (name, author)
                    }
                }
            } catch {
                // The upstream logs the error and falls back to the patterns.
                AppLog.shared.put("执行导入文件名规则出错", error: error)
            }
        }
        for pattern in nameAuthorPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(location: 0, length: (tempFileName as NSString).length)
            guard let match = regex.firstMatch(in: tempFileName, options: [], range: range) else { continue }
            func group(_ index: Int) -> String {
                guard index < match.numberOfRanges else { return "" }
                let r = match.range(at: index)
                if r.location == NSNotFound { return "" }
                return (tempFileName as NSString).substring(with: r)
            }
            let name = group(2)
            let author = TextFormat.formatBookAuthor(group(1) + group(3))
            return (name, author)
        }
        let name = TextFormat.formatBookName(tempFileName)
        let remainder = tempFileName.replacingOccurrences(of: name, with: "")
        let author = TextFormat.formatBookAuthor(remainder)
        return (name, author.count == tempFileName.count ? "" : author)
    }

    // MARK: - Import

    /// The result of importing a local file.
    public struct ImportedBook {
        public var book: Book
        public var chapters: [BookChapter]
        public var intro: String?
        public var wordCount: Int
        public var tocPattern: String?
    }

    /// Derives the name and the author of a book from the name of its file.
    ///
    /// The upstream uses the four patterns, unless the user configured a
    /// JavaScript rule (`AppConfig.bookImportFileName`) — then the script
    /// decides.
    public typealias NameAuthorAnalyzer = (String) -> (name: String, author: String)

    /// Import a local file: build the book, parse the table of contents.
    ///
    /// Upstream `LocalBook.getChapterList(book)` dispatches on the file type:
    /// a TXT file is split by the TOC rule, an EPUB file by its navigation
    /// tree, a UMD file by its chapter table and a PDF file page by page.
    ///
    /// - Parameters:
    ///   - fileURL: the file to import.
    ///   - bookUrl: the stable identity of the book (upstream `book.bookUrl`).
    ///   - tocRules: the enabled TXT TOC rules.
    ///   - nameAuthorAnalyzer: the rule that derives the name and the author
    ///     from the name of the file.
    public static func importFile(
        fileURL: URL,
        bookUrl: String? = nil,
        tocRules: [TxtTocRule] = [],
        splitLongChapter: Bool = false,
        nameAuthorAnalyzer: NameAuthorAnalyzer? = nil
    ) throws -> ImportedBook {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { throw LocalBookError.emptyFile }

        let fileName = fileURL.lastPathComponent
        guard let format = Format.detect(fileName: fileName) else {
            throw LocalBookError.unsupportedFormat(fileName)
        }
        switch format {
        case .txt:
            return try importTxt(
                fileURL: fileURL,
                bookUrl: bookUrl,
                tocRules: tocRules,
                splitLongChapter: splitLongChapter,
                nameAuthorAnalyzer: nameAuthorAnalyzer
            )
        case .epub:
            return try importEpub(
                fileURL: fileURL,
                bookUrl: bookUrl,
                nameAuthorAnalyzer: nameAuthorAnalyzer
            )
        case .umd:
            return try importUmd(
                fileURL: fileURL,
                bookUrl: bookUrl,
                nameAuthorAnalyzer: nameAuthorAnalyzer
            )
        case .pdf:
            return try PdfBook.importFile(
                fileURL: fileURL,
                bookUrl: bookUrl,
                nameAuthorAnalyzer: nameAuthorAnalyzer
            )
        case .mobi:
            return try MobiLocalBook.importFile(
                fileURL: fileURL,
                bookUrl: bookUrl,
                nameAuthorAnalyzer: nameAuthorAnalyzer
            )
        }
    }

    /// Imports a TXT file.
    private static func importTxt(
        fileURL: URL,
        bookUrl: String?,
        tocRules: [TxtTocRule],
        splitLongChapter: Bool,
        nameAuthorAnalyzer: NameAuthorAnalyzer?
    ) throws -> ImportedBook {
        let fileName = fileURL.lastPathComponent
        let nameAuthor = nameAuthorAnalyzer?(fileName) ?? analyzeNameAuthor(fileName: fileName)
        var book = Book()
        book.bookUrl = bookUrl ?? fileURL.absoluteString
        book.originName = fileName
        book.name = nameAuthor.name
        book.author = nameAuthor.author
        book.type = BookType.text | BookType.local
        book.origin = BookType.localTag

        let textBook = TextBook(fileURL: fileURL, splitLongChapter: splitLongChapter)
        let parsed = try textBook.chapterList(tocRules: tocRules)
        guard !parsed.chapters.isEmpty else { throw LocalBookError.tocEmpty }

        var chapters = normalize(chapters: parsed.chapters, bookUrl: book.bookUrl)
        // Upstream `TextFile.getChapterList` gives every chapter the URL
        // `md5Encode16(originName + index + title)` — without it the chapters
        // would collide in the store (the primary key is the book URL + the
        // chapter URL).
        for index in chapters.indices where chapters[index].url.isEmpty {
            chapters[index].url = ScriptDigest.md5Encode16(
                "\(fileName)\(index)\(chapters[index].title)"
            )
        }
        book.wordCount = TextFormat.wordCountFormat(parsed.wordCount)
        book.totalChapterNum = Int64(chapters.count)
        book.latestChapterTime = Int64(Date().timeIntervalSince1970 * 1000)
        book.tocUrl = parsed.tocPattern ?? ""
        book.charset = nil
        if let intro = parsed.intro {
            book.intro = intro
        }

        return ImportedBook(
            book: book,
            chapters: chapters,
            intro: parsed.intro,
            wordCount: parsed.wordCount,
            tocPattern: parsed.tocPattern
        )
    }

    /// Imports an EPUB file.
    ///
    /// Upstream `LocalBook.getChapterList` reads the navigation tree of the
    /// EPUB; the metadata comes from the OPF.
    private static func importEpub(
        fileURL: URL,
        bookUrl: String?,
        nameAuthorAnalyzer: NameAuthorAnalyzer?
    ) throws -> ImportedBook {
        let archive = try ZipArchive(fileURL: fileURL)
        let epubBook = try EpubBook(archive: archive)
        let epubFile = EpubFile(book: epubBook)
        let parsed = try epubFile.chapterList()
        guard !parsed.isEmpty else { throw LocalBookError.tocEmpty }

        let fileName = fileURL.lastPathComponent
        let nameAuthor = nameAuthorAnalyzer?(fileName) ?? analyzeNameAuthor(fileName: fileName)
        var book = Book()
        book.bookUrl = bookUrl ?? fileURL.absoluteString
        book.originName = fileName
        // The EPUB metadata wins over the file name (upstream `EpubFile`).
        book.name = epubBook.title.isEmpty ? nameAuthor.name : epubBook.title
        book.author = epubBook.authors.first ?? nameAuthor.author
        book.type = BookType.text | BookType.local
        book.origin = BookType.localTag
        book.intro = epubBook.description
        let chapters = normalize(chapters: parsed, bookUrl: book.bookUrl)
        book.totalChapterNum = Int64(chapters.count)
        book.latestChapterTime = Int64(Date().timeIntervalSince1970 * 1000)
        let wordCount = chapters.reduce(0) { total, chapter in
            total + ((try? epubFile.content(chapter: chapter))?.count ?? 0)
        }
        book.wordCount = TextFormat.wordCountFormat(wordCount)
        return ImportedBook(
            book: book,
            chapters: chapters,
            intro: epubBook.description,
            wordCount: wordCount,
            tocPattern: nil
        )
    }

    /// Imports a UMD file.
    private static func importUmd(
        fileURL: URL,
        bookUrl: String?,
        nameAuthorAnalyzer: NameAuthorAnalyzer?
    ) throws -> ImportedBook {
        let data = try Data(contentsOf: fileURL)
        let umdFile = try UmdFile(data: data)
        let identity = bookUrl ?? fileURL.absoluteString
        let parsed = umdFile.chapterList(bookUrl: identity)
        guard !parsed.isEmpty else { throw LocalBookError.tocEmpty }

        let fileName = fileURL.lastPathComponent
        let nameAuthor = nameAuthorAnalyzer?(fileName) ?? analyzeNameAuthor(fileName: fileName)
        var book = Book()
        book.bookUrl = identity
        book.originName = fileName
        book.name = umdFile.title.isEmpty ? nameAuthor.name : umdFile.title
        book.author = umdFile.author.isEmpty ? nameAuthor.author : umdFile.author
        book.type = BookType.text | BookType.local
        book.origin = BookType.localTag
        book.kind = umdFile.kind
        let chapters = normalize(chapters: parsed, bookUrl: book.bookUrl)
        book.totalChapterNum = Int64(chapters.count)
        book.latestChapterTime = Int64(Date().timeIntervalSince1970 * 1000)
        let wordCount = chapters.reduce(0) { total, chapter in
            total + umdFile.content(chapter: chapter).count
        }
        book.wordCount = TextFormat.wordCountFormat(wordCount)
        return ImportedBook(
            book: book,
            chapters: chapters,
            intro: nil,
            wordCount: wordCount,
            tocPattern: nil
        )
    }

    /// Normalise a chapter list: de-duplicate, index, name the empty titles.
    ///
    /// Upstream `LocalBook.getChapterList(book)`.
    ///
    /// The upstream stamps every chapter with the book it belongs to
    /// (`chapter.bookUrl = book.bookUrl`); the port does the same when a
    /// `bookUrl` is passed, otherwise the chapters keep their own.
    public static func normalize(chapters: [BookChapter], bookUrl: String? = nil) -> [BookChapter] {
        var seen = Set<String>()
        var list: [BookChapter] = []
        for chapter in chapters {
            let key = "\(chapter.url)\u{0}\(chapter.start ?? -1)"
            if seen.contains(key) { continue }
            seen.insert(key)
            list.append(chapter)
        }
        for index in list.indices {
            list[index].index = Int64(index)
            if list[index].title.isEmpty {
                list[index].title = "无标题章节"
            }
            if let bookUrl, !bookUrl.isEmpty {
                list[index].bookUrl = bookUrl
            }
        }
        return list
    }

    /// Reads the content of a local chapter.
    ///
    /// Upstream `LocalBook.getContent(book, chapter)` dispatches on the file
    /// type as well: the TXT reader returns the text between the chapter
    /// offsets, the EPUB reader the XHTML of the spine item, the UMD reader
    /// the chapter of the archive, the MOBI reader the HTML of the section
    /// and the PDF reader the text of the page.
    public static func content(
        fileURL: URL,
        chapter: BookChapter,
        charset: String.Encoding? = nil
    ) throws -> String {
        let fileName = fileURL.lastPathComponent
        switch Format.detect(fileName: fileName) ?? .txt {
        case .txt:
            let textBook = TextBook(fileURL: fileURL, charset: charset)
            return try textBook.content(
                chapter: chapter,
                start: chapter.start ?? 0,
                end: chapter.end ?? 0
            )
        case .epub:
            let archive = try ZipArchive(fileURL: fileURL)
            let epubBook = try EpubBook(archive: archive)
            let epubFile = EpubFile(book: epubBook)
            return (try? epubFile.content(chapter: chapter)) ?? ""
        case .umd:
            let data = try Data(contentsOf: fileURL)
            let umdFile = try UmdFile(data: data)
            return umdFile.content(chapter: chapter)
        case .mobi:
            let local = try MobiLocalBook.open(url: fileURL)
            return local.content(chapter: chapter) ?? ""
        case .pdf:
            return try pdfContent(fileURL: fileURL, chapter: chapter)
        }
    }

    /// The text of a PDF page — upstream `PdfFile.getContent`.
    ///
    /// The text extraction needs a real PDF engine; PDFKit provides it on
    /// Apple platforms, the other platforms have no renderer.
    private static func pdfContent(fileURL: URL, chapter: BookChapter) throws -> String {
        #if canImport(PDFKit)
        guard let document = PDFDocument(url: fileURL) else {
            throw LocalBookError.unsupportedFormat(fileURL.lastPathComponent)
        }
        let index = Int(chapter.url) ?? Int(chapter.index ?? 0)
        guard let page = document.page(at: index) else { return "" }
        return page.string ?? ""
        #else
        throw LocalBookError.unsupportedFormat(fileURL.lastPathComponent)
        #endif
    }
}
