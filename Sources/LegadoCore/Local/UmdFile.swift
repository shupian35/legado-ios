//
//  UmdFile.swift
//  LegadoCore
//
//  The Swift port of `app/src/main/java/io/legado/app/model/localBook/UmdFile.kt`.
//
//  Upstream the UMD support comes from the vendored `me.ag2s:umdlib` fork; the
//  port ships its own reader (`Local/UmdReader.swift`).
//

import Foundation

/// Reads the chapters and the content of a UMD book.
public final class UmdFile {
    private let book: UmdBook

    public init(book: UmdBook) {
        self.book = book
    }

    public convenience init(data: Data) throws {
        self.init(book: try UmdReader.read(data))
    }

    public var title: String { book.header.title }
    public var author: String { book.header.author }
    public var kind: String { book.header.bookType }
    public var coverData: Data? { book.coverData }

    /// The chapter list — upstream `UmdFile.getChapterList()`.
    ///
    /// The chapter URL is the index of the chapter, exactly like upstream.
    public func chapterList(bookUrl: String) -> [BookChapter] {
        var chapters: [BookChapter] = []
        for index in book.chapters.titles.indices {
            var chapter = BookChapter()
            chapter.title = book.chapters.title(at: index)
            chapter.index = Int64(index)
            chapter.bookUrl = bookUrl
            chapter.url = String(index)
            chapters.append(chapter)
        }
        return chapters
    }

    /// The content of a chapter — upstream `UmdFile.getContent(chapter)`.
    public func content(chapter: BookChapter) -> String {
        book.chapters.contentString(at: Int(chapter.index))
    }

    /// Fill the book metadata — upstream `UmdFile.upBookInfo()`.
    ///
    /// Upstream mutates the `Book` in place; Swift passes structs by value, so
    /// the updated book is returned.
    @discardableResult
    public func updateBookInfo(_ target: Book) -> Book {
        var target = target
        target.name = book.header.title
        target.author = book.header.author
        target.kind = book.header.bookType
        return target
    }
}
