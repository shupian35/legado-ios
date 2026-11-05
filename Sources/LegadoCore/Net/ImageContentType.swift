//
//  ImageContentType.swift
//  LegadoCore
//
//  The content type of an image.
//
//  Upstream `web/HttpServer.kt:103-114` converts every bitmap into a PNG
//  before it sends it, so `/cover` and `/image` always answer with
//  `image/png`. The port serves the ORIGINAL bytes (the cover of a book is
//  usually a JPEG), so it has to tell the browser what it actually got —
//  otherwise the browser refuses to render the picture.
//
//  The detection looks at the header of the file, the same way
//  `Reader/Images.swift` reads the size of an image.
//

import Foundation

/// The content type of an image.
public enum ImageContentType {

    public static let png = "image/png"
    public static let jpeg = "image/jpeg"
    public static let gif = "image/gif"
    public static let webp = "image/webp"
    public static let bmp = "image/bmp"
    public static let svg = "image/svg+xml"
    /// The type of an image the port cannot recognise.
    public static let unknown = "application/octet-stream"

    /// Detects the content type of the bytes of an image.
    ///
    /// - Parameter data: the bytes of the image.
    /// - Returns: the MIME type — `application/octet-stream` when the bytes
    ///   are not a known image format.
    public static func detect(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(16))
        guard bytes.count >= 4 else { return unknown }
        // PNG — "\x89PNG"
        if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 {
            return png
        }
        // JPEG — "\xFF\xD8"
        if bytes[0] == 0xFF && bytes[1] == 0xD8 {
            return jpeg
        }
        // GIF — "GIF8"
        if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 {
            return gif
        }
        // BMP — "BM"
        if bytes[0] == 0x42 && bytes[1] == 0x4D {
            return bmp
        }
        // WebP — "RIFF????WEBP"
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return webp
        }
        // The SVG files are text.
        if let text = String(data: data.prefix(512), encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<svg") {
                return svg
            }
        }
        return unknown
    }
}
