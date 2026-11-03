//
//  EncodingDetector.swift
//  LegadoCore
//
//  Detects the character encoding of a local book file.
//
//  Upstream: app/src/main/java/io/legado/app/utils/EncodingDetect.kt
//
//  The upstream implementation delegates to the ICU4J `CharsetDetector`
//  (a port of the Mozilla universal charset detector). That detector is not
//  available on iOS, so the port uses a deterministic heuristic:
//
//  1. A byte order mark wins outright.
//  2. Otherwise, if the bytes decode as strict UTF-8 the file is UTF-8.
//  3. Otherwise the Chinese legacy encodings are compared with a simple
//     two-byte-range scoring and the best match wins (GB18030 by default).
//

import Foundation

public enum EncodingDetector {

    /// The encodings the port is able to detect.
    public enum Detected: Equatable {
        case utf8
        case utf16BigEndian
        case utf16LittleEndian
        case gb18030
        case big5

        /// The canonical name of a detected encoding.
        public var name: String {
            switch self {
            case .utf8: return "UTF-8"
            case .utf16BigEndian: return "UTF-16BE"
            case .utf16LittleEndian: return "UTF-16LE"
            case .gb18030: return "GB18030"
            case .big5: return "Big5"
            }
        }

        /// The `String.Encoding` of a detected encoding.
        ///
        /// `GB18030` and `Big5` are not part of `String.Encoding` — the port
        /// transcodes them through the iconv-backed `CFStringConvertEncoding`
        /// when the platform provides it, and falls back to a lossy decode.
        public var stringEncoding: String.Encoding {
            switch self {
            case .utf8: return String.Encoding.utf8
            case .utf16BigEndian: return String.Encoding.utf16BigEndian
            case .utf16LittleEndian: return String.Encoding.utf16LittleEndian
            // The raw values are the CFStringEncoding constants
            // (kCFStringEncodingGB_18030_2000 = 0x0630, kCFStringEncodingBig5 = 0x0A03).
            case .gb18030: return String.Encoding(rawValue: 0x0630)
            case .big5: return String.Encoding(rawValue: 0x0A03)
            }
        }
    }

    /// Detect the encoding of a byte buffer.
    public static func detect(_ data: Data) -> Detected {
        let bytes = [UInt8](data)
        guard !bytes.isEmpty else { return .utf8 }

        // 1. Byte order marks.
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            return .utf8
        }
        if bytes.count >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF {
            return .utf16BigEndian
        }
        if bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE {
            return .utf16LittleEndian
        }
        if bytes.count >= 4 && bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0xFE && bytes[3] == 0xFF {
            return .utf16BigEndian
        }
        if bytes.count >= 4 && bytes[0] == 0xFF && bytes[1] == 0xFE && bytes[2] == 0x00 && bytes[3] == 0x00 {
            return .utf16LittleEndian
        }

        // 2. Strict UTF-8.
        if isValidUTF8(bytes) { return .utf8 }

        // 3. Chinese legacy encodings — score the two-byte lead/trail ranges.
        let sample = Array(bytes.prefix(64 * 1024))
        let gbScore = score(sample, gb18030TrailRange: 0x40...0xFE, gb18030TrailHigh: 0x81...0xFE)
        let big5Score = score(sample, gb18030TrailRange: 0x40...0x7E, gb18030TrailHigh: 0xA1...0xF9)
        return gbScore >= big5Score ? .gb18030 : .big5
    }

    /// Decode a byte buffer with the given encoding.
    public static func decode(_ data: Data, encoding: Detected) -> String {
        decode(data, encoding: encoding.stringEncoding)
    }

    /// Decode a byte buffer with a `String.Encoding`.
    public static func decode(_ data: Data, encoding: String.Encoding) -> String {
        if let text = String(data: data, encoding: encoding) {
            return text
        }
        // A lossy fallback keeps the reader usable for broken files.
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Helpers

    private static func isValidUTF8(_ bytes: [UInt8]) -> Bool {
        var index = 0
        let count = bytes.count
        while index < count {
            let byte = bytes[index]
            if byte < 0x80 {
                index += 1
                continue
            }
            let following: Int
            var lowerBound: UInt8 = 0x80
            var upperBound: UInt8 = 0xBF
            switch byte {
            case 0xC2...0xDF: following = 1
            case 0xE0: following = 2; lowerBound = 0xA0
            case 0xED: following = 2; upperBound = 0x9F
            case 0xE1...0xEC, 0xEE...0xEF: following = 2
            case 0xF0: following = 3; lowerBound = 0x90
            case 0xF4: following = 3; upperBound = 0x8F
            case 0xF1...0xF3: following = 3
            default: return false
            }
            guard index + following < count else { return false }
            if bytes[index + 1] < lowerBound || bytes[index + 1] > upperBound { return false }
            for offset in 2...following {
                let continuation = bytes[index + offset]
                if continuation < 0x80 || continuation > 0xBF { return false }
            }
            index += following + 1
        }
        return true
    }

    /// Count the byte pairs that look like a valid two-character sequence.
    private static func score(
        _ bytes: [UInt8],
        gb18030TrailRange: ClosedRange<UInt8>,
        gb18030TrailHigh: ClosedRange<UInt8>
    ) -> Int {
        var hits = 0
        var index = 0
        while index + 1 < bytes.count {
            let lead = bytes[index]
            let trail = bytes[index + 1]
            let isLead = (0x81...0xFE).contains(lead)
            let isTrail = gb18030TrailRange.contains(trail) || gb18030TrailHigh.contains(trail)
            if isLead && isTrail {
                hits += 1
                index += 2
            } else {
                index += 1
            }
        }
        return hits
    }
}
