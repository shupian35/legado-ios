//
//  Export.swift
//  LegadoCore
//
//  Book export (upstream `service/ExportBookService.kt`): a book becomes a
//  single TXT file or a single EPUB archive.
//
//  Deliberate deviations from the Android exporter:
//  * the EPUB writer is hand-written (upstream vendors `epublib`), and the
//    default stylesheet is embedded instead of read from the APK assets;
//  * the images are supplied by a closure instead of `BookHelp.getImage`
//    (the port has no on-disk image cache yet).
//

import Foundation

// MARK: - Options

/// What to export and how — upstream `ExportBookService.ExportConfig` plus
/// the relevant `AppConfig` switches.
public struct BookExportOptions: Equatable {
    /// Prepends the in-content chapter title (upstream
    /// `AppConfig.exportNoChapterName` negated).
    public var includeChapterTitle: Bool
    /// Applies the book's replace rules (upstream `exportUseReplace`).
    public var useReplaceRule: Bool
    /// Also writes the images referenced by the text into the TXT export
    /// (upstream `exportPictureFile`).
    public var exportPictureFile: Bool
    /// Overrides the generated file name.
    public var fileName: String?
    /// The zero-based indexes of the chapters to export — upstream
    /// `AppConfig.enableCustomExport` with the chapter scope of the
    /// `CacheActivity.configExportSection` dialog. `nil` exports every
    /// chapter.
    public var chapterIndexes: Set<Int>?

    public init(
        includeChapterTitle: Bool = true,
        useReplaceRule: Bool = true,
        exportPictureFile: Bool = false,
        fileName: String? = nil,
        chapterIndexes: Set<Int>? = nil
    ) {
        self.includeChapterTitle = includeChapterTitle
        self.useReplaceRule = useReplaceRule
        self.exportPictureFile = exportPictureFile
        self.fileName = fileName
        self.chapterIndexes = chapterIndexes
    }

    /// The chapters the options select — the scope filter of the upstream.
    public func selectChapters(_ chapters: [BookChapter]) -> [BookChapter] {
        guard let chapterIndexes else { return chapters }
        return chapters.enumerated().compactMap { index, chapter in
            chapterIndexes.contains(index) ? chapter : nil
        }
    }
}

public enum BookExportError: Error, Equatable {
    case emptyBook
    case invalidArchive(String)
    /// An image referenced by the text could not be fetched.
    case missingImage(String)
}

/// One file produced by an export.
public struct ExportedFile: Equatable {
    /// The suggested file name, e.g. `书名 作者：作者.txt`.
    public let fileName: String
    public let data: Data

    public init(fileName: String, data: Data) {
        self.fileName = fileName
        self.data = data
    }
}

/// A picture that the TXT export writes next to the book.
public struct ExportedImage: Equatable {
    /// The directory below the export root.
    public let directory: String
    /// The file name inside `directory`.
    public let fileName: String
    public let data: Data

    public init(directory: String, fileName: String, data: Data) {
        self.directory = directory
        self.fileName = fileName
        self.data = data
    }
}

/// The result of a TXT export.
public struct TxtExportResult: Equatable {
    public let file: ExportedFile
    /// The sidecar images, empty unless `exportPictureFile` is set.
    public let images: [ExportedImage]
}

// MARK: - Exporter

public enum BookExporter {

    /// The name a book is exported as — upstream `Book.getExportFileName`.
    public static func fileName(book: Book, suffix: String) -> String {
        "\(book.name) 作者：\(realAuthor(of: book)).\(suffix)"
    }

    /// Upstream `Book.getRealAuthor()`.
    public static func realAuthor(of book: Book) -> String {
        TextFormat.formatBookAuthor(book.author)
    }

    /// Upstream `Book.getDisplayIntro()`.
    public static func displayIntro(of book: Book) -> String {
        if let custom = book.customIntro, !custom.isEmpty {
            return custom
        }
        return book.intro ?? ""
    }

    // MARK: TXT

    /// Exports the whole book as one TXT file.
    ///
    /// - Parameters:
    ///   - book: the book row.
    ///   - chapters: the chapter list, in reading order.
    ///   - content: fetches the raw content of a chapter.
    ///   - titleRules: the replace rules that apply to chapter titles.
    ///   - contentRules: the replace rules that apply to the content.
    ///   - options: what to include.
    public static func exportTxt(
        book: Book,
        chapters: [BookChapter],
        titleRules: [ReplaceRule] = [],
        contentRules: [ReplaceRule] = [],
        options: BookExportOptions = BookExportOptions(),
        imageProvider: ((String) -> Data?)? = nil,
        content: (BookChapter) async throws -> String?
    ) async throws -> TxtExportResult {
        let chapters = options.selectChapters(chapters)
        guard !chapters.isEmpty else { throw BookExportError.emptyBook }
        let provider = imageProvider ?? BookExporter.imageProvider

        let useReplace = options.useReplaceRule && book.useReplaceRule
        var text = bookHeader(book)
        var images: [ExportedImage] = []
        let author = realAuthor(of: book)

        for chapter in chapters {
            let raw = try await content(chapter)
            let source = raw ?? (chapter.isVolume ? "" : "null")
            let processed = try ReplaceRuleEngine.processContent(
                book: book,
                chapter: chapter,
                content: source,
                includeTitle: options.includeChapterTitle,
                useReplace: useReplace,
                chineseConvert: false,
                reSegment: false,
                titleRules: titleRules,
                contentRules: contentRules
            )
            text += "\n\n" + processed.contents.joined(separator: "\n")

            if options.exportPictureFile, let raw {
                let directory = "\(book.name)_\(author)/images/\(chapter.title)"
                let found = imageSources(in: raw, chapterURL: chapter.url)
                for (index, source) in found {
                    // `getImage` is not part of the core; the caller supplies
                    // the bytes via the `imageProvider` hook if it wants
                    // sidecar files. Without it the reference is skipped.
                    guard let data = provider?(source) else { continue }
                    images.append(
                        ExportedImage(
                            directory: directory,
                            fileName: "\(index)-\(ScriptDigest.md5Encode16(source)).jpg",
                            data: data
                        )
                    )
                }
            }
        }

        return TxtExportResult(
            file: ExportedFile(
                fileName: options.fileName ?? fileName(book: book, suffix: "txt"),
                data: Data(text.utf8)
            ),
            images: images
        )
    }

    /// An optional hook used by the TXT export to write the pictures of a
    /// book — the port of `BookHelp.getImage`. The `App` layer plugs the
    /// on-disk image cache in here.
    public static var imageProvider: ((String) -> Data?)?

    /// An optional hook used by the EPUB export to embed the cover.
    public static var coverProvider: ((Book) -> Data?)?

    // MARK: EPUB

    /// Exports the whole book as one EPUB 2.0 archive.
    public static func exportEpub(
        book: Book,
        chapters: [BookChapter],
        titleRules: [ReplaceRule] = [],
        contentRules: [ReplaceRule] = [],
        options: BookExportOptions = BookExportOptions(),
        imageProvider: ((String) -> Data?)? = nil,
        coverProvider: ((Book) -> Data?)? = nil,
        content: (BookChapter) async throws -> String?
    ) async throws -> ExportedFile {
        let chapters = options.selectChapters(chapters)
        guard !chapters.isEmpty else { throw BookExportError.emptyBook }

        let images = imageProvider ?? BookExporter.imageProvider
        let cover = coverProvider ?? BookExporter.coverProvider
        let useReplace = options.useReplaceRule && book.useReplaceRule
        let epub = EpubBuilder(book: book)
        epub.addStylesheet()
        epub.addSection(
            title: "封面",
            href: "Text/cover.html",
            html: EpubTemplates.publicPage(
                name: book.name,
                author: realAuthor(of: book),
                intro: displayIntro(of: book),
                kind: book.kind,
                wordCount: book.wordCount,
                model: EpubTemplates.cover,
                href: "Text/cover.html"
            )
        )
        epub.addSection(
            title: "内容简介",
            href: "Text/intro.html",
            html: EpubTemplates.publicPage(
                name: book.name,
                author: realAuthor(of: book),
                intro: displayIntro(of: book),
                kind: book.kind,
                wordCount: book.wordCount,
                model: EpubTemplates.intro,
                href: "Text/intro.html"
            )
        )
        if let coverData = cover?(book), !coverData.isEmpty {
            epub.setCover(data: coverData, href: "Images/cover.jpg")
        }

        for (index, chapter) in chapters.enumerated() {
            let raw = try await content(chapter)
            let source = raw ?? (chapter.isVolume ? "" : "null")
            let fixed = EpubImages.fix(
                content: source,
                chapterURL: chapter.url,
                provider: images
            )
            let processed = try ReplaceRuleEngine.processContent(
                book: book,
                chapter: chapter,
                content: fixed.text,
                includeTitle: false,
                useReplace: useReplace,
                chineseConvert: false,
                reSegment: false,
                titleRules: titleRules,
                contentRules: contentRules
            )
            let title = try ReplaceRuleEngine.displayTitle(
                chapter,
                replaceRules: titleRules,
                useReplace: useReplace,
                chineseConvert: false
            )
            epub.addChapter(
                title: title.replacingOccurrences(of: "🔒", with: ""),
                content: processed.contents.joined(separator: "\n"),
                isVolume: chapter.isVolume,
                href: "Text/chapter_\(index).html",
                images: fixed.images
            )
        }

        let data = try epub.build()
        return ExportedFile(
            fileName: options.fileName ?? fileName(book: book, suffix: "epub"),
            data: data
        )
    }

    // MARK: - The split EPUB export

    /// Exports the book as several EPUB files — upstream
    /// `ExportBookService.CustomExporter.export`.
    ///
    /// The chapters selected by `options.chapterIndexes` are split into
    /// groups of `splitSize` chapters; every group becomes one EPUB file.
    /// The file name of a part is built from `nameTemplate` with the
    /// `epubIndex` binding (upstream `Book.getExportFileName(suffix,
    /// epubIndex, jsStr)`), the default is
    /// `书名 作者：作者 [1].epub`.
    public static func exportEpubParts(
        book: Book,
        chapters: [BookChapter],
        titleRules: [ReplaceRule] = [],
        contentRules: [ReplaceRule] = [],
        options: BookExportOptions = BookExportOptions(),
        splitSize: Int = 1,
        nameTemplate: String? = nil,
        engine: RuleScriptEngine? = nil,
        imageProvider: ((String) -> Data?)? = nil,
        coverProvider: ((Book) -> Data?)? = nil,
        content: (BookChapter) async throws -> String?
    ) async throws -> [ExportedFile] {
        let selected = options.selectChapters(chapters)
        guard !selected.isEmpty else { throw BookExportError.emptyBook }
        let groups = ExportScope.split(
            selected.enumerated().map { $0.offset },
            size: splitSize
        )
        var files: [ExportedFile] = []
        for (index, group) in groups.enumerated() {
            var partOptions = options
            partOptions.chapterIndexes = Set(group)
            partOptions.fileName = ExportFileName.indexedName(
                book: book,
                suffix: "epub",
                index: index + 1,
                template: nameTemplate,
                engine: engine
            )
            let file = try await exportEpub(
                book: book,
                chapters: selected,
                titleRules: titleRules,
                contentRules: contentRules,
                options: partOptions,
                imageProvider: imageProvider,
                coverProvider: coverProvider,
                content: content
            )
            files.append(file)
        }
        return files
    }

    // MARK: - Helpers

    /// The TXT preamble — upstream `getAllContents` builds it with string
    /// resources (`author_show`, `intro_show`).
    static func bookHeader(_ book: Book) -> String {
        """
        \(book.name)
        作者：\(realAuthor(of: book))
        简介：
        \(TextFormat.format(displayIntro(of: book)))
        """
    }

    /// The absolute image URLs of a chapter, with the line index.
    static func imageSources(in content: String, chapterURL: String) -> [(Int, String)] {
        guard let expression = try? NSRegularExpression(
            pattern: RulePatterns.imgPattern
        ) else { return [] }
        var result: [(Int, String)] = []
        let lines = content.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            for match in expression.matches(in: line, options: [], range: range) {
                guard match.numberOfRanges > 1,
                      match.range(at: 1).location != NSNotFound else { continue }
                let source = nsLine.substring(with: match.range(at: 1))
                result.append(
                    (index, NetworkUtils.absoluteURL(base: chapterURL, source))
                )
            }
        }
        return result
    }

    /// Upstream `UrlUtil.getSuffix(url, "jpg")`.
    static func imageSuffix(for source: String) -> String {
        let path = source.components(separatedBy: "?").first ?? source
        let name = path.components(separatedBy: "/").last ?? path
        guard let dot = name.lastIndex(of: ".") else { return "jpg" }
        let suffix = String(name[name.index(after: dot)...])
        guard !suffix.isEmpty, suffix.count <= 4 else { return "jpg" }
        return suffix
    }
}
