//
//  Images.swift
//  LegadoCore
//
//  The inline images of a chapter — the port of the upstream's
//  `AppPattern.imgPattern` handling in `ChapterProvider.setTypeImage` and of
//  `ImageProvider.getImageSize`.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/ChapterProvider.kt:200-463
//  app/src/main/java/io/legado/app/constant/AppPattern.kt:12
//  app/src/main/java/io/legado/app/help/ImageProvider.kt
//

import Foundation

/// One inline image of a chapter.
///
/// The upstream keeps the `src` of the image in the `ImageColumn` and asks
/// `ImageProvider` for the size and the bytes when the page is drawn. The port
/// resolves the image before the layout (the layout is synchronous), so the
/// size and the bytes travel with the image.
public struct ReaderImage: Equatable, Sendable {
    /// The absolute URL (or the local path) of the image.
    public var src: String
    /// The natural size of the image in points.
    public var size: CGSizeLike
    /// The bytes of the image — `nil` when only the size is known.
    public var data: Data?

    public init(src: String, size: CGSizeLike, data: Data? = nil) {
        self.src = src
        self.size = size
        self.data = data
    }
}

/// The size of an image, sniffed from its bytes.
///
/// The upstream uses Glide (`ImageProvider.getImageSize`) and therefore has to
/// download the image before the layout. The port sniffs the header of the
/// common formats, which needs no image decoder and therefore works on every
/// platform (including Linux, where the Core is built).
public enum ImageSizeDetector {

    /// The size of the image, or `nil` when the format is unknown.
    public static func size(of data: Data) -> CGSizeLike? {
        let bytes = [UInt8](data)
        // Every format checks its own minimum length below.
        guard bytes.count >= 4 else { return nil }
        if isPNG(bytes) { return pngSize(bytes) }
        if isGIF(bytes) { return gifSize(bytes) }
        if isJPEG(bytes) { return jpegSize(bytes) }
        if isWebP(bytes) { return webPSize(bytes) }
        if isBMP(bytes) { return bmpSize(bytes) }
        return nil
    }

    // MARK: - PNG

    private static func isPNG(_ bytes: [UInt8]) -> Bool {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count >= 24 else { return false }
        for (index, byte) in signature.enumerated() where bytes[index] != byte {
            return false
        }
        return true
    }

    private static func pngSize(_ bytes: [UInt8]) -> CGSizeLike? {
        // The IHDR chunk: the width at 16...20, the height at 20...24.
        CGSizeLike(
            width: Double(beUInt32(bytes, 16)),
            height: Double(beUInt32(bytes, 20))
        )
    }

    // MARK: - GIF

    private static func isGIF(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 10 else { return false }
        let head = String(bytes: bytes[0..<6], encoding: .ascii) ?? ""
        return head == "GIF87a" || head == "GIF89a"
    }

    private static func gifSize(_ bytes: [UInt8]) -> CGSizeLike? {
        CGSizeLike(
            width: Double(leUInt16(bytes, 6)),
            height: Double(leUInt16(bytes, 8))
        )
    }

    // MARK: - JPEG

    private static func isJPEG(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 4 && bytes[0] == 0xFF && bytes[1] == 0xD8
    }

    private static func jpegSize(_ bytes: [UInt8]) -> CGSizeLike? {
        var index = 2
        while index + 9 < bytes.count {
            // Every marker starts with 0xFF.
            guard bytes[index] == 0xFF else {
                index += 1
                continue
            }
            var marker = bytes[index + 1]
            // The fill bytes 0xFF may repeat.
            var cursor = index + 1
            while marker == 0xFF, cursor + 1 < bytes.count {
                cursor += 1
                marker = bytes[cursor]
            }
            // The standalone markers carry no length.
            if marker == 0xD8 || marker == 0x01 || (0xD0...0xD9).contains(marker) {
                index = cursor + 1
                continue
            }
            // The layout of a segment: the marker byte at `cursor`, the length
            // at `cursor + 1` and `cursor + 2` (the length counts itself).
            guard cursor + 3 <= bytes.count else { return nil }
            let length = Int(beUInt16(bytes, cursor + 1))
            // The SOFn markers carry the size: the height at +4, the width at
            // +6 (the precision is at +3).
            let isSOFn = (0xC0...0xCF).contains(marker)
                && marker != 0xC4 && marker != 0xC8 && marker != 0xCC
            if isSOFn, cursor + 8 <= bytes.count {
                return CGSizeLike(
                    width: Double(beUInt16(bytes, cursor + 6)),
                    height: Double(beUInt16(bytes, cursor + 4))
                )
            }
            guard length >= 2 else { return nil }
            index = cursor + 1 + length
        }
        return nil
    }

    // MARK: - WebP

    private static func isWebP(_ bytes: [UInt8]) -> Bool {
        guard bytes.count >= 16 else { return false }
        let riff = String(bytes: bytes[0..<4], encoding: .ascii) ?? ""
        let webp = String(bytes: bytes[8..<12], encoding: .ascii) ?? ""
        return riff == "RIFF" && webp == "WEBP"
    }

    private static func webPSize(_ bytes: [UInt8]) -> CGSizeLike? {
        let chunk = String(bytes: bytes[12..<16], encoding: .ascii) ?? ""
        switch chunk {
        case "VP8 ":
            // The lossy frame header: the width at 26, the height at 28.
            guard bytes.count >= 30 else { return nil }
            let width = Double(leUInt16(bytes, 26) & 0x3FFF)
            let height = Double(leUInt16(bytes, 28) & 0x3FFF)
            return CGSizeLike(width: width, height: height)
        case "VP8L":
            // The lossless header: the 32 bits at 20 hold the signature
            // (8 bits), the width-1 (14 bits), the height-1 (14 bits) and
            // the alpha flag.
            guard bytes.count >= 25 else { return nil }
            let bits = leUInt32(bytes, 20)
            let width = Double((bits >> 8) & 0x3FFF) + 1
            let height = Double((bits >> 22) & 0x3FFF) + 1
            return CGSizeLike(width: width, height: height)
        case "VP8X":
            // The canvas size: the width-1 at 24 (24 bits), the height-1 at 27.
            guard bytes.count >= 30 else { return nil }
            let width = Double(bytes[24] | (bytes[25] << 8) | (bytes[26] << 16)) + 1
            let height = Double(bytes[27] | (bytes[28] << 8) | (bytes[29] << 16)) + 1
            return CGSizeLike(width: width, height: height)
        default:
            return nil
        }
    }

    // MARK: - BMP

    private static func isBMP(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 26 && bytes[0] == 0x42 && bytes[1] == 0x4D
    }

    private static func bmpSize(_ bytes: [UInt8]) -> CGSizeLike? {
        CGSizeLike(
            width: Double(leUInt32(bytes, 18)),
            height: Double(leUInt32(bytes, 22))
        )
    }

    // MARK: - Byte helpers

    private static func beUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func beUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private static func leUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func leUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

/// The inline images of a chapter — the port of the upstream's split of the
/// content on `AppPattern.imgPattern` (`ChapterProvider.kt:230-264`).
public enum ChapterImageSplitter {

    /// One piece of the chapter content.
    public enum Segment: Equatable, Sendable {
        /// A piece of text.
        case text(String)
        /// The `src` of an image.
        case image(String)
    }

    /// Splits the content into its text and image segments.
    ///
    /// The upstream keeps the raw `src` of the tag (the group 1 of
    /// `AppPattern.imgPattern`); the caller resolves it against the chapter
    /// URL.
    public static func split(_ content: String) -> [Segment] {
        var segments: [Segment] = []
        let ns = content as NSString
        let matches = RulePatterns.compiledImgPattern.matches(
            in: content,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        )
        var start = 0
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            if match.range.location > start {
                segments.append(.text(ns.substring(with: NSRange(
                    location: start,
                    length: match.range.location - start
                ))))
            }
            let src = ns.substring(with: match.range(at: 1))
            segments.append(.image(src))
            start = match.range.location + match.range.length
        }
        if start < ns.length {
            segments.append(.text(ns.substring(from: start)))
        }
        return segments
    }

    /// The `src` of every image of the content, in order.
    public static func sources(in content: String) -> [String] {
        split(content).compactMap { segment in
            if case .image(let src) = segment { return src }
            return nil
        }
    }

    /// Replaces every image with the placeholder character — the upstream's
    /// `imgStyleText` (the image is embedded in the text).
    public static func textEmbedded(_ content: String, placeholder: String = "▣") -> String {
        var result = ""
        var start = 0
        let ns = content as NSString
        let matches = RulePatterns.compiledImgPattern.matches(
            in: content,
            options: [],
            range: NSRange(location: 0, length: ns.length)
        )
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            result += ns.substring(with: NSRange(location: start, length: match.range.location - start))
            result += placeholder
            start = match.range.location + match.range.length
        }
        result += ns.substring(from: start)
        return result
    }
}
