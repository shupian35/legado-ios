//
//  RemoteBookImport.swift
//  LegadoCore
//
//  The remote books — the port of `model/remote/RemoteBook.kt`,
//  `model/remote/RemoteBookWebDav.kt`, `ui/book/import/remote/RemoteBookViewModel.kt`
//  and `utils/AlphanumComparator.kt`.
//
//  The remote books live in the WebDAV server (the "books/" folder of the
//  default book WebDAV, or the root of a server the user picked). The user
//  browses the folders, picks the books and imports them into the library.
//

import Foundation

/// A book (or a folder) on the WebDAV server — upstream `RemoteBook`.
public struct RemoteBook: Equatable, Identifiable, Sendable {

    /// The file name (the folder name for a directory).
    public let filename: String
    /// The path below the WebDAV root.
    public let path: String
    /// The size in bytes.
    public let size: Int64
    /// The last modification, in epoch milliseconds.
    public let lastModify: Int64
    /// "folder" for a directory, the file extension otherwise.
    public let contentType: String
    /// Whether the book is already in the library.
    public var isOnBookShelf: Bool

    public var isDir: Bool { contentType == "folder" }

    public var id: String { path }

    public init(
        filename: String,
        path: String,
        size: Int64 = 0,
        lastModify: Int64 = 0,
        contentType: String = "folder",
        isOnBookShelf: Bool = false
    ) {
        self.filename = filename
        self.path = path
        self.size = size
        self.lastModify = lastModify
        self.contentType = contentType
        self.isOnBookShelf = isOnBookShelf
    }

    /// Builds a remote book from a WebDAV listing entry — upstream
    /// `RemoteBook(webDavFile)`.
    public init(file: WebDavFile, isOnBookShelf: Bool = false) {
        self.filename = file.name
        self.path = file.path
        self.size = file.size ?? 0
        self.lastModify = file.lastModified.map { Int64($0.timeIntervalSince1970 * 1000) } ?? 0
        if file.isDirectory {
            self.contentType = "folder"
            self.isOnBookShelf = false
        } else {
            self.contentType = String(file.name.split(separator: ".").last ?? "")
            self.isOnBookShelf = isOnBookShelf
        }
    }
}

/// How the remote books are sorted — upstream `RemoteBookSort`.
public enum RemoteBookSort: Int, CaseIterable, Sendable {
    /// The default — the last modification time.
    case modification = 0
    /// The file name.
    case name = 1
}

/// The name comparison — the port of `utils/AlphanumComparator.kt`.
///
/// The names are compared chunk by chunk: a run of digits is compared
/// numerically (so "第2章" sorts before "第10章"), a run of anything else is
/// compared as text.
public enum AlphanumComparator {

    public static func compare(_ s1: String, _ s2: String) -> Int {
        var thisMarker = 0
        var thatMarker = 0
        let s1Length = s1.count
        let s2Length = s2.count

        while thisMarker < s1Length && thatMarker < s2Length {
            let thisChunk = chunk(s1, s1Length, thisMarker)
            thisMarker += thisChunk.count

            let thatChunk = chunk(s2, s2Length, thatMarker)
            thatMarker += thatChunk.count

            var result: Int
            if isDigit(thisChunk.first), isDigit(thatChunk.first) {
                // Both chunks are numbers — compare them by length first.
                result = thisChunk.count - thatChunk.count
                if result == 0 {
                    for (left, right) in zip(thisChunk, thatChunk) {
                        result = Int(left.unicodeScalars.first!.value) - Int(right.unicodeScalars.first!.value)
                        if result != 0 { return result }
                    }
                }
            } else {
                result = compareChunks(thisChunk, thatChunk)
            }
            if result != 0 { return result }
        }
        return s1Length - s2Length
    }

    /// The next chunk of the string — a run of digits or a run of anything
    /// else.
    private static func chunk(_ string: String, _ length: Int, _ marker: Int) -> [Character] {
        let characters = Array(string)
        var current = marker
        var result: [Character] = []
        guard current < length else { return result }
        var character = characters[current]
        result.append(character)
        current += 1
        if isDigit(character) {
            while current < length {
                character = characters[current]
                if !isDigit(character) { break }
                result.append(character)
                current += 1
            }
        } else {
            while current < length {
                character = characters[current]
                if isDigit(character) { break }
                result.append(character)
                current += 1
            }
        }
        return result
    }

    private static func isDigit(_ character: Character?) -> Bool {
        guard let character, let scalar = character.unicodeScalars.first else { return false }
        return scalar.value >= 48 && scalar.value <= 57
    }

    /// Compares two text chunks — the Kotlin `String.compareTo` order (the
    /// UTF-16 code units).
    private static func compareChunks(_ lhs: [Character], _ rhs: [Character]) -> Int {
        let left = lhs.map { $0.unicodeScalars.first?.value ?? 0 }
        let right = rhs.map { $0.unicodeScalars.first?.value ?? 0 }
        for (a, b) in zip(left, right) where a != b {
            return a < b ? -1 : 1
        }
        return left.count - right.count
    }
}

/// The remote book browser — upstream `RemoteBookWebDav` +
/// `RemoteBookViewModel`.
public struct RemoteBookImporter: Sendable {

    public enum ImportError: Error, Equatable {
        /// The server is not configured.
        case notConfigured
        /// The download failed.
        case downloadFailed(String)
        /// The book could not be imported.
        case importFailed(String)
    }

    public let client: WebDavClient
    /// The folder that holds the books — "books/" for the default book WebDAV,
    /// empty for a server the user picked.
    public let rootPath: String
    /// The id of the server — it is written into the book's origin so that
    /// the book can be uploaded again later.
    public let serverID: Int64?

    public init(client: WebDavClient, rootPath: String = "", serverID: Int64? = nil) {
        self.client = client
        self.rootPath = rootPath
        self.serverID = serverID
    }

    /// The path of a folder below the root.
    public func path(_ subPath: String?) -> String {
        var path = rootPath
        if let subPath, !subPath.isEmpty {
            if !path.isEmpty && !path.hasSuffix("/") { path += "/" }
            path += subPath
        }
        return path
    }

    /// Lists the books of a folder — upstream `getRemoteBookList`.
    ///
    /// Only the directories and the files whose name matches the book or the
    /// archive pattern are returned.
    public func list(subPath: String? = nil) async throws -> [RemoteBook] {
        let files = try await client.list(path(subPath))
        return files
            .filter { entry in
                if entry.isDirectory { return true }
                let ext = FileAssociation.fileExtension(of: entry.name).lowercased()
                return FileAssociation.bookExtensions.contains(ext)
                    || FileAssociation.archiveExtensions.contains(ext)
            }
            .map { RemoteBook(file: $0) }
    }

    /// Sorts the books — upstream `RemoteBookViewModel.dataFlow`.
    ///
    /// Ascending puts the folders first, descending puts the files first.
    public static func sorted(
        _ books: [RemoteBook],
        by sort: RemoteBookSort,
        ascending: Bool
    ) -> [RemoteBook] {
        books.sorted { left, right in
            if left.isDir != right.isDir {
                return ascending ? left.isDir : !left.isDir
            }
            switch sort {
            case .name:
                let result = AlphanumComparator.compare(left.filename, right.filename)
                return ascending ? result < 0 : result > 0
            case .modification:
                if left.lastModify == right.lastModify {
                    return AlphanumComparator.compare(left.filename, right.filename) < 0
                }
                return ascending ? left.lastModify < right.lastModify : left.lastModify > right.lastModify
            }
        }
    }

    /// Downloads a book.
    public func download(_ book: RemoteBook) async throws -> Data {
        do {
            return try await client.download(book.path)
        } catch {
            throw ImportError.downloadFailed(book.filename)
        }
    }

    /// The origin of an imported book — upstream
    /// `BookType.webDavTag + CustomUrl(path).putAttribute("serverID", …)`.
    public func origin(for book: RemoteBook) -> String {
        let url = book.path
        guard let serverID else { return BookType.webDavTag + url }
        return BookType.webDavTag + url + ",{\"serverID\":\(serverID)}"
    }
}
