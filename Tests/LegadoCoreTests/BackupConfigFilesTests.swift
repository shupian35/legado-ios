//
//  BackupConfigFilesTests.swift
//  LegadoCoreTests
//
//  The configuration files of a backup — upstream `Backup.backup()` writes
//  them beside the table dumps and `Restore.restoreLocked` puts them back.
//

import XCTest
@testable import LegadoCore

final class BackupConfigFilesTests: XCTestCase {

    // MARK: - The file names

    func testTheFileNamesAreTheUpstreamOnes() {
        XCTAssertEqual(BackupConfigFiles.readerConfigFileName, "readConfig.json")
        XCTAssertEqual(BackupConfigFiles.shareConfigFileName, "shareConfig.json")
        XCTAssertEqual(BackupConfigFiles.themeConfigFileName, "themeConfig.json")
        XCTAssertEqual(BackupConfigFiles.coverRuleFileName, "coverRule.json")
        XCTAssertEqual(BackupConfigFiles.directLinkUploadFileName, "directLinkUploadRule.json")
    }

    func testEveryFileNameIsListed() {
        XCTAssertEqual(BackupConfigFiles.allNames.count, 5)
        XCTAssertTrue(BackupConfigFiles.allNames.contains("readConfig.json"))
        XCTAssertTrue(BackupConfigFiles.allNames.contains("themeConfig.json"))
        XCTAssertTrue(BackupConfigFiles.allNames.contains("coverRule.json"))
        XCTAssertTrue(BackupConfigFiles.allNames.contains("directLinkUploadRule.json"))
    }

    // MARK: - Collecting the files

    func testTheFilesAreCollected() {
        let files = BackupConfigFiles.files(
            readerConfig: Data("[{}]".utf8),
            themeConfig: Data("[]".utf8),
            coverRule: "{\"enable\":true}",
            directLinkUpload: "{\"summary\":\"x\"}"
        )
        XCTAssertEqual(files.count, 4)
        XCTAssertEqual(files.map { $0.name }, [
            "readConfig.json",
            "themeConfig.json",
            "coverRule.json",
            "directLinkUploadRule.json"
        ])
    }

    func testTheMissingFilesAreLeftOut() {
        let files = BackupConfigFiles.files(
            readerConfig: nil,
            themeConfig: nil,
            coverRule: nil,
            directLinkUpload: nil
        )
        XCTAssertTrue(files.isEmpty)
    }

    func testTheCoverRuleKeepsItsText() {
        let files = BackupConfigFiles.files(
            readerConfig: nil,
            themeConfig: nil,
            coverRule: "{\"enable\":false}",
            directLinkUpload: nil
        )
        XCTAssertEqual(files.first?.string, "{\"enable\":false}")
    }

    // MARK: - Reading the files back

    func testOnlyTheKnownFilesArePicked() {
        let archive = BackupArchive(fileName: "b.zip", files: [
            BackupFile(name: "readConfig.json", string: "[]"),
            BackupFile(name: "books.json", string: "[]"),
            BackupFile(name: "random.txt", string: "x")
        ])
        let files = BackupConfigFiles.files(in: archive)
        XCTAssertEqual(files.count, 1)
        XCTAssertNotNil(files["readConfig.json"])
    }

    func testTheFilesAreReadOutOfAZip() throws {
        let archive = BackupArchive(fileName: "b.zip", files: [
            BackupFile(name: "readConfig.json", string: "[]"),
            BackupFile(name: "themeConfig.json", string: "[]")
        ])
        let files = try BackupConfigFiles.files(inZipData: archive.zip())
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files["themeConfig.json"]?.string, "[]")
    }

    // MARK: - The managers pick the files up again

    func testTheBackgroundManagerReloadsItsFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("readConfig-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = ReaderBackgroundManager(fileURL: url)
        XCTAssertEqual(manager.presets.count, 1)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let presets = [
            ReaderBackgroundPreset.weixinRead,
            ReaderBackgroundPreset(name: "水墨", bgStr: "#FFFFFF", bgType: 1)
        ]
        try encoder.encode(presets).write(to: url)

        XCTAssertTrue(manager.reload())
        XCTAssertEqual(manager.presets.count, 2)
    }

    func testTheThemeManagerReloadsItsFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("themeConfig-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }

        let manager = ThemeManager(fileURL: url)
        XCTAssertEqual(manager.themes.count, AppTheme.defaults.count)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode([AppTheme.defaults[0]]).write(to: url)

        XCTAssertTrue(manager.reload())
        XCTAssertEqual(manager.themes.count, 1)
    }
}
