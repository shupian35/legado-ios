//
//  BookProgress.swift
//  LegadoCore
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/data/entities/BookProgress.kt (21 lines)
//
//  The reading progress of one book, as exchanged with the WebDAV sync
//  (`bookProgress/<name>_<author>.json`).
//

import Foundation

public struct BookProgress: Codable, Equatable, Hashable {
    public var name: String
    public var author: String
    public var durChapterIndex: Int
    public var durChapterPos: Int
    public var durChapterTime: Int64
    public var durChapterTitle: String?

    public init(
        name: String,
        author: String,
        durChapterIndex: Int,
        durChapterPos: Int,
        durChapterTime: Int64,
        durChapterTitle: String?
    ) {
        self.name = name
        self.author = author
        self.durChapterIndex = durChapterIndex
        self.durChapterPos = durChapterPos
        self.durChapterTime = durChapterTime
        self.durChapterTitle = durChapterTitle
    }

    public init(book: Book) {
        self.init(
            name: book.name,
            author: book.author,
            durChapterIndex: Int(book.durChapterIndex),
            durChapterPos: Int(book.durChapterPos),
            durChapterTime: book.durChapterTime,
            durChapterTitle: book.durChapterTitle
        )
    }

    /// The file name upstream derives for the WebDAV progress file
    /// (`AppWebDav.bookProgressFileName`): `<name>_<author>.json`.
    public var fileName: String {
        "\(BookProgress.normalize(name))_\(BookProgress.normalize(author)).json"
    }

    /// Upstream `AppWebDav.normalizeFileName` — strips the characters a file
    /// system rejects.
    static func normalize(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return value
            .components(separatedBy: invalid)
            .joined()
            .trimmingCharacters(in: .whitespaces)
    }
}
