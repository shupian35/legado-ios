//
//  ZipArchive.swift
//  LegadoCore
//
//  A minimal ZIP reader.
//
//  Why not Foundation: `Foundation` has no public ZIP API on any Apple platform
//  (`NSFileCoordinator` only reads ZIP *packages* and Apple dropped `NSFileManager`
//  unzip helpers long ago). The Android app reads EPUB/UMD archives with the
//  vendored `me.ag2s:epublib` fork, which uses `java.util.zip.ZipFile`.
//
//  This reader implements the parts of the ZIP spec that matter for EPUB/UMD:
//  the end-of-central-directory record, the central directory entries and the
//  local file headers, with STORED (0) and DEFLATE (8) support.
//
//  DEFLATE is inflated through the system zlib via the `CZlib` C shim.
//

import CZlib
import Foundation

/// A single file inside a ZIP archive.
public struct ZipEntry: Equatable {
    public let name: String
    /// 0 = stored, 8 = deflate.
    public let method: UInt16
    public let crc32: UInt32
    public let compressedSize: UInt32
    public let uncompressedSize: UInt32
    public let localHeaderOffset: UInt32
    public let isDirectory: Bool

    public init(
        name: String,
        method: UInt16,
        crc32: UInt32,
        compressedSize: UInt32,
        uncompressedSize: UInt32,
        localHeaderOffset: UInt32,
        isDirectory: Bool
    ) {
        self.name = name
        self.method = method
        self.crc32 = crc32
        self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize
        self.localHeaderOffset = localHeaderOffset
        self.isDirectory = isDirectory
    }
}

public enum ZipError: Error, Equatable {
    case notAnArchive
    case unsupportedCompression(UInt16)
    case entryNotFound(String)
    case corrupt(String)
    case inflateFailed(Int32)
}

/// A read-only ZIP archive backed by an in-memory `Data`.
public final class ZipArchive {
    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50
    private static let centralDirectorySignature: UInt32 = 0x0201_4b50
    private static let localHeaderSignature: UInt32 = 0x0403_4b50

    public let entries: [ZipEntry]
    private let archiveData: Data

    public init(data: Data) throws {
        archiveData = data
        entries = try ZipArchive.readCentralDirectory(data)
    }

    public convenience init(fileURL: URL) throws {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        try self.init(data: data)
    }

    /// The entry whose name matches `name`, or `nil`.
    public func entry(named name: String) -> ZipEntry? {
        entries.first { $0.name == name }
    }

    /// Whether the archive contains `name`.
    public func contains(_ name: String) -> Bool {
        entry(named: name) != nil
    }

    /// The uncompressed bytes of `entry`.
    public func data(for entry: ZipEntry) throws -> Data {
        if entry.isDirectory { return Data() }
        let headerOffset = Int(entry.localHeaderOffset)
        guard headerOffset + 30 <= archiveData.count else {
            throw ZipError.corrupt("local header out of range for \(entry.name)")
        }
        let bytes = [UInt8](archiveData)
        guard ZipArchive.readUInt32(bytes, headerOffset) == ZipArchive.localHeaderSignature else {
            throw ZipError.corrupt("bad local header for \(entry.name)")
        }
        let nameLength = Int(ZipArchive.readUInt16(bytes, headerOffset + 26))
        let extraLength = Int(ZipArchive.readUInt16(bytes, headerOffset + 28))
        let dataStart = headerOffset + 30 + nameLength + extraLength
        let compressedSize = Int(entry.compressedSize)
        guard dataStart + compressedSize <= bytes.count else {
            throw ZipError.corrupt("entry data out of range for \(entry.name)")
        }
        let payload = Data(bytes[dataStart ..< (dataStart + compressedSize)])
        switch entry.method {
        case 0:
            return payload
        case 8:
            let capacity = Int(entry.uncompressedSize)
            guard capacity > 0 else { return Data() }
            var output = Data(count: capacity)
            var produced: size_t = 0
            let status: Int32 = payload.withUnsafeBytes { sourceBuffer in
                output.withUnsafeMutableBytes { outputBuffer in
                    let source = sourceBuffer.bindMemory(to: UInt8.self).baseAddress!
                    let destination = outputBuffer.bindMemory(to: UInt8.self).baseAddress!
                    return cz_inflate(source, sourceBuffer.count, destination, outputBuffer.count, &produced)
                }
            }
            guard status == 0 else { throw ZipError.inflateFailed(status) }
            return output.prefix(Int(produced))
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
    }

    // MARK: - Central directory

    private static func readCentralDirectory(_ data: Data) throws -> [ZipEntry] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipError.notAnArchive }

        // The EOCD record is at the end, possibly followed by a comment of up to 64 KiB.
        var eocd = -1
        let lowerBound = max(0, bytes.count - 22 - 0xFFFF)
        var index = bytes.count - 22
        while index >= lowerBound {
            if readUInt32(bytes, index) == endOfCentralDirectorySignature {
                eocd = index
                break
            }
            index -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAnArchive }

        let entryCount = Int(readUInt16(bytes, eocd + 10))
        let directoryOffset = Int(readUInt32(bytes, eocd + 16))
        guard directoryOffset >= 0, directoryOffset <= bytes.count else {
            throw ZipError.corrupt("bad central directory offset")
        }

        var entries: [ZipEntry] = []
        entries.reserveCapacity(entryCount)
        var cursor = directoryOffset
        for _ in 0 ..< entryCount {
            guard cursor + 46 <= bytes.count else { break }
            guard readUInt32(bytes, cursor) == centralDirectorySignature else {
                throw ZipError.corrupt("bad central directory signature")
            }
            let method = readUInt16(bytes, cursor + 10)
            let crc = readUInt32(bytes, cursor + 16)
            let compressedSize = readUInt32(bytes, cursor + 20)
            let uncompressedSize = readUInt32(bytes, cursor + 24)
            let nameLength = Int(readUInt16(bytes, cursor + 28))
            let extraLength = Int(readUInt16(bytes, cursor + 30))
            let commentLength = Int(readUInt16(bytes, cursor + 32))
            let localOffset = readUInt32(bytes, cursor + 42)
            let nameStart = cursor + 46
            guard nameStart + nameLength <= bytes.count else { break }
            let nameData = Data(bytes[nameStart ..< (nameStart + nameLength)])
            let name = String(data: nameData, encoding: .utf8)
                ?? String(decoding: nameData, as: UTF8.self)
            entries.append(
                ZipEntry(
                    name: name,
                    method: method,
                    crc32: crc,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    localHeaderOffset: localOffset,
                    isDirectory: name.hasSuffix("/")
                )
            )
            cursor = nameStart + nameLength + extraLength + commentLength
        }
        return entries
    }

    // MARK: - Little endian helpers

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}
