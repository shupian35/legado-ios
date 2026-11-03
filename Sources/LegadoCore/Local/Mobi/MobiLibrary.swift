//
//  MobiLibrary.swift
//  LegadoCore
//
//  The MOBI / AZW (Kindle) reader — the port of
//  app/src/main/java/io/legado/app/lib/mobi/.
//
//  A MOBI file is a PalmDB container: the first record holds the PalmDOC and
//  the MOBI header, the following records hold the (compressed) text and the
//  INDX records hold the table of contents.
//
//  The port keeps the upstream structure: `PDBFile` (the container),
//  `MobiReader` (the headers), `MobiBook` (the shared logic), the KF6 / KF8
//  flavours and the three decompressors.
//

import Foundation

// MARK: - The byte readers

/// The big-endian byte readers — upstream
/// `lib/mobi/utils/ByteBufferExtensions.kt`.
///
/// The MOBI family stores every multi-byte number big-endian, which is what
/// `ByteBuffer.getInt()` does.
enum MobiBytes {

    static func uint8(_ data: [UInt8], _ offset: Int) -> Int {
        guard offset >= 0, offset < data.count else { return 0 }
        return Int(data[offset])
    }

    static func uint16(_ data: [UInt8], _ offset: Int) -> Int {
        guard offset >= 0, offset + 1 < data.count else { return 0 }
        return (Int(data[offset]) << 8) | Int(data[offset + 1])
    }

    /// The signed 32 bit read (`ByteBuffer.getInt()`).
    static func int32(_ data: [UInt8], _ offset: Int) -> Int {
        guard offset >= 0, offset + 3 < data.count else { return 0 }
        return (Int(data[offset]) << 24)
            | (Int(data[offset + 1]) << 16)
            | (Int(data[offset + 2]) << 8)
            | Int(data[offset + 3])
    }

    static func bytes(_ data: [UInt8], _ offset: Int, _ length: Int) -> [UInt8] {
        guard offset >= 0, length > 0, offset < data.count else { return [] }
        let end = min(data.count, offset + length)
        guard offset < end else { return [] }
        return Array(data[offset..<end])
    }

    /// The default charset read (`String(bytes)` = UTF-8 on Android).
    static func string(_ data: [UInt8], _ offset: Int, _ length: Int) -> String {
        String(decoding: bytes(data, offset, length), as: UTF8.self)
    }

    /// A fixed size string field — the PalmDB pads the name / the type / the
    /// creator with NUL bytes (the upstream keeps them; the port trims them).
    static func trimmedString(_ data: [UInt8], _ offset: Int, _ length: Int) -> String {
        var text = string(data, offset, length)
        while let last = text.last, last == "\u{0}" || last == " " {
            text.removeLast()
        }
        return text
    }

    static func string(
        _ data: [UInt8],
        _ offset: Int,
        _ length: Int,
        _ encoding: String.Encoding
    ) -> String {
        let raw = bytes(data, offset, length)
        if let text = String(data: Data(raw), encoding: encoding) { return text }
        return String(decoding: raw, as: UTF8.self)
    }

    /// Copies a byte range into a destination buffer (the Kotlin
    /// `ByteArray.copyInto` — the ranges may overlap).
    static func copy(
        _ source: [UInt8],
        into destination: inout [UInt8],
        destinationOffset: Int,
        sourceStart: Int,
        sourceEnd: Int
    ) {
        let upper = min(sourceEnd, source.count)
        guard sourceStart < upper else { return }
        let count = upper - sourceStart
        let temporary = Array(source[sourceStart..<upper])
        let start = max(0, destinationOffset)
        let end = min(destination.count, start + count)
        guard start < end else { return }
        destination.replaceSubrange(start..<end, with: temporary[0..<(end - start)])
    }
}

// MARK: - The entities

/// The PalmDOC header — upstream `entities/PalmDocHeader.kt`.
public struct PalmDocHeader {
    public let compression: Int
    public let numTextRecords: Int
    public let recordSize: Int
    public let encryption: Int
}

/// The MOBI header — upstream `entities/MobiHeader.kt`.
public struct MobiHeader {
    public let identifier: String
    public let length: Int
    public let type: Int
    public let encoding: Int
    public let uid: Int
    public let version: Int
    public let titleOffset: Int
    public let titleLength: Int
    public let localeRegion: Int
    public let localeLanguage: Int
    public let resourceStart: Int
    public let huffcdic: Int
    public let numHuffcdic: Int
    public let exthFlag: Int
    public let trailingFlags: Int
    public let indx: Int
    public let title: String
    public let language: String
}

/// The KF8 header — upstream `entities/KF8Header.kt`.
public struct KF8Header {
    public let fdst: Int
    public let numFdst: Int
    public let frag: Int
    public let skel: Int
    public let guide: Int
}

/// The EXTH records — upstream `entities/ExthRecordType.kt`.
public enum MobiExthValue {
    case text(String)
    case texts([String])
    case number(Int)

    public var text: String? {
        if case let .text(value) = self { return value }
        return nil
    }

    public var texts: [String] {
        if case let .texts(value) = self { return value }
        return []
    }

    public var number: Int? {
        if case let .number(value) = self { return value }
        return nil
    }
}

/// The metadata — upstream `entities/MobiMetadata.kt`.
public struct MobiMetadata {
    public let identifier: String
    public let title: String
    public let author: [String]
    public let publisher: String
    public let language: String
    public let published: String
    public let description: String
    public let subject: [String]
    public let rights: String
}

/// The table of contents entry — upstream `entities/TOC.kt`.
public struct MobiTOC {
    public let label: String
    public let href: String
    public let subitems: [MobiTOC]?
}

/// The NCX entry — upstream `entities/NCX.kt`.
public struct MobiNCX {
    public let index: Int
    public let offset: Int?
    public let size: Int?
    public let label: String
    public let headingLevel: Int?
    public let pos: [Int]?
    public let parent: Int?
    public let firstChild: Int?
    public let lastChild: Int?
    public var children: [MobiNCX]?

    public init(
        index: Int,
        offset: Int?,
        size: Int?,
        label: String,
        headingLevel: Int?,
        pos: [Int]?,
        parent: Int?,
        firstChild: Int?,
        lastChild: Int?,
        children: [MobiNCX]? = nil
    ) {
        self.index = index
        self.offset = offset
        self.size = size
        self.label = label
        self.headingLevel = headingLevel
        self.pos = pos
        self.parent = parent
        self.firstChild = firstChild
        self.lastChild = lastChild
        self.children = children
    }
}

/// The index tag — upstream `entities/IndexTag.kt`.
public struct MobiIndexTag {
    public let tagId: Int
    public let tagValues: [Int]

    public init(tagId: Int, tagValues: [Int]) {
        self.tagId = tagId
        self.tagValues = tagValues
    }
}

/// The index entry — upstream `entities/IndexEntry.kt`.
public struct MobiIndexEntry {
    public let label: String
    public let tags: [MobiIndexTag]
    public let tagMap: [Int: MobiIndexTag]

    public init(label: String, tags: [MobiIndexTag], tagMap: [Int: MobiIndexTag]) {
        self.label = label
        self.tags = tags
        self.tagMap = tagMap
    }
}

/// The index data — upstream `entities/IndexData.kt`.
public struct MobiIndexData {
    public let table: [MobiIndexEntry]
    public let cncx: [Int: String]

    public init(table: [MobiIndexEntry], cncx: [Int: String]) {
        self.table = table
        self.cncx = cncx
    }
}

/// The INDX header — upstream `entities/IndxHeader.kt`.
public struct MobiIndxHeader {
    public let magic: String
    public let length: Int
    public let type: Int
    public let idxt: Int
    public let numRecords: Int
    public let encoding: Int
    public let language: Int
    public let total: Int
    public let ordt: Int
    public let ligt: Int
    public let numLigt: Int
    public let numCncx: Int

    public init(
        magic: String,
        length: Int,
        type: Int,
        idxt: Int,
        numRecords: Int,
        encoding: Int,
        language: Int,
        total: Int,
        ordt: Int,
        ligt: Int,
        numLigt: Int,
        numCncx: Int
    ) {
        self.magic = magic
        self.length = length
        self.type = type
        self.idxt = idxt
        self.numRecords = numRecords
        self.encoding = encoding
        self.language = language
        self.total = total
        self.ordt = ordt
        self.ligt = ligt
        self.numLigt = numLigt
        self.numCncx = numCncx
    }
}

/// The TAGX header — upstream `entities/TagxHeader.kt`.
public struct MobiTagxHeader {
    public let magic: String
    public let length: Int
    public let numControlBytes: Int

    public init(magic: String, length: Int, numControlBytes: Int) {
        self.magic = magic
        self.length = length
        self.numControlBytes = numControlBytes
    }
}

/// The TAGX tag — upstream `entities/TagxTag.kt`.
public struct MobiTagxTag {
    public let tag: Int
    public let numValues: Int
    public let bitmask: Int
    public let controlByte: Int

    public init(tag: Int, numValues: Int, bitmask: Int, controlByte: Int) {
        self.tag = tag
        self.numValues = numValues
        self.bitmask = bitmask
        self.controlByte = controlByte
    }
}

/// The KF6 section — upstream `entities/KF6Section.kt`.
public final class MobiKF6Section {
    public let index: Int
    public let start: Int
    public let end: Int
    public let length: Int
    public let href: String
    public var next: MobiKF6Section?

    init(index: Int, start: Int, end: Int, length: Int, href: String) {
        self.index = index
        self.start = start
        self.end = end
        self.length = length
        self.href = href
    }
}

/// The KF8 skeleton — upstream `entities/Skeleton.kt`.
public struct MobiSkeleton {
    public let index: Int
    public let name: String
    public let numFrag: Int
    public let offset: Int
    public let length: Int
}

/// The KF8 fragment — upstream `entities/Fragment.kt`.
public struct MobiFragment {
    public let insertOffset: Int
    public let selector: String
    public let index: Int
    public let offset: Int
    public let length: Int
}

/// The KF8 section — upstream `entities/KF8Section.kt`.
public final class MobiKF8Section {
    public let index: Int
    public let skeleton: MobiSkeleton
    public let frags: [MobiFragment]
    public let fragEnd: Int
    public let length: Int
    public let totalLength: Int
    public let href: String
    public var next: MobiKF8Section?

    /// The upstream `KF8Section.linear`.
    public var linear: Bool { !frags.isEmpty }

    init(
        index: Int,
        skeleton: MobiSkeleton,
        frags: [MobiFragment],
        fragEnd: Int,
        length: Int,
        totalLength: Int,
        href: String
    ) {
        self.index = index
        self.skeleton = skeleton
        self.frags = frags
        self.fragEnd = fragEnd
        self.length = length
        self.totalLength = totalLength
        self.href = href
    }
}

/// The KF8 position — upstream `entities/KF8Pos.kt`.
public struct MobiKF8Pos {
    public let fid: Int
    public let offset: Int
}

// MARK: - The container

/// The PalmDB container — upstream `PDBFile.kt`.
public final class PDBFile {

    public let name: String
    public let type: String
    public let creator: String
    public let recordCount: Int
    private let offsets: [Int]
    private let data: [UInt8]

    public init(url: URL) throws {
        let data = try Data(contentsOf: url)
        self.data = [UInt8](data)
        guard self.data.count >= 78 else { throw MobiError.invalidHeader }
        name = MobiBytes.trimmedString(self.data, 0, 32)
        type = MobiBytes.trimmedString(self.data, 60, 4)
        creator = MobiBytes.trimmedString(self.data, 64, 4)
        recordCount = MobiBytes.uint16(self.data, 76)
        var offsets: [Int] = []
        offsets.reserveCapacity(recordCount)
        for index in 0..<recordCount {
            offsets.append(MobiBytes.int32(self.data, 78 + index * 8))
        }
        self.offsets = offsets
    }

    /// The data of a record — upstream `PDBFile.getRecordData`.
    public func recordData(_ index: Int) -> [UInt8] {
        guard index >= 0, index < recordCount else { return [] }
        let start = offsets[index]
        let end = index + 1 < recordCount ? offsets[index + 1] : data.count
        guard start >= 0, end > start else { return [] }
        return MobiBytes.bytes(data, start, end - start)
    }
}

/// The errors of the MOBI reader.
public enum MobiError: Error, Equatable {
    case invalidHeader
    case unsupportedCompression(Int)
    case unknownCharset(Int)
    case invalidRecord(String)
}

// MARK: - The decompressors

/// The decompressor protocol — upstream `decompress/Decompressor.kt`.
protocol MobiDecompressing {
    func decompress(_ data: [UInt8]) -> [UInt8]
}

/// The uncompressed text — upstream `decompress/PlainDecompressor.kt`.
struct MobiPlainDecompressor: MobiDecompressing {
    func decompress(_ data: [UInt8]) -> [UInt8] { data }
}

/// The LZ77 text — upstream `decompress/Lz77Decompressor.kt`.
struct MobiLz77Decompressor: MobiDecompressing {

    let textRecordSize: Int

    func decompress(_ data: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(max(textRecordSize, data.count * 4))
        var index = 0
        while index < data.count {
            var control = Int(data[index])
            index += 1
            if control >= 0x01 && control <= 0x08 {
                var copied = 0
                while copied < control && index + copied < data.count {
                    out.append(data[index + copied])
                    copied += 1
                }
                index += control
            } else if control <= 0x7F {
                out.append(UInt8(control))
            } else if control >= 0xC0 {
                out.append(0x20)
                out.append(UInt8(control ^ 0x80))
            } else if index < data.count {
                control = (control << 8) | Int(data[index])
                index += 1
                let length = (control & 0x0007) + 3
                let location = (control >> 3) & 0x7FF
                if location >= 1 && location <= out.count {
                    for _ in 0..<length {
                        let source = out.count - location
                        out.append(out[source])
                    }
                }
            }
        }
        return out
    }
}

/// The HUFF-Cdic text — upstream `decompress/HuffcdicDecompressor.kt`.
final class MobiHuffcdicDecompressor: MobiDecompressing {

    private struct Entry {
        var data: [UInt8]
        var decompressed: Bool
    }

    private let table1: [Int]
    private let mincodeTable: [Int64]
    private let maxcodeTable: [Int64]
    private var dictionary: [Entry]

    init(book: MobiBook, header: MobiHeader) throws {
        let huff = book.record(header.huffcdic)
        guard MobiBytes.string(huff, 0, 4) == "HUFF" else {
            throw MobiError.invalidRecord("Invalid HUFF record")
        }
        let offset1 = MobiBytes.int32(huff, 8)
        let offset2 = MobiBytes.int32(huff, 12)

        var table: [Int] = []
        table.reserveCapacity(256)
        for index in 0..<256 {
            table.append(MobiBytes.int32(huff, offset1 + index * 4))
        }
        table1 = table

        var mincodes = [Int64](repeating: 0, count: 33)
        var maxcodes = [Int64](repeating: 0, count: 33)
        var position = offset2
        for index in 1...32 {
            let mincode = Int64(MobiBytes.int32(huff, position))
            let maxcode = Int64(MobiBytes.int32(huff, position + 4))
            position += 8
            mincodes[index] = mincode << (32 - index)
            maxcodes[index] = ((maxcode + 1) << (32 - index)) - 1
        }
        mincodeTable = mincodes
        maxcodeTable = maxcodes

        var entries: [Entry] = []
        if header.numHuffcdic > 1 {
            for index in 1..<header.numHuffcdic {
                let record = book.record(header.huffcdic + index)
                guard MobiBytes.string(record, 0, 4) == "CDIC" else {
                    throw MobiError.invalidRecord("Invalid CDIC record")
                }
                let length = MobiBytes.int32(record, 4)
                let numEntries = MobiBytes.int32(record, 8)
                let codeLength = MobiBytes.int32(record, 12)
                let count = min(1 << codeLength, numEntries - entries.count)
                guard count > 0 else { continue }
                let buffer = MobiBytes.bytes(record, length, record.count - length)
                for j in 0..<count {
                    let offset = MobiBytes.uint16(buffer, j * 2)
                    let value = MobiBytes.uint16(buffer, offset)
                    let entryLength = value & 0x7FFF
                    let isDecompressed = (value & 0x8000) != 0
                    let payload = MobiBytes.bytes(buffer, offset + 2, entryLength)
                    entries.append(Entry(data: payload, decompressed: isDecompressed))
                }
            }
        }
        dictionary = entries
    }

    func decompress(_ data: [UInt8]) -> [UInt8] {
        var output: [UInt8] = []
        output.reserveCapacity(data.count * 4)
        var bitsLeft = data.count * 8
        var position = 0
        var window = readUIntX(data, position, 8)
        var bitCount = 32

        while true {
            if bitCount <= 0 {
                position += 4
                window = readUIntX(data, position, 8)
                bitCount += 32
            }
            let code = Int((window >> UInt64(bitCount)) & 0xFFFF_FFFF)
            let entry = table1[(code >> 24) & 0xFF]
            var codeLength = entry & 0x1F
            var maxCode = Int64((Int64(entry >> 8) + 1) << (32 - codeLength)) - 1
            if (entry & 0x80) == 0 {
                while codeLength < 32, Int64(code) < mincodeTable[codeLength] {
                    codeLength += 1
                }
                maxCode = maxcodeTable[codeLength]
            }
            bitCount -= codeLength
            bitsLeft -= codeLength
            if bitsLeft < 0 { break }
            let index = Int((maxCode - Int64(code)) >> (32 - codeLength))
            guard index >= 0, index < dictionary.count else { break }
            if !dictionary[index].decompressed {
                dictionary[index].data = decompress(dictionary[index].data)
                dictionary[index].decompressed = true
            }
            output.append(contentsOf: dictionary[index].data)
        }
        return output
    }

    /// The big-endian 64 bit read — upstream `readUIntX`.
    private func readUIntX(_ data: [UInt8], _ offset: Int, _ maxLength: Int) -> UInt64 {
        var value: UInt64 = 0
        var index = maxLength
        while index > 0 {
            index -= 1
            guard offset + (maxLength - 1 - index) < data.count else { break }
            let byte = data[offset + (maxLength - 1 - index)]
            value |= UInt64(byte) << UInt64(index * 8)
        }
        return value
    }
}

// MARK: - The book

/// The MOBI book — upstream `MobiBook.kt` (with the KF6 / KF8 flavours).
public final class MobiBook {

    public let headers: MobiEntryHeaders
    public let palmdoc: PalmDocHeader
    public let mobi: MobiHeader
    public let exth: [String: MobiExthValue]
    public let kf8Header: KF8Header?
    public let charset: String.Encoding

    /// The table of contents.
    public private(set) var toc: [MobiTOC]?

    /// The KF6 sections.
    public private(set) var kf6Sections: [MobiKF6Section]?

    /// The KF8 sections.
    public private(set) var kf8Sections: [MobiKF8Section]?

    /// The section index → the table of contents entries.
    public private(set) var sectionIdMap: [Int: [MobiTOC]] = [:]

    /// Whether the book uses the KF8 layout.
    public let isKF8: Bool

    private let pdb: PDBFile
    private let kf8BoundaryOffset: Int
    private let resourceStart: Int
    /// The decompressor of the text records.
    ///
    /// It is an implicitly unwrapped optional because the HUFF/CDIC
    /// decompressor needs the book itself — the upstream does the same
    /// (`MobiReader` creates the decompressor with the book).
    private var decompressor: MobiDecompressing!
    private var textRecordCache: [Int: [UInt8]] = [:]
    private var skelTable: [MobiSkeleton] = []
    private var fragTable: [MobiFragment] = []

    // MARK: - The creation

    /// Reads a MOBI file — upstream `MobiReader.readMobi`.
    public static func read(url: URL) throws -> MobiBook {
        let pdb = try PDBFile(url: url)
        let record0 = pdb.recordData(0)
        var headers = try MobiReader.readEntryHeaders(record0)
        var boundary = 0
        var isKF8 = headers.mobi.version >= 8
        if !isKF8 {
            if let value = headers.exth["boundary"]?.number, value != -1 {
                let buffer = pdb.recordData(value)
                if !buffer.isEmpty {
                    headers = try MobiReader.readEntryHeaders(buffer)
                    boundary = value
                    isKF8 = true
                }
            }
        }
        return try MobiBook(
            pdb: pdb,
            headers: headers,
            kf8BoundaryOffset: boundary,
            resourceStart: headers.mobi.resourceStart
        )
    }

    init(
        pdb: PDBFile,
        headers: MobiEntryHeaders,
        kf8BoundaryOffset: Int,
        resourceStart: Int
    ) throws {
        self.pdb = pdb
        self.headers = headers
        self.kf8BoundaryOffset = kf8BoundaryOffset
        self.resourceStart = resourceStart
        mobi = headers.mobi
        palmdoc = headers.palmdoc
        exth = headers.exth
        kf8Header = headers.kf8

        switch mobi.encoding {
        case 65001:
            charset = .utf8
        case 1252:
            charset = .windowsCP1252
        default:
            throw MobiError.unknownCharset(mobi.encoding)
        }

        isKF8 = mobi.version >= 8 || kf8BoundaryOffset > 0

        switch palmdoc.compression {
        case 1:
            decompressor = MobiPlainDecompressor()
        case 2:
            decompressor = MobiLz77Decompressor(textRecordSize: max(4096, palmdoc.recordSize))
        case 17480:
            decompressor = try MobiHuffcdicDecompressor(book: self, header: mobi)
        default:
            throw MobiError.unsupportedCompression(palmdoc.compression)
        }

        if isKF8 {
            try prepareKF8()
        } else {
            try prepareKF6()
        }
    }

    // MARK: - The metadata

    /// The metadata — upstream `MobiBook.metadata`.
    public var metadata: MobiMetadata {
        MobiMetadata(
            identifier: String(mobi.uid),
            title: exth["title"]?.text ?? mobi.title,
            author: exth["creator"]?.texts ?? [],
            publisher: exth["publisher"]?.text ?? "",
            language: exth["language"]?.text ?? mobi.language,
            published: exth["date"]?.text ?? "",
            description: exth["description"]?.text ?? "",
            subject: exth["subject"]?.texts ?? [],
            rights: exth["rights"]?.text ?? ""
        )
    }

    // MARK: - The records

    /// A record of the book (the KF8 boundary is added) — upstream
    /// `MobiBook.getRecord`.
    public func record(_ index: Int) -> [UInt8] {
        pdb.recordData(kf8BoundaryOffset + index)
    }

    /// A resource — upstream `MobiBook.getResource`.
    public func resource(_ index: Int) -> [UInt8] {
        pdb.recordData(resourceStart + index)
    }

    /// The decompressed text record — upstream `MobiBook.getTextRecord`.
    public func textRecord(_ index: Int) -> [UInt8] {
        if let cached = textRecordCache[index] { return cached }
        guard index >= 0, index < palmdoc.numTextRecords else { return [] }
        var content = record(index + 1)
        content = removeTrailingEntries(content)
        let decompressed = decompressor.decompress(content)
        textRecordCache[index] = decompressed
        return decompressed
    }

    /// The whole text — the concatenation of the text records.
    public func allText() -> [UInt8] {
        var result: [UInt8] = []
        for index in 0..<palmdoc.numTextRecords {
            result.append(contentsOf: textRecord(index))
        }
        return result
    }

    /// The text bytes of a range — upstream `getTextRecordInputStream`.
    public func text(from offset: Int, length: Int) -> [UInt8] {
        guard length > 0 else { return [] }
        var result: [UInt8] = []
        result.reserveCapacity(length)
        var position = 0
        var index = 0
        while result.count < length && index < palmdoc.numTextRecords {
            let record = textRecord(index)
            let recordEnd = position + record.count
            if offset < recordEnd {
                let start = max(0, offset - position)
                let take = min(record.count - start, length - result.count)
                if take > 0 {
                    result.append(contentsOf: record[start..<(start + take)])
                }
            }
            position = recordEnd
            index += 1
        }
        return result
    }

    /// The trailing entries of a text record — upstream
    /// `MobiBook.removeTrailingEntries`.
    private func removeTrailingEntries(_ bytes: [UInt8]) -> [UInt8] {
        let flags = mobi.trailingFlags
        guard flags != 0, !bytes.isEmpty else { return bytes }
        let multibyte = (flags & 1) != 0
        let count = flags >> 1
        let lastIndex = bytes.count - 1
        var extraSize = 0
        for _ in 0..<count {
            var value = 0
            let lower = max(0, lastIndex - 4 - extraSize)
            let upper = max(0, lastIndex - extraSize)
            if lower <= upper {
                for index in lower...upper {
                    let byte = Int(bytes[index])
                    if (byte & 0b1000_0000) != 0 { value = 0 }
                    value = (value << 7) | (byte & 0b111_1111)
                }
            }
            extraSize += value
        }
        if multibyte {
            let position = lastIndex - extraSize
            if position >= 0 {
                let byte = Int(bytes[position])
                extraSize += (byte & 0b11) + 1
            }
        }
        guard extraSize > 0 else { return bytes }
        let end = max(0, bytes.count - extraSize)
        return Array(bytes[0..<end])
    }

    // MARK: - The cover

    /// The cover image — upstream `MobiBook.getCover`.
    public func cover() -> [UInt8]? {
        if let offset = exth["coverOffset"]?.number, offset != -1 {
            let data = resource(offset)
            return data.isEmpty ? nil : data
        }
        if let offset = exth["thumbnailOffset"]?.number, offset != -1 {
            let data = resource(offset)
            return data.isEmpty ? nil : data
        }
        return nil
    }

    // MARK: - The index

    /// The index data — upstream `MobiBook.getIndexData`.
    public func indexData(_ indxIndex: Int) throws -> MobiIndexData {
        let indxRecord = record(indxIndex)
        let indx = try MobiReader.readIndxHeader(indxRecord)
        let tagxBuffer = MobiBytes.bytes(indxRecord, indx.length, indxRecord.count - indx.length)
        let tagx = try MobiReader.readTagxHeader(tagxBuffer)
        let tagTable = MobiReader.readTagxTags(tagx: tagx, buffer: tagxBuffer)
        let cncx = try readCncx(indxIndex: indxIndex, indx: indx)

        var table: [MobiIndexEntry] = []
        for index in 0..<indx.numRecords {
            let buffer = record(indxIndex + 1 + index)
            let header = try MobiReader.readIndxHeader(buffer)
            let idxt = MobiReader.readIdxt(buffer: buffer, header: header)
            for j in 0..<header.numRecords {
                let offset = idxt[j]
                table.append(
                    MobiReader.readIndexEntry(
                        buffer: buffer,
                        tagx: tagx,
                        tagTable: tagTable,
                        idxtOffset: offset
                    )
                )
            }
        }
        return MobiIndexData(table: table, cncx: cncx)
    }

    /// The compressed NCX text — upstream `MobiBook.readCncx`.
    private func readCncx(indxIndex: Int, indx: MobiIndxHeader) throws -> [Int: String] {
        var cncx: [Int: String] = [:]
        var recordOffset = 0
        for index in 0..<indx.numCncx {
            let data = record(indxIndex + indx.numRecords + index + 1)
            var position = 0
            while position < data.count {
                let key = position
                var value = 0
                var length = 0
                let upper = min(position + 4, data.count)
                if position < upper {
                    for offset in position..<upper {
                        let byte = Int(data[offset])
                        value = (value << 7) | (byte & 0b111_1111)
                        length += 1
                        if (byte & 0b1000_0000) != 0 { break }
                    }
                } else {
                    break
                }
                position += length
                let text = MobiBytes.string(data, position, value, charset)
                position += value
                cncx[recordOffset + key] = text
            }
            recordOffset += 0x10000
        }
        return cncx
    }

    /// The navigation — upstream `MobiBook.getNCX`.
    public func ncx() throws -> [MobiNCX]? {
        let indxIndex = mobi.indx
        guard indxIndex != -1 else { return nil }
        // A book without a usable index has no table of contents — the
        // upstream would throw, the port falls back to the sections.
        guard let data = try? indexData(indxIndex) else { return nil }
        var items: [MobiNCX] = []
        for (index, entry) in data.table.enumerated() {
            let map = entry.tagMap
            let label = map[3].flatMap { data.cncx[$0.tagValues[0]] } ?? ""
            items.append(
                MobiNCX(
                    index: index,
                    offset: map[1]?.tagValues.first,
                    size: map[2]?.tagValues.first,
                    label: label,
                    headingLevel: map[4]?.tagValues.first,
                    pos: map[6]?.tagValues,
                    parent: map[21]?.tagValues.first,
                    firstChild: map[22]?.tagValues.first,
                    lastChild: map[23]?.tagValues.first
                )
            )
        }

        var childrenMap: [Int: [MobiNCX]] = [:]
        for item in items {
            guard let parent = item.parent else { continue }
            childrenMap[parent, default: []].append(item)
        }

        func withChildren(_ item: MobiNCX) -> MobiNCX {
            guard item.firstChild != nil else { return item }
            var copy = item
            copy.children = childrenMap[item.index]?.map(withChildren)
            return copy
        }

        return items.filter { $0.headingLevel == 0 }.map(withChildren)
    }

    // MARK: - KF6

    private func prepareKF6() throws {
        let sections = buildKF6Sections()
        kf6Sections = sections
        if let ncx = try ncx() {
            func makeToc(_ item: MobiNCX) -> MobiTOC {
                let offset = item.offset ?? 0
                let href = "filepos:" + String(format: "%010d", offset)
                return MobiTOC(label: item.label, href: href, subitems: item.children?.map(makeToc))
            }
            toc = ncx.map(makeToc)
        }
        buildSectionIdMap()
    }

    /// The sections of a KF6 book — upstream `KF6Book.processSections`.
    private func buildKF6Sections() -> [MobiKF6Section] {
        let text = allText()
        let breaks = MobiBook.pageBreaks(text)
        var sections: [MobiKF6Section] = []
        var nextStart = 0
        for range in breaks {
            let start = nextStart
            let end = range.lowerBound
            let length = end - start
            let href = "filepos:" + String(format: "%010d", start)
            let section = MobiKF6Section(
                index: sections.count,
                start: start,
                end: end,
                length: length,
                href: href
            )
            sections.last?.next = section
            sections.append(section)
            nextStart = range.upperBound
        }
        if nextStart > 0 {
            let start = nextStart
            let length = text.count - start
            let href = "filepos:" + String(format: "%010d", start)
            let section = MobiKF6Section(
                index: sections.count,
                start: start,
                end: text.count,
                length: length,
                href: href
            )
            sections.last?.next = section
            sections.append(section)
        } else if sections.isEmpty && !text.isEmpty {
            // A text without any <mbp:pagebreak> yields no section upstream (the
            // `nextStart > 0` guard), but the upstream always builds its chapter
            // list from the NCX and never hits the empty case. The port falls back
            // to the whole text so that a book without a table of contents still
            // opens with one chapter.
            let section = MobiKF6Section(
                index: 0,
                start: 0,
                end: text.count,
                length: text.count,
                href: "filepos:" + String(format: "%010d", 0)
            )
            sections.append(section)
        }
        return sections
    }

    /// The `<mbp:pagebreak>` markers — upstream
    /// `KF6Book.mbpPagebreakRegex` (`(?i)<\s*(?:mbp:)?pagebreak[^>]*>`).
    static func pageBreaks(_ text: [UInt8]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var index = 0
        while index < text.count {
            guard text[index] == 0x3C else {
                index += 1
                continue
            }
            var cursor = index + 1
            while cursor < text.count, isMobiSpace(text[cursor]) { cursor += 1 }
            if matches(text, cursor, "mbp:") { cursor += 4 }
            if matches(text, cursor, "pagebreak") {
                cursor += 9
                while cursor < text.count, text[cursor] != 0x3E { cursor += 1 }
                if cursor < text.count {
                    cursor += 1
                    result.append(index..<cursor)
                    index = cursor
                    continue
                }
            }
            index += 1
        }
        return result
    }

    private static func isMobiSpace(_ byte: UInt8) -> Bool {
        byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x0C
    }

    private static func matches(_ text: [UInt8], _ offset: Int, _ pattern: String) -> Bool {
        let bytes = Array(pattern.utf8)
        guard offset >= 0, offset + bytes.count <= text.count else { return false }
        for index in 0..<bytes.count {
            let left = text[offset + index] | 0x20
            let right = bytes[index] | 0x20
            if left != right { return false }
        }
        return true
    }

    /// The section of a `filepos:` href — upstream `KF6Book.getSectionByHref`.
    public func kf6Section(byHref href: String) -> MobiKF6Section? {
        guard let filepos = MobiBook.number(after: "filepos:", in: href) else { return nil }
        return kf6Sections?.first { $0.end > filepos }
    }

    /// The text of a KF6 section — upstream `KF6Book.getSectionText`.
    public func kf6SectionText(_ section: MobiKF6Section) -> String {
        let bytes = text(from: section.start, length: section.length)
        return MobiBytes.string(bytes, 0, bytes.count, charset)
    }

    /// The resource of a `recindex:` href — upstream `KF6Book.getResourceByHref`.
    public func kf6Resource(byHref href: String) -> [UInt8]? {
        guard let index = MobiBook.number(after: "recindex:", in: href) else { return nil }
        return resource(index - 1)
    }

    // MARK: - KF8

    private func prepareKF8() throws {
        guard let kf8 = kf8Header else {
            try prepareKF6()
            return
        }
        readFdstTable(kf8: kf8)
        skelTable = try readSkelTable(kf8: kf8)
        fragTable = try readFragTable(kf8: kf8)
        let sections = buildKF8Sections()
        kf8Sections = sections
        if let ncx = try ncx() {
            func makeToc(_ item: MobiNCX) -> MobiTOC {
                let fid = item.pos?.first ?? 0
                let offset = item.pos?.count ?? 0 > 1 ? (item.pos?[1] ?? 0) : 0
                let href = MobiBook.makePosURI(fid: fid, offset: offset)
                return MobiTOC(label: item.label, href: href, subitems: item.children?.map(makeToc))
            }
            toc = ncx.map(makeToc)
        }
        buildSectionIdMap()
    }

    private func readFdstTable(kf8: KF8Header) {
        let data = record(kf8.fdst)
        guard MobiBytes.string(data, 0, 4) == "FDST" else { return }
        let numEntries = MobiBytes.int32(data, 8)
        var starts: [Int] = []
        var ends: [Int] = []
        var position = 12
        for _ in 0..<numEntries {
            starts.append(MobiBytes.int32(data, position))
            ends.append(MobiBytes.int32(data, position + 4))
            position += 8
        }
        fdstTableStarts = starts
        fdstTableEnds = ends
    }

    private var fdstTableStarts: [Int] = []
    private var fdstTableEnds: [Int] = []

    private func readSkelTable(kf8: KF8Header) throws -> [MobiSkeleton] {
        let data = try indexData(kf8.skel)
        return data.table.enumerated().map { index, entry in
            let map = entry.tagMap
            return MobiSkeleton(
                index: index,
                name: entry.label,
                numFrag: map[1]?.tagValues.first ?? 0,
                offset: map[6]?.tagValues.first ?? 0,
                length: map[6].flatMap { $0.tagValues.count > 1 ? $0.tagValues[1] : nil } ?? 0
            )
        }
    }

    private func readFragTable(kf8: KF8Header) throws -> [MobiFragment] {
        let data = try indexData(kf8.frag)
        return data.table.map { entry in
            let map = entry.tagMap
            return MobiFragment(
                insertOffset: Int(entry.label) ?? 0,
                selector: map[2].flatMap { data.cncx[$0.tagValues[0]] } ?? "",
                index: map[4]?.tagValues.first ?? 0,
                offset: map[6]?.tagValues.first ?? 0,
                length: map[6].flatMap { $0.tagValues.count > 1 ? $0.tagValues[1] : nil } ?? 0
            )
        }
    }

    private func buildKF8Sections() -> [MobiKF8Section] {
        var sections: [MobiKF8Section] = []
        for skeleton in skelTable {
            let last = sections.last
            let index = sections.count
            let fragStart = last?.fragEnd ?? 0
            let fragEnd = fragStart + skeleton.numFrag
            let frags = fragEnd <= fragTable.count
                ? Array(fragTable[fragStart..<fragEnd])
                : Array(fragTable.dropFirst(fragStart))
            let length = skeleton.length + frags.reduce(0) { $0 + $1.length }
            let totalLength = (last?.totalLength ?? 0) + length
            let href = frags.first.map { MobiBook.makePosURI(fid: $0.index, offset: 0) } ?? ""
            let section = MobiKF8Section(
                index: index,
                skeleton: skeleton,
                frags: frags,
                fragEnd: fragEnd,
                length: length,
                totalLength: totalLength,
                href: href
            )
            last?.next = section
            sections.append(section)
        }
        return sections
    }

    /// The `kindle:pos:fid:…:off:…` href — upstream `KF8Book.parsePosURI`.
    public func kf8Pos(href: String) -> MobiKF8Pos? {
        guard let range = href.range(of: "kindle:pos:fid:") else { return nil }
        let rest = href[range.upperBound...]
        guard let offRange = rest.range(of: ":off:") else { return nil }
        let fidText = String(rest[..<offRange.lowerBound])
        let offsetText = String(rest[offRange.upperBound...])
        guard let fid = Int(fidText, radix: 32), let offset = Int(offsetText, radix: 32) else {
            return nil
        }
        return MobiKF8Pos(fid: fid, offset: offset)
    }

    /// The `kindle:pos:` href — upstream `KF8Book.makePosURI`.
    static func makePosURI(fid: Int, offset: Int) -> String {
        let encodedFid = String(fid, radix: 32).uppercased()
        let encodedOffset = String(offset, radix: 32).uppercased()
        let paddedFid = String(repeating: "0", count: max(0, 4 - encodedFid.count)) + encodedFid
        let paddedOffset = String(repeating: "0", count: max(0, 10 - encodedOffset.count)) + encodedOffset
        return "kindle:pos:fid:\(paddedFid):off:\(paddedOffset)"
    }

    /// The section of a `kindle:pos:` href — upstream `KF8Book.getSectionByHref`.
    public func kf8Section(byHref href: String) -> MobiKF8Section? {
        guard let pos = kf8Pos(href: href) else { return nil }
        return kf8Sections?.first { section in
            section.frags.contains { $0.index == pos.fid }
        }
    }

    /// The text of a KF8 section — upstream `KF8Book.getSectionText`.
    public func kf8SectionText(_ section: MobiKF8Section) -> String {
        let skeleton = section.skeleton
        let frags = section.frags
        let raw = text(from: skeleton.offset, length: section.length)
        var buffer = [UInt8](repeating: 0, count: raw.count)
        var leftBytes = raw.count
        MobiBytes.copy(raw, into: &buffer, destinationOffset: 0, sourceStart: 0, sourceEnd: skeleton.length)
        leftBytes -= skeleton.length
        for frag in frags {
            let insertOffset = frag.insertOffset - skeleton.offset
            let offset = skeleton.length + frag.offset
            MobiBytes.copy(
                buffer,
                into: &buffer,
                destinationOffset: insertOffset + frag.length,
                sourceStart: insertOffset,
                sourceEnd: buffer.count - leftBytes
            )
            MobiBytes.copy(
                raw,
                into: &buffer,
                destinationOffset: insertOffset,
                sourceStart: offset,
                sourceEnd: offset + frag.length
            )
            leftBytes -= frag.length
        }
        return MobiBytes.string(buffer, 0, buffer.count, charset)
    }

    /// The text of a KF8 href — upstream `KF8Book.getTextByHref`.
    public func kf8Text(byHref href: String, nextHref: String) -> String {
        guard let pos = kf8Pos(href: href), let nextPos = kf8Pos(href: nextHref) else { return "" }
        guard let sections = kf8Sections else { return "" }
        let index = sections.firstIndex { section in
            section.frags.contains { $0.index == pos.fid }
        } ?? 0
        let nextIndex = sections.firstIndex { section in
            section.frags.contains { $0.index == nextPos.fid }
        } ?? 0
        let startFid = pos.fid
        let endFid = index == nextIndex ? nextPos.fid : Int.max
        let section = sections[index]
        let skeleton = section.skeleton
        var droppedFragsLength = section.frags
            .filter { $0.index < startFid }
            .reduce(0) { $0 + $1.length }
        let frags = section.frags.filter { $0.index >= startFid && $0.index <= endFid }
        guard !frags.isEmpty else { return "" }
        let length = skeleton.length + frags.reduce(0) { $0 + $1.length }
        let raw = text(from: skeleton.offset, length: section.length)
        let lastFragDroppedLength = index == nextIndex ? frags[frags.count - 1].length - nextPos.offset : 0
        let size = length - pos.offset - lastFragDroppedLength
        guard size > 0 else { return "" }
        var buffer = [UInt8](repeating: 0, count: size)
        var leftBytes = size
        MobiBytes.copy(raw, into: &buffer, destinationOffset: 0, sourceStart: 0, sourceEnd: skeleton.length)
        leftBytes -= skeleton.length
        for (i, frag) in frags.enumerated() {
            let isFirstFrag = i == 0
            let isLastFrag = i == frags.count - 1
            let insertOffset = frag.insertOffset - skeleton.offset - droppedFragsLength
            let offset = skeleton.length + frag.offset
            let destination = insertOffset + frag.length
                - (isFirstFrag ? pos.offset : 0)
                - (isLastFrag ? lastFragDroppedLength : 0)
            MobiBytes.copy(
                buffer,
                into: &buffer,
                destinationOffset: destination,
                sourceStart: insertOffset,
                sourceEnd: buffer.count - leftBytes
            )
            MobiBytes.copy(
                raw,
                into: &buffer,
                destinationOffset: insertOffset,
                sourceStart: offset + (isFirstFrag ? pos.offset : 0),
                sourceEnd: offset + frag.length - (isLastFrag ? lastFragDroppedLength : 0)
            )
            leftBytes -= frag.length
                - (isFirstFrag ? pos.offset : 0)
                - (isLastFrag && index == nextIndex ? nextPos.offset : 0)
            if isFirstFrag {
                droppedFragsLength += pos.offset
            }
        }
        return MobiBytes.string(buffer, 0, buffer.count, charset)
    }

    /// The resource of a `kindle:embed:` href — upstream `KF8Book.getResourceByHref`.
    public func kf8Resource(byHref href: String) -> [UInt8]? {
        guard let range = href.range(of: "kindle:embed:") else { return nil }
        let rest = href[range.upperBound...]
        let digits = rest.prefix { $0.isLetter || $0.isNumber }
        guard let id = Int(digits, radix: 32) else { return nil }
        return resource(id - 1)
    }

    // MARK: - The section map

    private func buildSectionIdMap() {
        var map: [Int: [MobiTOC]] = [:]
        guard let toc else { return }
        func visit(_ item: MobiTOC) {
            let index = sectionIndex(href: item.href)
            guard index >= 0 else { return }
            map[index, default: []].append(item)
            item.subitems?.forEach(visit)
        }
        toc.forEach(visit)
        sectionIdMap = map
    }

    private func sectionIndex(href: String) -> Int {
        if isKF8 {
            guard let pos = kf8Pos(href: href) else { return -1 }
            return kf8Sections?.firstIndex { section in
                section.frags.contains { $0.index == pos.fid }
            } ?? -1
        }
        guard let filepos = MobiBook.number(after: "filepos:", in: href) else { return -1 }
        return kf6Sections?.firstIndex { $0.end > filepos } ?? -1
    }

    /// The number after a marker — upstream `String.substringAfter`.
    static func number(after marker: String, in text: String) -> Int? {
        guard let range = text.range(of: marker) else { return nil }
        let rest = text[range.upperBound...]
        let digits = rest.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }
}

// MARK: - The entry headers

/// The headers of a MOBI record — upstream `entities/MobiEntryHeaders.kt`.
public struct MobiEntryHeaders {
    public let palmdoc: PalmDocHeader
    public let mobi: MobiHeader
    public let exth: [String: MobiExthValue]
    public let kf8: KF8Header?
}

/// The header reader — upstream `MobiReader.kt`.
public enum MobiReader {

    static func readEntryHeaders(_ buffer: [UInt8]) throws -> MobiEntryHeaders {
        let palmdoc = readPalmDocHeader(buffer)
        let mobi = try readMobiHeader(buffer)
        var exth: [String: MobiExthValue] = [:]
        if (mobi.exthFlag & 0b100_0000) != 0 {
            exth = try readExth(MobiBytes.bytes(buffer, mobi.length + 16, buffer.count - mobi.length - 16))
        }
        let kf8: KF8Header? = mobi.version >= 8 ? readKF8Header(buffer) : nil
        return MobiEntryHeaders(palmdoc: palmdoc, mobi: mobi, exth: exth, kf8: kf8)
    }

    private static func readPalmDocHeader(_ content: [UInt8]) -> PalmDocHeader {
        PalmDocHeader(
            compression: MobiBytes.uint16(content, 0),
            numTextRecords: MobiBytes.uint16(content, 8),
            recordSize: MobiBytes.uint16(content, 10),
            encryption: MobiBytes.uint16(content, 12)
        )
    }

    private static func readMobiHeader(_ content: [UInt8]) throws -> MobiHeader {
        let identifier = MobiBytes.string(content, 16, 4)
        guard identifier == "MOBI" else { throw MobiError.invalidHeader }
        let encoding = MobiBytes.int32(content, 28)
        let charset: String.Encoding
        switch encoding {
        case 65001: charset = .utf8
        case 1252: charset = .windowsCP1252
        default: charset = .utf8
        }
        let titleOffset = MobiBytes.int32(content, 84)
        let titleLength = MobiBytes.int32(content, 88)
        let localeRegion = MobiBytes.uint8(content, 94)
        let localeLanguage = MobiBytes.uint8(content, 95)
        return MobiHeader(
            identifier: identifier,
            length: MobiBytes.int32(content, 20),
            type: MobiBytes.int32(content, 24),
            encoding: encoding,
            uid: MobiBytes.int32(content, 32),
            version: MobiBytes.int32(content, 36),
            titleOffset: titleOffset,
            titleLength: titleLength,
            localeRegion: localeRegion,
            localeLanguage: localeLanguage,
            resourceStart: MobiBytes.int32(content, 108),
            huffcdic: MobiBytes.int32(content, 112),
            numHuffcdic: MobiBytes.int32(content, 116),
            exthFlag: MobiBytes.int32(content, 128),
            trailingFlags: MobiBytes.int32(content, 240),
            indx: MobiBytes.int32(content, 244),
            title: MobiBytes.string(content, titleOffset, titleLength, charset),
            language: MobiReader.language(region: localeRegion, language: localeLanguage)
        )
    }

    private static func readKF8Header(_ content: [UInt8]) -> KF8Header {
        KF8Header(
            fdst: MobiBytes.int32(content, 192),
            numFdst: MobiBytes.int32(content, 196),
            frag: MobiBytes.int32(content, 248),
            skel: MobiBytes.int32(content, 252),
            guide: MobiBytes.int32(content, 260)
        )
    }

    private static func readExth(_ buffer: [UInt8]) throws -> [String: MobiExthValue] {
        guard MobiBytes.string(buffer, 0, 4) == "EXTH" else {
            throw MobiError.invalidRecord("Invalid EXTH header")
        }
        let count = MobiBytes.int32(buffer, 8)
        var offset = 12
        var result: [String: MobiExthValue] = [:]
        for _ in 0..<count {
            let type = MobiBytes.int32(buffer, offset)
            let length = MobiBytes.int32(buffer, offset + 4)
            if let record = MobiReader.exthRecordTypes[type] {
                if record.type == "uint" {
                    let value = MobiBytes.int32(buffer, offset + 8)
                    result[record.name] = .number(value)
                } else {
                    let text = MobiBytes.string(buffer, offset + 8, length - 8)
                    if record.many {
                        var values = result[record.name]?.texts ?? []
                        values.append(text)
                        result[record.name] = .texts(values)
                    } else {
                        result[record.name] = .text(text)
                    }
                }
            }
            offset += length
            if offset <= 0 { break }
        }
        return result
    }

    /// The EXTH record types — upstream `MobiReader.exthRecordTypeMap`.
    static let exthRecordTypes: [Int: (name: String, type: String, many: Bool)] = [
        100: ("creator", "string", true),
        101: ("publisher", "string", false),
        103: ("description", "string", false),
        104: ("isbn", "string", false),
        105: ("subject", "string", true),
        106: ("date", "string", false),
        108: ("contributor", "string", true),
        109: ("rights", "string", false),
        110: ("subjectCode", "string", true),
        112: ("source", "string", true),
        113: ("asin", "string", false),
        121: ("boundary", "uint", false),
        122: ("fixedLayout", "string", false),
        125: ("numResources", "uint", false),
        126: ("originalResolution", "string", false),
        127: ("zeroGutter", "string", false),
        128: ("zeroMargin", "string", false),
        129: ("coverURI", "string", false),
        132: ("regionMagnification", "string", false),
        201: ("coverOffset", "uint", false),
        202: ("thumbnailOffset", "uint", false),
        204: ("creatorSoftware", "uint", false),
        503: ("title", "string", false),
        524: ("language", "string", true),
        527: ("pageProgressionDirection", "string", false)
    ]

    // MARK: - The index headers

    static func readIndxHeader(_ buffer: [UInt8]) throws -> MobiIndxHeader {
        let magic = MobiBytes.string(buffer, 0, 4)
        guard magic == "INDX" else { throw MobiError.invalidRecord("Invalid INDX record") }
        return MobiIndxHeader(
            magic: magic,
            length: MobiBytes.int32(buffer, 4),
            type: MobiBytes.int32(buffer, 8),
            idxt: MobiBytes.int32(buffer, 20),
            numRecords: MobiBytes.int32(buffer, 24),
            encoding: MobiBytes.int32(buffer, 28),
            language: MobiBytes.int32(buffer, 32),
            total: MobiBytes.int32(buffer, 36),
            ordt: MobiBytes.int32(buffer, 40),
            ligt: MobiBytes.int32(buffer, 44),
            numLigt: MobiBytes.int32(buffer, 48),
            numCncx: MobiBytes.int32(buffer, 52)
        )
    }

    static func readTagxHeader(_ buffer: [UInt8]) throws -> MobiTagxHeader {
        let magic = MobiBytes.string(buffer, 0, 4)
        guard magic == "TAGX" else { throw MobiError.invalidRecord("Invalid TAGX record") }
        return MobiTagxHeader(
            magic: magic,
            length: MobiBytes.int32(buffer, 4),
            numControlBytes: MobiBytes.int32(buffer, 8)
        )
    }

    static func readTagxTags(tagx: MobiTagxHeader, buffer: [UInt8]) -> [MobiTagxTag] {
        let count = max(0, (tagx.length - 12) / 4)
        var tags: [MobiTagxTag] = []
        tags.reserveCapacity(count)
        var position = 12
        for _ in 0..<count {
            tags.append(
                MobiTagxTag(
                    tag: MobiBytes.uint8(buffer, position),
                    numValues: MobiBytes.uint8(buffer, position + 1),
                    bitmask: MobiBytes.uint8(buffer, position + 2),
                    controlByte: MobiBytes.uint8(buffer, position + 3)
                )
            )
            position += 4
        }
        return tags
    }

    static func readIdxt(buffer: [UInt8], header: MobiIndxHeader) -> [Int] {
        var result: [Int] = []
        result.reserveCapacity(header.numRecords)
        for index in 0..<header.numRecords {
            result.append(MobiBytes.uint16(buffer, header.idxt + 4 + index * 2))
        }
        return result
    }

    /// An index entry — upstream `MobiBook.readIndexEntry`.
    static func readIndexEntry(
        buffer: [UInt8],
        tagx: MobiTagxHeader,
        tagTable: [MobiTagxTag],
        idxtOffset: Int
    ) -> MobiIndexEntry {
        let length = MobiBytes.uint8(buffer, idxtOffset)
        let label = MobiBytes.string(buffer, idxtOffset + 1, length)
        let startPos = idxtOffset + 1 + length
        var controlByteIndex = 0
        var position = startPos + tagx.numControlBytes

        var ptagxs: [(tag: Int, tagValueCount: Int, valueCount: Int?, valueBytes: Int?)] = []
        for tag in tagTable {
            if tag.controlByte == 1 {
                controlByteIndex += 1
                continue
            }
            let offset = startPos + controlByteIndex
            var value = MobiBytes.uint8(buffer, offset) & tag.bitmask
            if value == tag.bitmask {
                if tag.bitmask.nonzeroBitCount > 1 {
                    var v = 0
                    let upper = min(position + 4, buffer.count)
                    if position < upper {
                        for index in position..<upper {
                            let byte = Int(buffer[index])
                            v = (v << 7) | (byte & 0b111_1111)
                            position += 1
                            if (byte & 0b1000_0000) != 0 { break }
                        }
                    }
                    ptagxs.append((tag.tag, tag.numValues, nil, v))
                } else {
                    ptagxs.append((tag.tag, tag.numValues, 1, nil))
                }
            } else {
                var mask = tag.bitmask
                while (mask & 1) == 0 {
                    mask >>= 1
                    value >>= 1
                }
                ptagxs.append((tag.tag, tag.numValues, value, nil))
            }
        }

        var tags: [MobiIndexTag] = []
        var tagMap: [Int: MobiIndexTag] = [:]
        for ptagx in ptagxs {
            var values: [Int] = []
            if let valueCount = ptagx.valueCount {
                for _ in 0..<(valueCount * ptagx.tagValueCount) {
                    var v = 0
                    let upper = min(position + 4, buffer.count)
                    if position < upper {
                        for index in position..<upper {
                            let byte = Int(buffer[index])
                            v = (v << 7) | (byte & 0b111_1111)
                            position += 1
                            if (byte & 0b1000_0000) != 0 { break }
                        }
                    }
                    values.append(v)
                }
            } else if let valueBytes = ptagx.valueBytes {
                var count = 0
                while count < valueBytes {
                    var v = 0
                    let upper = min(position + 4, buffer.count)
                    if position < upper {
                        for index in position..<upper {
                            let byte = Int(buffer[index])
                            v = (v << 7) | (byte & 0b111_1111)
                            position += 1
                            count += 1
                            if (byte & 0b1000_0000) != 0 { break }
                        }
                    } else {
                        break
                    }
                    values.append(v)
                }
            }
            let tag = MobiIndexTag(tagId: ptagx.tag, tagValues: values)
            tags.append(tag)
            tagMap[tag.tagId] = tag
        }
        return MobiIndexEntry(label: label, tags: tags, tagMap: tagMap)
    }

    // MARK: - The language

    /// The language of the book — upstream `MobiReader.mobiLangMap`.
    static func language(region: Int, language: Int) -> String {
        guard let list = mobiLangMap[language] else { return "" }
        let index = region >> 2
        if index >= 0, index < list.count {
            if let value = list[index] { return value }
        }
        if let first = list.first { return first ?? "" }
        return ""
    }

    static let mobiLangMap: [Int: [String?]] = [
        1: ["ar", "ar-SA", "ar-IQ", "ar-EG", "ar-LY", "ar-DZ", "ar-MA", "ar-TN", "ar-OM",
            "ar-YE", "ar-SY", "ar-JO", "ar-LB", "ar-KW", "ar-AE", "ar-BH", "ar-QA"],
        2: ["bg"], 3: ["ca"],
        4: ["zh", "zh-TW", "zh-CN", "zh-HK", "zh-SG"],
        5: ["cs"], 6: ["da"],
        7: ["de", "de-DE", "de-CH", "de-AT", "de-LU", "de-LI"], 8: ["el"],
        9: ["en", "en-US", "en-GB", "en-AU", "en-CA", "en-NZ", "en-IE", "en-ZA",
            "en-JM", nil, "en-BZ", "en-TT", "en-ZW", "en-PH"],
        10: ["es", "es-ES", "es-MX", nil, "es-GT", "es-CR", "es-PA", "es-DO",
              "es-VE", "es-CO", "es-PE", "es-AR", "es-EC", "es-CL", "es-UY", "es-PY",
              "es-BO", "es-SV", "es-HN", "es-NI", "es-PR"],
        11: ["fi"],
        12: ["fr", "fr-FR", "fr-BE", "fr-CA", "fr-CH", "fr-LU", "fr-MC"],
        13: ["he"], 14: ["hu"], 15: ["is"],
        16: ["it", "it-IT", "it-CH"], 17: ["ja"], 18: ["ko"],
        19: ["nl", "nl-NL", "nl-BE"], 20: ["no", "nb", "nn"],
        21: ["pl"], 22: ["pt", "pt-BR", "pt-PT"], 23: ["rm"],
        24: ["ro"], 25: ["ru"], 26: ["hr", nil, "sr"],
        27: ["sk"], 28: ["sq"], 29: ["sv", "sv-SE", "sv-FI"],
        30: ["th"], 31: ["tr"], 32: ["ur"], 33: ["id"],
        34: ["uk"], 35: ["be"], 36: ["sl"], 37: ["et"],
        38: ["lv"], 39: ["lt"], 41: ["fa"], 42: ["vi"],
        43: ["hy"], 44: ["az"], 45: ["eu"], 46: ["hsb"],
        47: ["mk"], 48: ["st"], 49: ["ts"], 50: ["tn"],
        52: ["xh"], 53: ["zu"], 54: ["af"], 55: ["ka"],
        56: ["fo"], 57: ["hi"], 58: ["mt"], 59: ["se"],
        62: ["ms"], 63: ["kk"], 65: ["sw"],
        67: ["uz", nil, "uz-UZ"], 68: ["tt"], 69: ["bn"],
        70: ["pa"], 71: ["gu"], 72: ["or"], 73: ["ta"],
        74: ["te"], 75: ["kn"], 76: ["ml"], 77: ["as"],
        78: ["mr"], 79: ["sa"], 82: ["cy", "cy-GB"],
        83: ["gl", "gl-ES"], 87: ["kok"], 97: ["ne"],
        98: ["fy"]
    ]
}
