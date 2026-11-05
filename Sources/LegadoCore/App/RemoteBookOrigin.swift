//
//  RemoteBookOrigin.swift
//  LegadoCore
//
//  The origin of a book that lives on the WebDAV server — the port of
//  app/src/main/java/io/legado/app/help/book/BookExtensions.kt:190
//  (`fun Book.getRemoteUrl(): String?`) and of the `CustomUrl` attribute
//  block the upstream appends to the origin
//  (`BookType.webDavTag + CustomUrl(path).putAttribute("serverID", …)`).
//
//  The origin of such a book looks like
//  `webDav::books/我的书.txt,{"serverID":5}` — the path, then the option
//  block with the id of the server the book lives on.
//

import Foundation

/// The origin of a book that lives on a WebDAV server.
public enum RemoteBookOrigin {

    /// The remote address of a book — upstream `Book.getRemoteUrl()`.
    ///
    /// It is the origin without the `webDav::` prefix; a book that does not
    /// live on a server has none.
    public static func remoteURL(of book: Book) -> String? {
        guard book.origin.hasPrefix(BookType.webDavTag) else { return nil }
        let remote = String(book.origin.dropFirst(BookType.webDavTag.count))
        return remote.isEmpty ? nil : remote
    }

    /// The path of the remote file, without the option block.
    ///
    /// The upstream stores the option block in the origin too, so the path
    /// has to be cut before the comma.
    public static func remotePath(of book: Book) -> String? {
        guard let remote = remoteURL(of: book) else { return nil }
        let path = remote.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? remote
        return path.isEmpty ? nil : path
    }

    /// The id of the server the book lives on — the `serverID` attribute of
    /// the option block.
    public static func serverID(of book: Book) -> Int64? {
        guard let remote = remoteURL(of: book),
              let comma = remote.firstIndex(of: ",") else { return nil }
        let block = String(remote[remote.index(after: comma)...])
        guard let value = try? JSONValue.parse(block),
              case .object(let object) = value,
              let raw = object["serverID"] else { return nil }
        switch raw {
        case .number(let number): return Int64(number)
        case .string(let text): return Int64(text)
        default: return nil
        }
    }

    /// The name of the remote file — the last component of the path.
    public static func remoteFileName(of book: Book) -> String? {
        guard let path = remotePath(of: book) else { return nil }
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return name.isEmpty ? nil : name
    }
}
