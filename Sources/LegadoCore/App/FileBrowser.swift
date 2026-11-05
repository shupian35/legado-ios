//
//  FileBrowser.swift
//  LegadoCore
//
//  The file manager — upstream `ui/file/FileManageActivity` +
//  `ui/file/FileManageViewModel`.
//
//  The upstream browses the app's own files folder:
//
//      val rootDoc = context.getExternalFilesDir(null)?.parentFile
//
//  and lists the folders before the files, both sorted by the name:
//
//      parentFile.listFiles()?.sortedWith(compareBy({ it.isFile }, { it.name }))
//
//  A search keeps the entries whose name contains the query, and the long
//  press menu deletes the file.
//

import Foundation

/// One entry of the file manager.
public struct BrowserEntry: Equatable, Sendable, Identifiable {

    /// The name of the file or the folder.
    public let name: String
    /// The URL of the entry.
    public let url: URL
    /// Whether the entry is a folder.
    public let isDirectory: Bool
    /// The size in bytes — 0 for a folder.
    public let size: Int64
    /// The modification date.
    public let lastModify: Date?

    public var id: String { url.path }

    public init(
        name: String,
        url: URL,
        isDirectory: Bool,
        size: Int64 = 0,
        lastModify: Date? = nil
    ) {
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.size = size
        self.lastModify = lastModify
    }
}

/// The file manager's logic.
public enum FileBrowser {

    /// The name of the "go to the parent folder" entry — upstream
    /// `dirParent`.
    public static let parentEntryName = ".."

    /// Lists the content of `directory` — upstream `FileManageViewModel.upFiles`.
    ///
    /// The folders come first, then the files, both sorted by the name.
    public static func list(_ directory: URL) -> [BrowserEntry] {
        let manager = FileManager.default
        guard let names = try? manager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        let entries = names.map { url -> BrowserEntry in
            let values = try? url.resourceValues(
                forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            )
            return BrowserEntry(
                name: url.lastPathComponent,
                url: url,
                isDirectory: values?.isDirectory ?? false,
                size: Int64(values?.fileSize ?? 0),
                lastModify: values?.contentModificationDate
            )
        }
        return sorted(entries)
    }

    /// The folders before the files, both sorted by the name — upstream
    /// `compareBy({ it.isFile }, { it.name })`.
    public static func sorted(_ entries: [BrowserEntry]) -> [BrowserEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    /// The search of the file manager — upstream `updateFiles`: the entries
    /// whose name contains the query.
    public static func filtered(_ entries: [BrowserEntry], query: String) -> [BrowserEntry] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return entries }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(key) }
    }

    /// Deletes the file or the empty folder — upstream `FileManageViewModel.delFile`.
    @discardableResult
    public static func delete(_ entry: BrowserEntry) -> Bool {
        let manager = FileManager.default
        guard manager.fileExists(atPath: entry.url.path) else { return false }
        do {
            try manager.removeItem(at: entry.url)
            return true
        } catch {
            return false
        }
    }

    /// The size of a folder — the sum of the files it holds.
    public static func folderSize(_ directory: URL) -> Int64 {
        list(directory).reduce(0) { $0 + $1.size }
    }
}
