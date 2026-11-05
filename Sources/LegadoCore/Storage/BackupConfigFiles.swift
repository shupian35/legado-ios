//
//  BackupConfigFiles.swift
//  LegadoCore
//
//  The configuration files that go into a backup beside the table dumps —
//  the port of the file list of the upstream `Backup.backupFileNames` and of
//  the restore of `Restore.restoreLocked`.
//
//  Upstream writes these files:
//
//  | file                      | content                                        |
//  |---------------------------|------------------------------------------------|
//  | `readConfig.json`         | the reader configuration (`ReadBookConfig`)    |
//  | `shareConfig.json`        | the shared layout (`ReadBookConfig`)           |
//  | `themeConfig.json`        | the themes (`ThemeConfig`)                     |
//  | `coverRule.json`          | the cover rule (`BookCover`)                   |
//  | `directLinkUploadRule.json`| the direct link upload rules (`DirectLinkUpload`)|
//
//  and restores them into their own files on a restore.
//

import Foundation

/// The configuration files of a backup.
public enum BackupConfigFiles {

    /// The name of the reader configuration file — upstream
    /// `ReadBookConfig.configFileName`.
    public static let readerConfigFileName = "readConfig.json"

    /// The name of the shared layout file — upstream
    /// `ReadBookConfig.shareConfigFileName`.
    public static let shareConfigFileName = "shareConfig.json"

    /// The name of the theme configuration file — upstream
    /// `ThemeConfig.configFileName`.
    public static let themeConfigFileName = "themeConfig.json"

    /// The name of the cover rule file — upstream `BookCover.configFileName`.
    public static let coverRuleFileName = "coverRule.json"

    /// The name of the direct link upload rule file — upstream
    /// `DirectLinkUpload.ruleFileName`.
    public static let directLinkUploadFileName = "directLinkUploadRule.json"

    /// Every configuration file a backup can carry.
    public static let allNames: [String] = [
        readerConfigFileName,
        shareConfigFileName,
        themeConfigFileName,
        coverRuleFileName,
        directLinkUploadFileName
    ]

    /// The configuration files of the application — the ones that go into a
    /// backup.
    ///
    /// - Parameters:
    ///   - readerConfig: the reader configuration (the background presets).
    ///   - themeConfig: the themes.
    ///   - coverRule: the cover rule.
    ///   - directLinkUpload: the direct link upload rule.
    public static func files(
        readerConfig: Data?,
        themeConfig: Data?,
        coverRule: String?,
        directLinkUpload: String?
    ) -> [BackupFile] {
        var result: [BackupFile] = []
        if let readerConfig { result.append(BackupFile(name: readerConfigFileName, data: readerConfig)) }
        if let themeConfig { result.append(BackupFile(name: themeConfigFileName, data: themeConfig)) }
        if let coverRule { result.append(BackupFile(name: coverRuleFileName, string: coverRule)) }
        if let directLinkUpload {
            result.append(BackupFile(name: directLinkUploadFileName, string: directLinkUpload))
        }
        return result
    }

    /// The configuration files of an archive, by name.
    ///
    /// Upstream `Restore.restoreLocked` picks the files it knows by name and
    /// restores every one of them; the port hands them to the application
    /// layer, which knows where they live.
    public static func files(in archive: BackupArchive) -> [String: BackupFile] {
        var result: [String: BackupFile] = [:]
        for file in archive.files where allNames.contains(file.name) {
            result[file.name] = file
        }
        return result
    }

    /// The configuration files of a zipped backup, by name.
    ///
    /// - Parameter data: the zipped backup.
    public static func files(inZipData data: Data) throws -> [String: BackupFile] {
        let archive = try ZipArchive(data: data)
        var contents: [BackupFile] = []
        for entry in archive.entries {
            contents.append(BackupFile(name: entry.name, data: try archive.data(for: entry)))
        }
        return files(in: BackupArchive(fileName: "", files: contents))
    }
}
