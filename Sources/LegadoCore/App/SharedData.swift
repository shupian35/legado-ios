//
//  SharedData.swift
//  LegadoCore
//
//  The export of the library to other apps.
//
//  Upstream exposes the library through the exported `ContentProvider`
//  (`api/ReaderProvider.kt`), which other apps can query for the book
//  sources, the RSS sources, the bookshelf, the chapter list and the book
//  content, and which they can write to (a book, a source, a reading
//  progress).
//
//  iOS has no equivalent IPC surface. The port keeps the same data
//  available in two ways:
//
//  * the shared database in the App Group (`Storage/AppGroup.swift`) — an
//    extension can open the same file;
//  * a JSON export (`SharedDataExporter`) that the share sheet can hand to
//    another app, with the same fields the provider returned.
//

import Foundation

/// One book of the exported bookshelf.
public struct SharedBook: Equatable, Sendable {
    public var bookUrl: String
    public var name: String
    public var author: String
    public var origin: String
    public var originName: String
    public var group: Int64
    public var kind: String?
    public var coverUrl: String?
    public var intro: String?
    /// The chapter the reader stopped at.
    public var chapterIndex: Int64
    /// The character offset inside that chapter.
    public var chapterPos: Int
    /// The progress in `0...1`.
    public var progress: Double
    /// The time of the last update.
    public var updateTime: Int64

    public init(
        bookUrl: String,
        name: String,
        author: String,
        origin: String,
        originName: String,
        group: Int64,
        kind: String? = nil,
        coverUrl: String? = nil,
        intro: String? = nil,
        chapterIndex: Int64 = 0,
        chapterPos: Int = 0,
        progress: Double = 0,
        updateTime: Int64 = 0
    ) {
        self.bookUrl = bookUrl
        self.name = name
        self.author = author
        self.origin = origin
        self.originName = originName
        self.group = group
        self.kind = kind
        self.coverUrl = coverUrl
        self.intro = intro
        self.chapterIndex = chapterIndex
        self.chapterPos = chapterPos
        self.progress = progress
        self.updateTime = updateTime
    }
}

/// The exported library.
public struct SharedLibrary: Equatable, Sendable {
    /// The books of the bookshelf.
    public var books: [SharedBook]
    /// The book sources.
    public var sources: [BookSource]
    /// The RSS sources.
    public var rssSources: [RssSource]
    /// The time of the export.
    public var exportedAt: Int64

    public init(
        books: [SharedBook],
        sources: [BookSource],
        rssSources: [RssSource],
        exportedAt: Int64
    ) {
        self.books = books
        self.sources = sources
        self.rssSources = rssSources
        self.exportedAt = exportedAt
    }
}

/// Builds the shared export of the library.
public enum SharedDataExporter {

    /// The version of the export format.
    public static let formatVersion = 1

    /// Builds the export of the store.
    public static func export(
        store: LegadoStore,
        exportedAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) throws -> SharedLibrary {
        let books = try store.allBooks().map { book in
            let total = max(1, Int(book.totalChapterNum))
            let progress = min(1, Double(Int(book.durChapterIndex) + 1) / Double(total))
            return SharedBook(
                bookUrl: book.bookUrl,
                name: book.name,
                author: book.author,
                origin: book.origin,
                originName: book.originName,
                group: book.group,
                kind: book.kind,
                coverUrl: book.coverUrl,
                intro: book.intro,
                chapterIndex: book.durChapterIndex,
                chapterPos: Int(book.durChapterPos),
                progress: progress,
                updateTime: book.durChapterTime
            )
        }
        return SharedLibrary(
            books: books,
            sources: try store.allSources(),
            rssSources: try store.allRssSources(),
            exportedAt: exportedAt
        )
    }

    /// The JSON representation of the export.
    public static func json(_ library: SharedLibrary) -> String {
        let books = library.books.map { book -> JSONValue in
            var fields: [String: JSONValue] = [
                "bookUrl": .string(book.bookUrl),
                "name": .string(book.name),
                "author": .string(book.author),
                "origin": .string(book.origin),
                "originName": .string(book.originName),
                "group": .number(Double(book.group)),
                "chapterIndex": .number(Double(book.chapterIndex)),
                "chapterPos": .number(Double(book.chapterPos)),
                "progress": .number(book.progress),
                "updateTime": .number(Double(book.updateTime))
            ]
            if let kind = book.kind { fields["kind"] = .string(kind) }
            if let coverUrl = book.coverUrl { fields["coverUrl"] = .string(coverUrl) }
            if let intro = book.intro { fields["intro"] = .string(intro) }
            return .object(fields)
        }
        let sources = library.sources.map { BookSourceJSONBridge.encode($0) }
        let rssSources = library.rssSources.map { RssSourceJSONBridge.encode($0) }
        let root: JSONValue = .object([
            "version": .number(Double(formatVersion)),
            "exportedAt": .number(Double(library.exportedAt)),
            "books": .array(books),
            "bookSources": .array(sources),
            "rssSources": .array(rssSources)
        ])
        return root.jsonString
    }
}
