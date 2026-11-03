//
//  ScriptDigest.swift
//  LegadoCore
//
//  A small pure-Swift MD5 implementation.
//
//  Upstream uses `org.apache.commons.codec.digest.DigestUtils.md5Hex` inside
//  `JsExtensions.kt` and `MD5Utils.md5Encode16` for chapter identifiers. The
//  port implements MD5 directly so the core has no platform dependency and
//  the behaviour can be unit tested on Linux CI as well.
//

import Foundation

/// MD5 message digest.
public enum ScriptDigest {
    /// The 64 round constants of the MD5 algorithm.
    private static let s: [UInt32] = [
        7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
        5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
        4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
        6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
    ]

    /// The binary integer parts of the sines of 1…64.
    private static let k: [UInt32] = (0..<64).map { index in
        UInt32(truncatingIfNeeded: Int64(abs(sin(Double(index + 1))) * 4_294_967_296.0))
    }

    /// The raw 16-byte digest of `data`.
    public static func md5(_ data: Data) -> [UInt8] {
        var a0: UInt32 = 0x6745_2301
        var b0: UInt32 = 0xefcd_ab89
        var c0: UInt32 = 0x98ba_dcfe
        var d0: UInt32 = 0x1032_5476

        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for index in 0..<8 {
            message.append(UInt8(truncatingIfNeeded: bitLength >> (8 * UInt64(index))))
        }

        var chunkStart = 0
        while chunkStart < message.count {
            var words = [UInt32](repeating: 0, count: 16)
            for index in 0..<16 {
                let offset = chunkStart + index * 4
                words[index] = UInt32(message[offset])
                    | (UInt32(message[offset + 1]) << 8)
                    | (UInt32(message[offset + 2]) << 16)
                    | (UInt32(message[offset + 3]) << 24)
            }

            var a = a0
            var b = b0
            var c = c0
            var d = d0

            for index in 0..<64 {
                var f: UInt32
                var g: Int
                switch index {
                case 0..<16:
                    f = (b & c) | (~b & d)
                    g = index
                case 16..<32:
                    f = (d & b) | (~d & c)
                    g = (5 * index + 1) % 16
                case 32..<48:
                    f = b ^ c ^ d
                    g = (3 * index + 5) % 16
                default:
                    f = c ^ (b | ~d)
                    g = (7 * index) % 16
                }
                f = f &+ a &+ k[index] &+ words[g]
                a = d
                d = c
                c = b
                b = b &+ rotateLeft(f, by: s[index])
            }

            a0 = a0 &+ a
            b0 = b0 &+ b
            c0 = c0 &+ c
            d0 = d0 &+ d
            chunkStart += 64
        }

        var digest = [UInt8]()
        digest.reserveCapacity(16)
        for word in [a0, b0, c0, d0] {
            digest.append(UInt8(truncatingIfNeeded: word))
            digest.append(UInt8(truncatingIfNeeded: word >> 8))
            digest.append(UInt8(truncatingIfNeeded: word >> 16))
            digest.append(UInt8(truncatingIfNeeded: word >> 24))
        }
        return digest
    }

    /// The lower-case hexadecimal digest of `data`.
    public static func md5Hex(_ data: Data) -> String {
        md5(data).map { String(format: "%02x", $0) }.joined()
    }

    /// The lower-case hexadecimal digest of `text`'s UTF-8 bytes.
    public static func md5Hex(_ text: String) -> String {
        md5Hex(Data(text.utf8))
    }

    /// Upstream `MD5Utils.md5Encode16` — the first 16 characters of the digest.
    public static func md5Encode16(_ text: String) -> String {
        String(md5Hex(text).prefix(16))
    }

    private static func rotateLeft(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value << amount) | (value >> (32 - amount))
    }
}
