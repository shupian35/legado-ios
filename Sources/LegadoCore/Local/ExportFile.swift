//
//  ExportFile.swift
//  LegadoCore
//
//  Writing an export to disk — the port of the file handling of
//  `service/ExportBookService.kt`.
//
//  The upstream writes the exported book into the folder the user picked
//  (`AppConfig.exportBookPath`), uploads it to the WebDAV `books/` folder
//  when `AppConfig.exportToWebDav` is on, and names the file with a
//  JavaScript template (`AppConfig.bookExportFileName`).
//
//  The port writes into the application documents directory (visible in the
//  Files app) and offers the share sheet, because an iOS application may
//  only write into its own container unless the user grants a folder
//  bookmark.
//

import Foundation

// MARK: - The character set

/// The character set of a TXT export — upstream `AppConfig.exportCharset`.
///
/// The upstream stores a free-form string that is handed to
/// `Charset.forName(...)`. The port offers the common ones and falls back
/// to UTF-8 when the platform cannot encode them (the Linux build has no
/// GBK encoder).
public enum ExportCharset: String, CaseIterable, Identifiable, Sendable {
    case utf8 = "UTF-8"
    case gbk = "GBK"
    case gb2312 = "GB2312"
    case gb18030 = "GB18030"
    case unicode = "Unicode"
    case utf16 = "UTF-16"
    case ascii = "ASCII"

    public var id: String { rawValue }

    /// Whether this platform can encode the charset.
    public var isSupported: Bool {
        switch self {
        case .utf8, .unicode, .utf16, .ascii:
            return true
        case .gbk, .gb2312, .gb18030:
            #if canImport(Darwin)
            return true
            #else
            return false
            #endif
        }
    }

    /// Encodes the text — the upstream's `bufferedWriter(charset)`.
    public func encode(_ text: String) -> Data {
        switch self {
        case .utf8:
            return Data(text.utf8)
        case .ascii:
            // The upstream's ASCII writer replaces every character it cannot
            // encode with a question mark (Java encodes per character, not
            // per byte).
            var scalars = String.UnicodeScalarView()
            for scalar in text.unicodeScalars {
                scalars.append(scalar.isASCII ? scalar : UnicodeScalar(63))
            }
            return Data(String(scalars).utf8)
        case .unicode, .utf16:
            // Java's "Unicode" is UTF-16 big endian.
            if let data = text.data(using: .utf16BigEndian) { return data }
            return Array(text.utf16).withUnsafeBytes { Data($0) }
        case .gbk, .gb2312, .gb18030:
            if let data = gb18030Data(text) { return data }
            return Data(text.utf8)
        }
    }

    #if canImport(Darwin)
    private func gb18030Data(_ text: String) -> Data? {
        let encoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        return text.data(using: encoding)
    }
    #else
    private func gb18030Data(_ text: String) -> Data? { nil }
    #endif
}

// MARK: - The written file

/// An export that has been written to disk.
public struct WrittenExport: Equatable {
    /// The name of the exported file.
    public let fileName: String
    /// Where the file was written.
    public let url: URL
    /// The sidecar images that were written next to it.
    public let imageURLs: [URL]

    public init(fileName: String, url: URL, imageURLs: [URL] = []) {
        self.fileName = fileName
        self.url = url
        self.imageURLs = imageURLs
    }
}

public enum ExportFileError: Error, Equatable {
    /// The export directory could not be created.
    case cannotCreateDirectory(String)
    /// The file could not be written.
    case cannotWrite(String)
}

// MARK: - The writer

/// Writes an export to disk — the file handling of
/// `service/ExportBookService.kt`.
public enum BookExportFileWriter {

    /// The name of the export folder inside the documents directory.
    public static let exportFolderName = "导出"

    /// The directory the exports are written into.
    ///
    /// The upstream uses the folder the user picked
    /// (`AppConfig.exportBookPath`); the port writes into its own documents
    /// directory, which the user can reach through the Files app (the
    /// information property list enables the file sharing).
    public static func exportDirectory(
        fileManager: FileManager = .default
    ) -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return documents.appendingPathComponent(exportFolderName, isDirectory: true)
    }

    /// Writes the exported file and its sidecar images.
    ///
    /// - Parameters:
    ///   - file: the exported book.
    ///   - images: the sidecar images of a TXT export.
    ///   - directory: where the export is written.
    ///   - charset: the character set of a TXT export.
    public static func write(
        file: ExportedFile,
        images: [ExportedImage] = [],
        to directory: URL,
        charset: ExportCharset = .utf8,
        fileManager: FileManager = .default
    ) throws -> WrittenExport {
        do {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            throw ExportFileError.cannotCreateDirectory(directory.path)
        }

        let target = directory.appendingPathComponent(sanitized(file.fileName))
        let data = file.fileName.lowercased().hasSuffix(".txt")
            ? charset.encode(String(decoding: file.data, as: UTF8.self))
            : file.data
        do {
            try data.write(to: target, options: .atomic)
        } catch {
            throw ExportFileError.cannotWrite(target.path)
        }

        var written: [URL] = []
        for image in images {
            let folder = directory.appendingPathComponent(
                image.directory,
                isDirectory: true
            )
            do {
                try fileManager.createDirectory(
                    at: folder,
                    withIntermediateDirectories: true
                )
                let url = folder.appendingPathComponent(sanitized(image.fileName))
                try image.data.write(to: url, options: .atomic)
                written.append(url)
            } catch {
                // A missing picture must not abort the export.
                continue
            }
        }
        return WrittenExport(fileName: target.lastPathComponent, url: target, imageURLs: written)
    }

    /// Removes the characters that a file name may not contain — the
    /// upstream's `normalizeFileName`.
    static func sanitized(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        let cleaned = name.unicodeScalars.map { scalar -> Character in
            illegal.contains(scalar) ? "_" : Character(String(scalar))
        }
        var result = String(cleaned)
        while result.hasSuffix(".") {
            result.removeLast()
        }
        return result.isEmpty ? "export" : result
    }
}

// MARK: - The file name template

/// The file name of an export — upstream `Book.getExportFileName(suffix)`.
///
/// The upstream evaluates `AppConfig.bookExportFileName` as JavaScript with
/// the bindings `name`, `author` and `epubIndex`; when the template is empty
/// or fails, the default `书名 作者：作者.suffix` is used.
public enum ExportFileName {

    /// The default name — upstream `"$name 作者：${getRealAuthor()}.$suffix"`.
    public static func defaultName(book: Book, suffix: String) -> String {
        "\(book.name) 作者：\(BookExporter.realAuthor(of: book)).\(suffix)"
    }

    /// The name of the export file.
    public static func name(
        book: Book,
        suffix: String,
        template: String?,
        epubIndex: Int = 0,
        engine: RuleScriptEngine? = nil
    ) -> String {
        let fallback = defaultName(book: book, suffix: suffix)
        guard let template, !template.trimmingCharacters(in: .whitespaces).isEmpty else {
            return fallback
        }
        guard let engine else { return fallback }
        let bindings: [String: RuleValue] = [
            "name": .text(book.name),
            "author": .text(BookExporter.realAuthor(of: book)),
            "epubIndex": .number(Double(epubIndex))
        ]
        guard let value = try? engine.evaluate(template, bindings: bindings) else {
            return fallback
        }
        let text = value.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return fallback }
        return text.hasSuffix(".\(suffix)") ? text : text + "." + suffix
    }
}
