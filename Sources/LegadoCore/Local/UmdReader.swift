//
//  UmdReader.swift
//  LegadoCore
//
//  A reader for the UMD ebook format.
//
//  Upstream reference (the vendored `me.ag2s:umdlib` fork):
//    * modules/book/src/main/java/me/ag2s/umdlib/umd/UmdReader.java
//    * modules/book/src/main/java/me/ag2s/umdlib/domain/UmdBook.java
//    * modules/book/src/main/java/me/ag2s/umdlib/domain/UmdChapters.java
//    * modules/book/src/main/java/me/ag2s/umdlib/domain/UmdHeader.java
//    * modules/book/src/main/java/me/ag2s/umdlib/tool/StreamReader.java
//    * modules/book/src/main/java/me/ag2s/umdlib/tool/UmdUtils.java
//
//  The format is a sequence of '#'-tagged sections; every section may be
//  followed by '$'-tagged additional sections that carry the payload.
//

import Foundation
import CZlib

public enum UmdError: Error, Equatable {
    case wrongHeader
    case truncated
    case inflateFailed
}

/// The metadata of a UMD book — upstream `UmdHeader`.
public struct UmdHeader: Equatable {
    public var umdType: UInt8 = 0
    public var title: String = ""
    public var author: String = ""
    public var year: String = ""
    public var month: String = ""
    public var day: String = ""
    public var bookType: String = ""
    public var bookMan: String = ""
    public var shopKeeper: String = ""
}

/// The chapters of a UMD book — upstream `UmdChapters`.
///
/// The contents are stored zlib-compressed and split into chunks; the
/// `contentLengths` are the offsets of the individual chapters inside the
/// decompressed stream.
public final class UmdChapters {
    public private(set) var titles: [Data] = []
    public private(set) var contentLengths: [Int] = []
    public private(set) var contents = Data()
    public var totalContentLen: Int = 0

    public func addTitle(_ title: Data) {
        titles.append(title)
    }

    public func addContentLength(_ length: Int) {
        contentLengths.append(length)
    }

    /// Append decompressed content — upstream `UmdChapters.contents.write(...)`.
    public func appendContents(_ data: Data) {
        contents.append(data)
    }

    /// The title of a chapter — upstream `getTitle(index)`.
    public func title(at index: Int) -> String {
        guard index < titles.count else { return "" }
        return UmdReader.unicodeString(titles[index])
    }

    /// The raw content of a chapter — upstream `getContent(index)`.
    public func content(at index: Int) -> Data {
        guard index < contentLengths.count else { return Data() }
        let start = contentLengths[index]
        let end = index + 1 < contentLengths.count ? contentLengths[index + 1] : totalContentLen
        guard end > start, start >= 0, end <= contents.count else { return Data() }
        return contents.subdata(in: start..<end)
    }

    /// The text of a chapter — upstream `getContentString(index)`.
    ///
    /// UMD uses U+2029 (PARAGRAPH SEPARATOR) as the line break.
    public func contentString(at index: Int) -> String {
        UmdReader.unicodeString(content(at: index))
            .replacingOccurrences(of: "\u{2029}", with: "\n")
    }
}

/// A parsed UMD book — upstream `UmdBook`.
public final class UmdBook {
    public let header: UmdHeader
    public let chapters: UmdChapters
    public let coverData: Data?
    /// The number of chapters — upstream `UmdBook.num`.
    public let num: Int

    init(header: UmdHeader, chapters: UmdChapters, coverData: Data?, num: Int) {
        self.header = header
        self.chapters = chapters
        self.coverData = coverData
        self.num = num
    }
}

/// Reads a UMD book — upstream `me.ag2s.umdlib.umd.UmdReader`.
public enum UmdReader {

    /// The magic number of a UMD file.
    static let magic: UInt32 = 0xde9a_9b89

    /// Parse a UMD file.
    public static func read(_ data: Data) throws -> UmdBook {
        var reader = UmdStreamReader(data)
        // The magic is read as a signed 32 bit value, so compare it with the
        // same representation.
        let magicValue = try reader.readIntLe()
        guard UInt32(truncatingIfNeeded: magicValue) == magic else { throw UmdError.wrongHeader }

        var header = UmdHeader()
        let chapters = UmdChapters()
        var coverData: Data?
        var num = 0
        var additionalCheckNumber = 0

        var previousSectionType = -1
        var ch = reader.readByteOrZero()
        while ch == 35 {
            var sectionType = Int(try reader.readShortLe())
            _ = try reader.readByte()      // the section flag
            let length = Int(try reader.readUint8()) - 5

            try readSection(
                sectionType, length, &reader, &header, chapters,
                &additionalCheckNumber, &num, &coverData
            )

            // Sections 241 (licence) and 10 (content id) inherit the type of
            // the previous section — upstream does the same.
            if sectionType == 241 || sectionType == 10 {
                sectionType = previousSectionType
            }

            ch = reader.readByteOrZero()
            while ch == 36 {
                let check = try reader.readIntLe()
                let additionalLength = try reader.readIntLe() - 9
                try readAdditionalSection(
                    sectionType, check, additionalLength, &reader,
                    chapters, &additionalCheckNumber, &num, &coverData
                )
                ch = reader.readByteOrZero()
            }
            previousSectionType = sectionType
        }

        return UmdBook(header: header, chapters: chapters, coverData: coverData, num: num)
    }

    // MARK: - Sections

    private static func readSection(
        _ sectionType: Int,
        _ length: Int,
        _ reader: inout UmdStreamReader,
        _ header: inout UmdHeader,
        _ chapters: UmdChapters,
        _ additionalCheckNumber: inout Int,
        _ num: inout Int,
        _ coverData: inout Data?
    ) throws {
        switch sectionType {
        case 1:                                   // the file version
            header.umdType = try reader.readByte()
            _ = try reader.readBytes(2)            // random
        case 2:                                   // the title
            header.title = unicodeString(try reader.readBytes(length))
        case 3:                                   // the author
            header.author = unicodeString(try reader.readBytes(length))
        case 4:
            header.year = unicodeString(try reader.readBytes(length))
        case 5:
            header.month = unicodeString(try reader.readBytes(length))
        case 6:
            header.day = unicodeString(try reader.readBytes(length))
        case 7:                                   // the book type
            header.bookType = unicodeString(try reader.readBytes(length))
        case 8:                                   // the publisher
            header.bookMan = unicodeString(try reader.readBytes(length))
        case 9:                                   // the retailer
            header.shopKeeper = unicodeString(try reader.readBytes(length))
        case 10:                                  // the content id
            break
        case 11:                                  // the total content length
            chapters.totalContentLen = try reader.readIntLe()
        case 12:                                  // the end of the file
            _ = try reader.readIntLe()
        case 13:
            break
        case 14:
            _ = try reader.readByte()
        case 15:
            _ = try reader.readBytes(length)
        case 129, 131:                            // the text, the chapter offsets
            additionalCheckNumber = try reader.readIntLe()
        case 132:                                 // the chapter titles, the text
            additionalCheckNumber = try reader.readIntLe()
        case 130:                                 // the cover
            _ = try reader.readByte()
            additionalCheckNumber = try reader.readIntLe()
        case 135:                                 // the page offsets
            _ = try reader.readUint8()            // the font size
            _ = try reader.readUint8()            // the screen width
            _ = try reader.readBytes(4)           // the block random
        case 240:                                 // the CDS key
            break
        case 241:                                 // the licence key
            _ = try reader.readBytes(16)
        default:
            if length > 0 {
                _ = try reader.readBytes(length)
            }
        }
    }

    private static func readAdditionalSection(
        _ sectionType: Int,
        _ check: Int,
        _ length: Int,
        _ reader: inout UmdStreamReader,
        _ chapters: UmdChapters,
        _ additionalCheckNumber: inout Int,
        _ num: inout Int,
        _ coverData: inout Data?
    ) throws {
        switch sectionType {
        case 14, 15:
            break
        case 129:
            _ = try reader.readBytes(length)
        case 130:
            coverData = try reader.readBytes(length)
        case 131:
            // The chapter offsets — one little-endian int per chapter.
            num = length / 4
            for _ in 0..<(length / 4) {
                chapters.addContentLength(try reader.readIntLe())
            }
        case 132:
            if check != additionalCheckNumber {
                // The compressed text.
                let compressed = try reader.readBytes(length)
                guard let plain = UmdReader.inflate(compressed) else { throw UmdError.inflateFailed }
                chapters.appendContents(plain)
            } else {
                // The chapter titles.
                for _ in 0..<num {
                    let titleLength = Int(try reader.readUint8())
                    chapters.addTitle(try reader.readBytes(titleLength))
                }
            }
        default:
            break
        }
    }

    // MARK: - Helpers

    /// Decode UTF-16LE bytes — upstream `UmdUtils.unicodeBytesToString`.
    public static func unicodeString(_ bytes: Data) -> String {
        guard !bytes.isEmpty else { return "" }
        // UTF-16LE needs an even number of bytes; upstream's decoder silently
        // drops a trailing odd byte.
        var data = bytes
        if data.count % 2 == 1 {
            data.removeLast()
        }
        return String(data: data, encoding: .utf16LittleEndian) ?? ""
    }

    /// Inflate a zlib stream — upstream `UmdUtils.decompress`.
    ///
    /// The output size is not known in advance, so the buffer grows until
    /// zlib stops reporting `Z_BUF_ERROR`.
    static func inflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        var capacity = max(data.count * 4, 4096)
        for _ in 0..<10 {
            var output = Data(count: capacity)
            var outputLength = 0
            let status: Int32 = data.withUnsafeBytes { source -> Int32 in
                output.withUnsafeMutableBytes { destination -> Int32 in
                    CZlib.cz_uncompress_zlib(
                        source.bindMemory(to: UInt8.self).baseAddress,
                        data.count,
                        destination.bindMemory(to: UInt8.self).baseAddress,
                        capacity,
                        &outputLength
                    )
                }
            }
            if status == 0 {
                output.count = outputLength
                return output
            }
            if status == -5 {                 // Z_BUF_ERROR — the buffer was too small
                capacity *= 2
                continue
            }
            return nil
        }
        return nil
    }
}

/// A little-endian byte reader — upstream `me.ag2s.umdlib.tool.StreamReader`.
struct UmdStreamReader {
    private let bytes: [UInt8]
    private var offset = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    private mutating func require(_ count: Int) throws {
        if offset + count > bytes.count { throw UmdError.truncated }
    }

    mutating func readByte() throws -> UInt8 {
        try require(1)
        defer { offset += 1 }
        return bytes[offset]
    }

    /// Reads a byte, returning 0 at the end of the data.
    ///
    /// The section loop uses it so that a file which ends right after the
    /// "end of file" section does not raise a truncation error.
    mutating func readByteOrZero() -> UInt8 {
        guard offset < bytes.count else { return 0 }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func readUint8() throws -> UInt16 {
        try require(1)
        defer { offset += 1 }
        return UInt16(bytes[offset])
    }

    mutating func readBytes(_ count: Int) throws -> Data {
        if count <= 0 { return Data() }
        try require(count)
        defer { offset += count }
        return Data(bytes[offset..<(offset + count)])
    }

    mutating func readShortLe() throws -> Int {
        try require(2)
        defer { offset += 2 }
        let low = UInt16(bytes[offset])
        let high = UInt16(bytes[offset + 1])
        return Int(Int16(bitPattern: low | (high << 8)))
    }

    mutating func readIntLe() throws -> Int {
        try require(4)
        defer { offset += 4 }
        let b0 = UInt32(bytes[offset])
        let b1 = UInt32(bytes[offset + 1])
        let b2 = UInt32(bytes[offset + 2])
        let b3 = UInt32(bytes[offset + 3])
        return Int(Int32(bitPattern: b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)))
    }
}
