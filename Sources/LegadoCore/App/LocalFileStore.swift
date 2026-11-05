//
//  LocalFileStore.swift
//  LegadoCore
//
//  Imports the files the user picks into the app's own directory.
//
//  The upstream Android app copies every picked image into its external files
//  directory under a hashed name — upstream `GroupEditDialog`:
//
//      val fileName = MD5Utils.md5Encode(tmp) + ".$suffix"
//      file = FileUtils.createFileIfNotExist(file, "covers", fileName)
//
//  iOS hands out security scoped URLs whose paths are temporary, so the port
//  copies the file the same way the upstream does and stores the path of the
//  copy.
//

import Foundation

public enum LocalFileStore {

    /// The error of a failed import.
    public enum ImportError: Error, LocalizedError {
        case unreadable
        case noDocumentsDirectory

        public var errorDescription: String? {
            switch self {
            case .unreadable:
                return "无法读取所选文件"
            case .noDocumentsDirectory:
                return "无法访问应用目录"
            }
        }
    }

    /// The directory the app stores its own files in.
    public static func documentsDirectory() throws -> URL {
        guard let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first else {
            throw ImportError.noDocumentsDirectory
        }
        return base
    }

    /// The cache directory of the app — upstream `context.cacheDir`.
    ///
    /// The audio of the HTTP TTS engine is cached in it
    /// (`cacheDir/httpTTS`).
    public static func cachesDirectory() throws -> URL {
        guard let base = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first else {
            throw ImportError.noDocumentsDirectory
        }
        return base
    }

    /// Copies the file at `url` into `<documents>/<directory>/<md5>.<suffix>`
    /// and returns the path of the copy.
    ///
    /// - Parameters:
    ///   - url: the file the user picked.
    ///   - directory: the sub directory of the documents directory — upstream
    ///     `FileUtils.createFileIfNotExist(file, "covers", fileName)`.
    public static func importFile(from url: URL, into directory: String) throws -> String {
        let data = try Data(contentsOf: url)
        return try importData(data, suffix: url.pathExtension, into: directory)
    }

    /// Writes `data` into `<documents>/<directory>/<md5>.<suffix>` and returns
    /// the path of the written file.
    public static func importData(
        _ data: Data,
        suffix: String,
        into directory: String
    ) throws -> String {
        let base = try documentsDirectory()
        let folder = base.appendingPathComponent(directory, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true
        )
        var name = ScriptDigest.md5Hex(data)
        if !suffix.isEmpty {
            name += ".\(suffix)"
        }
        let target = folder.appendingPathComponent(name)
        try data.write(to: target, options: .atomic)
        return target.path
    }

    /// Removes the file at `path` when it lives inside the documents
    /// directory — the helper behind "clear the cover".
    @discardableResult
    public static func removeFile(at path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        let url = URL(fileURLWithPath: path)
        guard let base = try? documentsDirectory() else { return false }
        let documents = base.standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(documents) else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            return false
        }
    }
}
