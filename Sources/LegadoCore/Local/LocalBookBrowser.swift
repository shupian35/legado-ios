//
//  LocalBookBrowser.swift
//  LegadoCore
//
//  The browser of the local books — upstream
//  `ui/book/import/local/ImportBookViewModel.kt` (the folder tree, the sort,
//  the filter) and `utils/AlphanumComparator.kt` (the name comparison).
//
//  The upstream lists the entries of the current folder, navigates into the
//  sub-folders and scans the whole tree for the books. The port keeps the
//  same shape: `list` reads one folder, `scan` walks the tree.
//

import Foundation

/// One entry of the local book browser — upstream `FileDoc`.
public struct LocalBookEntry: Identifiable, Equatable, Sendable {

    /// The file or the folder.
    public let url: URL
    /// The name of the entry.
    public let name: String
    /// Whether the entry is a folder.
    public let isDirectory: Bool
    /// The size of the file (0 for a folder).
    public let size: Int64
    /// The time the file was changed.
    public let modified: Date

    public var id: String { url.path }

    public init(url: URL, name: String, isDirectory: Bool, size: Int64, modified: Date) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.modified = modified
    }
}

/// The browser of the local books — upstream `ImportBookViewModel`.
public enum LocalBookBrowser {

    /// The sort of the list — upstream `PreferKey.localBookImportSort`:
    /// 0 = the name, 1 = the size, 2 = the time.
    public enum Sort: Int, CaseIterable, Sendable {
        case name = 0
        case size = 1
        case time = 2

        /// The title of the sort mode.
        public var displayName: String {
            switch self {
            case .name: return "名称"
            case .size: return "大小"
            case .time: return "时间"
            }
        }
    }

    /// Lists the entries of a folder — upstream `ImportBookViewModel.loadDoc`:
    /// the hidden entries are skipped, the folders are always listed, the
    /// files only when their name matches the book or the archive pattern.
    public static func list(directory: URL, fileManager: FileManager = .default) -> [LocalBookEntry] {
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [LocalBookEntry] = []
        for entry in entries {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: entry.path, isDirectory: &isDirectory)
            guard exists else { continue }
            let name = entry.lastPathComponent
            if isDirectory.boolValue {
                result.append(
                    LocalBookEntry(
                        url: entry,
                        name: name,
                        isDirectory: true,
                        size: 0,
                        modified: modifiedDate(of: entry, fileManager: fileManager)
                    )
                )
                continue
            }
            let ext = FileAssociation.fileExtension(of: name)
            guard FileAssociation.bookExtensions.contains(ext)
                    || FileAssociation.archiveExtensions.contains(ext) else { continue }
            let attributes = try? fileManager.attributesOfItem(atPath: entry.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            result.append(
                LocalBookEntry(
                    url: entry,
                    name: name,
                    isDirectory: false,
                    size: size,
                    modified: modifiedDate(of: entry, fileManager: fileManager)
                )
            )
        }
        return result
    }

    /// The modification time of a file.
    private static func modifiedDate(of url: URL, fileManager: FileManager) -> Date {
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        return (attributes?[.modificationDate] as? Date) ?? Date(timeIntervalSince1970: 0)
    }

    /// Sorts the entries — upstream `ImportBookViewModel`'s comparator: the
    /// folders come first, then the size or the time (the newest first), then
    /// the name with the alphanumeric comparator.
    public static func sort(_ entries: [LocalBookEntry], by sort: Sort) -> [LocalBookEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            switch sort {
            case .size:
                if lhs.size != rhs.size { return lhs.size > rhs.size }
            case .time:
                if lhs.modified != rhs.modified { return lhs.modified > rhs.modified }
            case .name:
                break
            }
            return alphanumericLess(lhs.name, rhs.name)
        }
    }

    /// Filters the entries by a search key — upstream `ImportBookViewModel`'s
    /// `filterKey` (the name contains the key).
    public static func filter(_ entries: [LocalBookEntry], key: String) -> [LocalBookEntry] {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return entries }
        return entries.filter { $0.name.contains(key) }
    }

    /// Compares two names the way the upstream does — upstream
    /// `utils/AlphanumComparator.kt`: the names are cut into chunks of digits
    /// and of other characters; two digit chunks are compared by their length
    /// first and then by their digits, the other chunks are compared as text.
    public static func alphanumericLess(_ lhs: String, _ rhs: String) -> Bool {
        compare(lhs, rhs) < 0
    }

    /// The comparison of two names — upstream `AlphanumComparator.compare`.
    public static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var thisMarker = 0
        var thatMarker = 0
        while thisMarker < left.count, thatMarker < right.count {
            let thisChunk = chunk(of: left, from: thisMarker)
            thisMarker += thisChunk.count
            let thatChunk = chunk(of: right, from: thatMarker)
            thatMarker += thatChunk.count

            var result = 0
            if isDigit(thisChunk[0]), isDigit(thatChunk[0]) {
                // The upstream compares the length first and then the digits.
                result = thisChunk.count - thatChunk.count
                if result == 0 {
                    for index in 0..<thisChunk.count {
                        result = Int(thisChunk[index].asciiValue ?? 0) - Int(thatChunk[index].asciiValue ?? 0)
                        if result != 0 { return result }
                    }
                }
            } else {
                result = compareText(thisChunk, thatChunk)
            }
            if result != 0 { return result }
        }
        return left.count - right.count
    }

    /// One chunk of a name — upstream `AlphanumComparator.getChunk`.
    private static func chunk(of characters: [Character], from marker: Int) -> [Character] {
        var current = marker
        var result: [Character] = []
        var character = characters[current]
        result.append(character)
        current += 1
        if isDigit(character) {
            while current < characters.count {
                character = characters[current]
                if !isDigit(character) { break }
                result.append(character)
                current += 1
            }
        } else {
            while current < characters.count {
                character = characters[current]
                if isDigit(character) { break }
                result.append(character)
                current += 1
            }
        }
        return result
    }

    /// Whether a character is a digit — upstream `AlphanumComparator.isDigit`.
    private static func isDigit(_ character: Character) -> Bool {
        character.isASCII && character.isNumber
    }

    /// The comparison of two text chunks — upstream `String.compareTo`.
    private static func compareText(_ lhs: [Character], _ rhs: [Character]) -> Int {
        let count = min(lhs.count, rhs.count)
        for index in 0..<count {
            let left = lhs[index].asciiValue ?? 0
            let right = rhs[index].asciiValue ?? 0
            if left != right { return Int(left) - Int(right) }
        }
        return lhs.count - rhs.count
    }
}
