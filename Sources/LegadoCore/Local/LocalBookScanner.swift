//
//  LocalBookScanner.swift
//  LegadoCore
//
//  The scan of a folder for the local books — upstream
//  `ui/book/import/local/ImportBookViewModel.kt:134` (`scanDoc`).
//
//  The upstream walks the folder tree and collects every file whose name
//  matches the book file pattern (`AppPattern.bookFileRegex`) or the archive
//  pattern (`AppPattern.archiveFileRegex`).
//

import Foundation

/// The scan of a folder for the local books.
public enum LocalBookScanner {

    /// The result of a scan.
    public struct Result: Equatable, Sendable {
        /// The book files that were found.
        public var books: [URL]
        /// The archives that were found.
        public var archives: [URL]

        public init(books: [URL], archives: [URL]) {
            self.books = books
            self.archives = archives
        }

        /// Every file that was found.
        public var files: [URL] { books + archives }

        public var isEmpty: Bool { books.isEmpty && archives.isEmpty }
    }

    /// Scans a folder and returns the book files and the archives inside it.
    ///
    /// The tree is walked depth first; a folder that cannot be read is skipped.
    public static func scan(directory: URL, fileManager: FileManager = .default) -> Result {
        var books: [URL] = []
        var archives: [URL] = []
        var visited: Set<String> = []
        scan(directory: directory, fileManager: fileManager, books: &books, archives: &archives, visited: &visited)
        return Result(books: books, archives: archives)
    }

    private static func scan(
        directory: URL,
        fileManager: FileManager,
        books: inout [URL],
        archives: inout [URL],
        visited: inout Set<String>
    ) {
        // The path of the folder — it keeps the scan from looping on a symlink.
        let path = directory.standardizedFileURL.path
        guard !visited.contains(path) else { return }
        visited.insert(path)

        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory)
            guard exists else { continue }
            if isDirectory.boolValue {
                scan(directory: entry, fileManager: fileManager, books: &books, archives: &archives, visited: &visited)
                continue
            }
            let ext = FileAssociation.fileExtension(of: entry.lastPathComponent)
            if FileAssociation.bookExtensions.contains(ext) {
                books.append(entry)
            } else if FileAssociation.archiveExtensions.contains(ext) {
                archives.append(entry)
            }
        }
    }

    /// Whether a file is a book that the port can read.
    ///
    /// The upstream `AppPattern.bookFileRegex` accepts `mobi` and `azw3` as
    /// well, but the port cannot decode them yet — they are reported as
    /// unsupported so the user is not offered a broken import.
    public static func isSupportedBook(_ url: URL) -> Bool {
        let ext = FileAssociation.fileExtension(of: url.lastPathComponent)
        return ["txt", "epub", "umd", "pdf"].contains(ext)
    }

    /// The files of a scan that the port can import.
    public static func supportedBooks(of result: Result) -> [URL] {
        result.books.filter { isSupportedBook($0) }
    }
}
