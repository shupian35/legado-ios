//
//  ZipWriter.swift
//  LegadoCore
//
//  A minimal ZIP writer. `ZipArchive` only reads, but the book export
//  (TXT/EPUB) and the backup archive both need to write archives.
//
//  Why not Foundation: there is no public ZIP API on any Apple platform, and
//  the port must not depend on a third-party archiver. Every entry is stored
//  uncompressed, which is a valid ZIP (and the EPUB specification actually
//  requires the `mimetype` entry to be stored).
//

import Foundation
import CZlib

/// One entry of an archive.
public struct ZipWriteEntry: Equatable {
    /// The path inside the archive, using `/` separators.
    public let name: String
    /// The uncompressed payload.
    public let data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    public init(name: String, string: String) {
        self.init(name: name, data: Data(string.utf8))
    }
}

public enum ZipWriteError: Error, Equatable {
    /// An entry name is empty, or duplicates another entry.
    case invalidEntry(String)
}

/// Writes a ZIP archive (store method only).
public enum ZipWriter {

    /// Builds a ZIP archive from the entries, preserving their order.
    ///
    /// - Parameter entries: the entries; the first one should be `mimetype`
    ///   for an EPUB.
    /// - Returns: the archive bytes.
    public static func archive(_ entries: [ZipWriteEntry]) throws -> Data {
        var names = Set<String>()
        for entry in entries {
            guard !entry.name.isEmpty else {
                throw ZipWriteError.invalidEntry(entry.name)
            }
            guard names.insert(entry.name).inserted else {
                throw ZipWriteError.invalidEntry(entry.name)
            }
        }

        var output = Data()
        var central = Data()

        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            let payload = [UInt8](entry.data)
            let crc = cz_crc32(payload, payload.count)
            let offset = UInt32(output.count)

            // Local file header (APPNOTE 4.3.7).
            output.appendLE(UInt32(0x0403_4b50))          // signature
            output.appendLE(UInt16(20))                   // version needed
            output.appendLE(UInt16(0x0800))               // flags: UTF-8 name
            output.appendLE(UInt16(0))                    // method: store
            output.appendLE(UInt16(0))                    // mod time
            output.appendLE(UInt16(0x0021))               // mod date: 1980-01-01
            output.appendLE(crc)                          // crc-32
            output.appendLE(UInt32(payload.count))        // compressed size
            output.appendLE(UInt32(payload.count))        // uncompressed size
            output.appendLE(UInt16(nameBytes.count))      // name length
            output.appendLE(UInt16(0))                    // extra length
            output.append(contentsOf: nameBytes)
            output.append(contentsOf: payload)

            // Central directory record (APPNOTE 4.3.12).
            central.appendLE(UInt32(0x0201_4b50))         // signature
            central.appendLE(UInt16(20))                  // version made by
            central.appendLE(UInt16(20))                  // version needed
            central.appendLE(UInt16(0x0800))              // flags
            central.appendLE(UInt16(0))                   // method
            central.appendLE(UInt16(0))                   // mod time
            central.appendLE(UInt16(0x0021))              // mod date
            central.appendLE(crc)
            central.appendLE(UInt32(payload.count))
            central.appendLE(UInt32(payload.count))
            central.appendLE(UInt16(nameBytes.count))
            central.appendLE(UInt16(0))                   // extra length
            central.appendLE(UInt16(0))                   // comment length
            central.appendLE(UInt16(0))                   // disk number
            central.appendLE(UInt16(0))                   // internal attributes
            central.appendLE(UInt32(0))                   // external attributes
            central.appendLE(offset)                      // local header offset
            central.append(contentsOf: nameBytes)
        }

        let centralOffset = UInt32(output.count)
        output.append(central)

        // End of central directory (APPNOTE 4.3.16).
        output.appendLE(UInt32(0x0605_4b50))
        output.appendLE(UInt16(0))                        // this disk
        output.appendLE(UInt16(0))                        // central dir disk
        output.appendLE(UInt16(entries.count))            // entries on this disk
        output.appendLE(UInt16(entries.count))            // total entries
        output.appendLE(UInt32(central.count))            // central dir size
        output.appendLE(centralOffset)                    // central dir offset
        output.appendLE(UInt16(0))                        // comment length

        return output
    }
}

private extension Data {
    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
