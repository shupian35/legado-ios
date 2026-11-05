//
//  WebFileBook.swift
//  LegadoCore
//
//  The books of a source that only offers a download service — upstream
//  `BookInfoViewModel.WebFile` and `BookInfoViewModel.loadWebFile`.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/info/BookInfoViewModel.kt:273-292
//  app/src/main/java/io/legado/app/ui/book/info/BookInfoViewModel.kt:509-527
//  app/src/main/java/io/legado/app/utils/UrlUtil.kt:138-169
//

import Foundation

/// A file that can be downloaded from a book — upstream
/// `BookInfoViewModel.WebFile`.
public struct WebFile: Equatable, Sendable, Identifiable {

    /// The address of the file.
    public let url: String

    /// The name of the file — upstream `WebFile.name`.
    public let name: String

    /// The identifier of the row.
    public var id: String { url }

    /// Creates a file.
    public init(url: String, name: String) {
        self.url = url
        self.name = name
    }

    /// The extension of the file — upstream `UrlUtil.getSuffix`.
    public var suffix: String {
        WebFileBook.suffix(of: name)
    }

    /// Whether the port can read the file — upstream
    /// `AppPattern.bookFileRegex` (txt, epub, umd, pdf, mobi, azw3, azw).
    public var isSupported: Bool {
        LocalBook.Format.supportedExtensions.contains(suffix.lowercased())
    }

    /// Whether the file is an archive of books — upstream
    /// `AppPattern.archiveFileRegex` (zip, rar, 7z).
    public var isSupportDecompress: Bool {
        FileAssociation.archiveExtensions.contains(suffix.lowercased())
    }
}

/// The files of a book that only offers a download service — upstream
/// `BookInfoViewModel.loadWebFile` and `UrlUtil`.
public enum WebFileBook {

    /// The suffixes the upstream refuses — upstream
    /// `UrlUtil.unExpectFileSuffixs` ("php", "html"): the file name is often
    /// in the query of the address.
    public static let unexpectedSuffixes = ["php", "html"]

    /// The files that can be downloaded for a book — upstream
    /// `BookInfoViewModel.loadWebFile`.
    ///
    /// - Parameters:
    ///   - book: the book (its name and its author name the file when the
    ///     address has no file name).
    ///   - urls: the addresses — upstream `book.downloadUrls`.
    ///   - type: the extension of the address — upstream `AnalyzeUrl.type`.
    public static func files(book: Book, urls: [String], type: String? = nil) -> [WebFile] {
        urls.map { url in
            WebFile(url: url, name: fileName(url: url, book: book, type: type))
        }
    }

    /// The name of a downloaded file — upstream `BookInfoViewModel.loadWebFile`.
    ///
    /// The upstream takes the name from the path of the address; when the path
    /// has no usable name the name of the book is used (upstream
    /// `"${fileNameNoExtension}.${analyzeUrl.type}"`).
    public static func fileName(url: String, book: Book, type: String? = nil) -> String {
        if let fromPath = fileNameFromPath(url) {
            return fromPath
        }
        let base = book.author.isEmpty ? book.name : "\(book.name) 作者：\(book.author)"
        var ext = type ?? ""
        if ext.isEmpty {
            ext = rawSuffix(of: url)
        }
        if ext.isEmpty {
            ext = "ext"
        }
        return "\(base).\(ext)"
    }

    /// The file name of the path of an address — upstream
    /// `UrlUtil.getFileNameFromPath`.
    ///
    /// The upstream only accepts a path whose last component has a legal
    /// suffix (up to five letters or digits) that is not one of the
    /// unexpected ones.
    public static func fileNameFromPath(_ url: String) -> String? {
        guard let parsed = URL(string: url) else { return nil }
        let path = parsed.path
        guard !path.isEmpty else { return nil }
        let ext = rawSuffix(of: path)
        guard !ext.isEmpty, !unexpectedSuffixes.contains(ext.lowercased()) else { return nil }
        let name = (path as NSString).lastPathComponent
        return name.isEmpty ? nil : name
    }

    /// The legal suffix of a string — upstream `UrlUtil.getSuffix`.
    ///
    /// The upstream accepts up to five letters or digits; anything else
    /// becomes "ext".
    public static func suffix(of text: String) -> String {
        let raw = rawSuffix(of: text)
        return raw.isEmpty ? "ext" : raw
    }

    /// The legal suffix of a string, or an empty string when there is none —
    /// upstream `UrlUtil.getSuffix(str, "")`.
    public static func rawSuffix(of text: String) -> String {
        let path = text
            .components(separatedBy: "/").last ?? text
        let withoutQuery = path
            .components(separatedBy: "?").first ?? path
        let withoutFragment = withoutQuery
            .components(separatedBy: "#").first ?? withoutQuery
        let ext = (withoutFragment as NSString).pathExtension
        guard !ext.isEmpty, ext.count <= 5 else { return "" }
        for character in ext.lowercased() {
            guard character.isLetter || character.isNumber else { return "" }
        }
        return ext
    }
}
