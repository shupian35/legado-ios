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
        case allFilesFailed
        case archiveEmpty
    }

    /// The directory that holds the imported files — upstream
    /// `AppConfig.defaultBookTreeUri`.
    public var booksDirectory: URL

    /// The JavaScript rule of the upstream `AppConfig.bookImportFileName` — the
    /// script derives the name and the author of the book from the name of the
    /// file.
    public var fileNameRule: String?
    /// The engine that runs the rule above.
    public var scriptEngine: RuleScriptEngine?

    private let store: LegadoStore
    private let fileManager: FileManager

    public init(store: LegadoStore, booksDirectory: URL, fileManager: FileManager = .default) {
        self.store = store
        self.booksDirectory = booksDirectory
        self.fileManager = fileManager
    }

    /// The rule that derives the name and the author of a book from the name
    /// of its file.
    ///
    /// Upstream `LocalBook.analyzeNameAuthor` runs the JavaScript rule of
    /// `AppConfig.bookImportFileName` first; when the rule is missing or it
    /// assigns nothing, the four patterns are used.
    public func nameAuthorAnalyzer() -> LocalBook.NameAuthorAnalyzer? {
        guard let rule = fileNameRule?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rule.isEmpty else { return nil }
        let engine = scriptEngine
        return { fileName in
            LocalBook.analyzeNameAuthor(
                fileName: fileName,
                fileNameRule: rule,
                scriptEngine: engine
            )
        }
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
            tocRules: rules,
            nameAuthorAnalyzer: nameAuthorAnalyzer()
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
    ///
    /// The upstream's `LocalBook.deleteBook` only deletes the file when
    /// `deleteOriginal` is set (the caller decides).
    public func removeBook(_ book: Book, deleteOriginal: Bool = true) throws {
        try store.delete(bookUrl: book.bookUrl)
        guard deleteOriginal else { return }
        if let url = fileURL(for: book) {
            try? fileManager.removeItem(at: url)
        }
    }

    /// Imports several files — upstream `LocalBook.importFiles(uris)`.
    ///
    /// The upstream counts the failures and only fails when EVERY file
    /// failed; the port does the same.
    ///
    /// - Returns: the number of the imported books.
    @discardableResult
    public func importBooks(from urls: [URL]) throws -> Int {
        var imported = 0
        var failures = 0
        for url in urls {
            do {
                if isArchive(url) {
                    imported += try importArchive(from: url).count
                } else {
                    try importBook(from: url)
                    imported += 1
                }
            } catch {
                failures += 1
                AppLog.shared.put(
                    "ImportFile Error:\nFile \(url.lastPathComponent)\n\(error.localizedDescription)",
                    error: error
                )
            }
        }
        if !urls.isEmpty, failures == urls.count {
            throw ImportError.allFilesFailed
        }
        return imported
    }

    /// Imports the books of an archive — upstream `LocalBook.importArchiveFile`.
    ///
    /// The archive is decompressed into the storage of the app and every book
    /// inside it is imported; the origin of the book carries the name of the
    /// archive, so that the book can be extracted again later.
    ///
    /// - Returns: the imported books.
    @discardableResult
    public func importArchive(from url: URL) throws -> [Book] {
        let data = try Data(contentsOf: url)
        let archive = try ZipArchive(data: data)
        let archiveName = url.lastPathComponent
        var books: [Book] = []
        for entry in archive.entries {
            guard !entry.isDirectory else { continue }
            let name = (entry.name as NSString).lastPathComponent
            let ext = FileAssociation.fileExtension(of: name).lowercased()
            guard FileAssociation.bookExtensions.contains(ext),
                LocalBook.Format.detect(fileName: name) != nil else { continue }
            let payload: Data
            do {
                payload = try archive.data(for: entry)
            } catch {
                AppLog.shared.put("解压失败：\(entry.name)", error: error)
                continue
            }
            guard payload.count > 0 else { continue }
            try fileManager.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
            let destination = booksDirectory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            try payload.write(to: destination)
            let book = try importBook(from: destination)
            var stored = book
            stored.origin = "\(BookType.localTag)::\(archiveName)"
            stored.type = stored.type | BookType.archive
            try store.update(stored)
            books.append(stored)
        }
        guard !books.isEmpty else { throw ImportError.archiveEmpty }
        return books
    }

    /// Whether a file is an archive — upstream `ArchiveUtils.isArchive`.
    public func isArchive(_ url: URL) -> Bool {
        let ext = FileAssociation.fileExtension(of: url.lastPathComponent)
        return FileAssociation.archiveExtensions.contains(ext)
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
