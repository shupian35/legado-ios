//
//  Multipart.swift
//  LegadoServer
//
//  A minimal `multipart/form-data` parser.
//
//  The upstream upload page (`app/src/main/assets/web/uploadBook/index.html`)
//  posts the book file as the `fileData` part and the file name as the
//  `fileName` field, so the local API has to understand the multipart body.
//

import Foundation

/// One part of a `multipart/form-data` body.
public struct MultipartPart: Equatable, Sendable {
    /// The `name` attribute of the part's `Content-Disposition` header.
    public let name: String
    /// The `filename` attribute of the part's `Content-Disposition` header.
    public let fileName: String?
    /// The `Content-Type` of the part (nil for a plain field).
    public let contentType: String?
    /// The raw bytes of the part.
    public let data: Data

    public init(name: String, fileName: String? = nil, contentType: String? = nil, data: Data) {
        self.name = name
        self.fileName = fileName
        self.contentType = contentType
        self.data = data
    }

    /// The part decoded as UTF-8 text.
    public var text: String {
        String(decoding: data, as: UTF8.self)
    }
}

public enum MultipartError: Error, Equatable {
    case missingBoundary
    case malformed
}

public enum MultipartParser {
    /// Parses a `multipart/form-data` body.
    ///
    /// - Parameters:
    ///   - body: the raw request body.
    ///   - contentType: the `Content-Type` header (the boundary is taken from it).
    public static func parse(body: Data, contentType: String?) throws -> [MultipartPart] {
        guard let boundary = boundary(in: contentType) else {
            throw MultipartError.missingBoundary
        }
        let delimiter = Data("--\(boundary)".utf8)
        let separator = Data("\r\n\r\n".utf8)
        let closing = Data("--\(boundary)--".utf8)

        var parts: [MultipartPart] = []
        var searchStart = body.startIndex

        // Find the first delimiter.
        guard let first = body.range(of: delimiter, in: searchStart..<body.endIndex) else {
            throw MultipartError.malformed
        }
        searchStart = first.upperBound

        while searchStart < body.endIndex {
            // The closing delimiter ends the body.
            if body.range(of: closing, in: searchStart..<body.endIndex)?.lowerBound == searchStart {
                break
            }
            guard let next = body.range(of: delimiter, in: searchStart..<body.endIndex) else {
                throw MultipartError.malformed
            }
            // The part is between the header block and the delimiter; the
            // trailing CRLF belongs to the delimiter.
            var end = next.lowerBound
            if end > body.startIndex, body[body.index(before: end)] == 0x0A,
               body[body.index(before: body.index(before: end))] == 0x0D {
                end = body.index(before: body.index(before: end))
            }
            guard let headerRange = body.range(of: separator, in: searchStart..<end) else {
                throw MultipartError.malformed
            }
            let headerText = String(decoding: body[searchStart..<headerRange.lowerBound], as: UTF8.self)
            let payload = body[headerRange.upperBound..<end]
            parts.append(part(headerText: headerText, data: Data(payload)))
            // `--` after the delimiter marks the end of the body.
            let after = next.upperBound
            if after + 1 < body.endIndex, body[after] == 0x2D, body[after + 1] == 0x2D {
                break
            }
            searchStart = after
            // Skip the CRLF after the delimiter.
            if searchStart + 1 < body.endIndex,
               body[searchStart] == 0x0D, body[searchStart + 1] == 0x0A {
                searchStart += 2
            }
        }
        return parts
    }

    /// The boundary of a `multipart/form-data` content type.
    public static func boundary(in contentType: String?) -> String? {
        guard let contentType else { return nil }
        let lower = contentType.lowercased()
        guard lower.contains("multipart/form-data") else { return nil }
        for component in contentType.split(separator: ";").dropFirst() {
            let trimmed = component.trimmingCharacters(in: .whitespaces)
            guard trimmed.lowercased().hasPrefix("boundary=") else { continue }
            var value = String(trimmed.dropFirst("boundary=".count))
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func part(headerText: String, data: Data) -> MultipartPart {
        var name = ""
        var fileName: String?
        var contentType: String?
        for line in headerText.split(separator: "\r\n", omittingEmptySubsequences: true) {
            let lower = line.lowercased()
            if lower.hasPrefix("content-disposition:") {
                name = attribute("name", in: String(line)) ?? ""
                fileName = attribute("filename", in: String(line))
            } else if lower.hasPrefix("content-type:") {
                contentType = String(line.dropFirst("content-type:".count))
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return MultipartPart(name: name, fileName: fileName, contentType: contentType, data: data)
    }

    private static func attribute(_ key: String, in value: String) -> String? {
        let needle = "\(key)="
        guard let range = value.range(of: needle, options: .caseInsensitive) else { return nil }
        var result = String(value[range.upperBound...])
        if result.hasPrefix("\"") {
            result.removeFirst()
            if let end = result.firstIndex(of: "\"") {
                result = String(result[..<end])
            }
        } else {
            if let semicolon = result.firstIndex(of: ";") {
                result = String(result[..<semicolon])
            }
        }
        let trimmed = result.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
