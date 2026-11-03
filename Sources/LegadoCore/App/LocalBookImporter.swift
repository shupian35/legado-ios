//
//  LocalBookImporter.swift
//  LegadoCore
//
//  Imports the local books (TXT / EPUB / UMD / PDF) into the library.
//
//  Upstream `model/localBook/LocalBook.kt:231-262` (`importFile`) copies the
//  picked file into the app's own storage — the `bookUrl` is the URI of that
//  copy, so the book stays readable after the picker grants access once.
//  The port keeps the same shape: the file is copied into
//  `<documents>/books/`, the book and its chapters are written to the store,
//  and the file is removed again when the book is deleted.
//

import Foundation

/// Imports the local books into the library.
public final class LocalBookImporter: @unchecked Sendable {

    public enum ImportError: Error, Equatable {
        case emptyFile
        case unsupportedFormat(String)
        case copyFailed(String)
        case unknownBook
    }

    /// The directory that holds the imported files.
    public let booksDirectory: URL

    private let store: LegadoStore
    private let fileManager: FileManager

    public init(store: LegadoStore, booksDirectory: URL, fileManager: FileManager = .default) {
        self.store = store
        self.booksDirectory = booksDirectory
        self.fileManager = fileManager
    }

    /// Imports a local file.
    ///
    /// - Parameter sourceURL: the file to import (a picker URL).
    /// - Returns: the stored book.
    @discardableResult
    public func importBook(from sourceURL: URL, bookUrl: String? = nil) throws -> Book {
        let attributes = try? fileManager.attributesOfItem(atPath: sourceURL.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0 else { throw ImportError.emptyFile }

        let fileName = sourceURL.lastPathComponent
        guard LocalBook.Format.detect(fileName: fileName) != nil else {
            throw ImportError.unsupportedFormat(fileName)
        }

        try fileManager.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        let destination = booksDirectory.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            throw ImportError.copyFailed(fileName)
        }

        // The book URL is the copy inside the app storage — the upstream uses
        // the same trick so the book stays readable.
        let url = bookUrl ?? destination.absoluteString
        let rules = (try? store.enabledTxtTocRules()) ?? []
        let imported = try LocalBook.importFile(
            fileURL: destination,
            bookUrl: url,
            tocRules: rules
        )

        var book = imported.book
        book.origin = fileName
        book.originName = fileName
        book.type = book.type | BookType.local
        if book.order == 0 {
            book.order = minOrder()
        }
        book.totalChapterNum = Int64(imported.chapters.count)
        if let intro = imported.intro, !intro.isEmpty {
            book.intro = intro
        }

        // An existing book with the same URL is replaced (upstream deletes the
        // old chapters first).
        try store.deleteChapters(bookUrl: book.bookUrl)
        try store.insert(book)
        try store.insert(imported.chapters)
        return book
    }

    /// Deletes a local book and its file.
    public func removeBook(_ book: Book) throws {
        try store.delete(bookUrl: book.bookUrl)
        if let url = fileURL(for: book) {
            try? fileManager.removeItem(at: url)
        }
    }

    /// The smallest order of the shelf — upstream `BookDao.minOrder`.
    private func minOrder() -> Int64 {
        let orders = (try? store.allBooks().map { $0.order }) ?? []
        return (orders.min() ?? 0) - 1
    }

    /// The file of an imported book.
    public func fileURL(for book: Book) -> URL? {
        guard book.isLocal else { return nil }
        if let url = URL(string: book.bookUrl), url.isFileURL {
            return url
        }
        let candidate = booksDirectory.appendingPathComponent(book.originName)
        return fileManager.fileExists(atPath: candidate.path) ? candidate : nil
    }

    /// Every imported local book.
    public func localBooks() throws -> [Book] {
        try store.allBooks().filter { $0.isLocal }
    }
}
