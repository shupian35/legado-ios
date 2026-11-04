//
//  DocumentExporter.swift
//  LegadoUI
//
//  The export of a document to a file.
//
//  Upstream the exports use `HandleFileContract` — a file picker that asks
//  the user where the file goes. iOS has no such picker for arbitrary
//  documents, so the port writes the file into the temporary directory and
//  hands it to the share sheet, which offers "Save to Files".
//
//  The same helper serves the book sources, the RSS sources, the replace
//  rules, the bookmarks and the TXT directory rules.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// Writes a document to a file that can be shared.
public enum DocumentExporter {

    /// Writes the data into the temporary directory and returns the URL.
    ///
    /// - Parameters:
    ///   - data: the bytes of the document.
    ///   - fileName: the name of the file (the upstream's
    ///     `HandleFileContract.FileData.fileName`).
    public static func write(_ data: Data, fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        try data.write(to: url)
        return url
    }

    /// Writes a text into the temporary directory and returns the URL.
    public static func write(_ text: String, fileName: String) throws -> URL {
        try write(Data(text.utf8), fileName: fileName)
    }
}
