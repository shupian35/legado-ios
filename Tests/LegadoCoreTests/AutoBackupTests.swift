//
//  AutoBackupTests.swift
//  LegadoCoreTests
//
//  The daily automatic backup — upstream `Backup.autoBack()` and
//  `AppWebDav.upBgs()`.
//

import XCTest
@testable import LegadoCore

final class AutoBackupTests: XCTestCase {

    // MARK: - shouldBackup

    func testABackupIsDueWithoutAPreviousOne() {
        XCTAssertTrue(AutoBackup.shouldBackup(lastBackup: nil))
    }

    func testABackupIsNotDueAfterOne() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertFalse(AutoBackup.shouldBackup(lastBackup: now, now: now))
    }

    func testABackupIsDueAfterADay() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // Upstream `lastBackup + TimeUnit.DAYS.toMillis(1) < now` — the
        // comparison is strict, so exactly a day is not enough.
        let yesterday = now.addingTimeInterval(-86_401)
        XCTAssertTrue(AutoBackup.shouldBackup(lastBackup: yesterday, now: now))
    }

    func testABackupIsNotDueExactlyAfterADay() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let yesterday = now.addingTimeInterval(-86_400)
        XCTAssertFalse(AutoBackup.shouldBackup(lastBackup: yesterday, now: now))
    }

    func testABackupIsNotDueJustBeforeADay() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let almost = now.addingTimeInterval(-86_399)
        XCTAssertFalse(AutoBackup.shouldBackup(lastBackup: almost, now: now))
    }

    // MARK: - backgroundImageNames

    func testOnlyTheUserImagesAreCollected() {
        let preset = ReaderBackgroundPreset(
            name: "测试",
            bgStr: "day.jpg",
            bgStrNight: "night.jpg",
            bgStrEInk: "eink.jpg",
            bgAlpha: 100,
            bgType: 2,
            bgTypeNight: 2,
            bgTypeEInk: 0,
            textColor: "#000000",
            textColorNight: "#FFFFFF",
            textColorEInk: "#000000"
        )
        XCTAssertEqual(
            AutoBackup.backgroundImageNames(presets: [preset]),
            ["day.jpg", "night.jpg"]
        )
    }

    func testNoBackgroundsForTheColourPresets() {
        let preset = ReaderBackgroundPreset()
        XCTAssertTrue(AutoBackup.backgroundImageNames(presets: [preset]).isEmpty)
    }

    func testTheBackgroundsOfEveryPresetAreCollected() {
        let first = ReaderBackgroundPreset(bgStr: "a.jpg", bgType: 2)
        let second = ReaderBackgroundPreset(bgStr: "b.jpg", bgType: 2)
        XCTAssertEqual(
            AutoBackup.backgroundImageNames(presets: [first, second]),
            ["a.jpg", "b.jpg"]
        )
    }

    // MARK: - pendingBackgrounds

    func testTheExistingBackgroundsAreNotUploadedAgain() {
        let local: [(name: String, data: Data)] = [
            ("a.jpg", Data([1])),
            ("b.jpg", Data([2]))
        ]
        let pending = AutoBackup.pendingBackgrounds(local: local, remote: ["a.jpg"])
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending.first?.name, "b.jpg")
    }

    func testEveryBackgroundIsPendingWhenTheServerIsEmpty() {
        let local: [(name: String, data: Data)] = [("a.jpg", Data([1]))]
        XCTAssertEqual(AutoBackup.pendingBackgrounds(local: local, remote: []).count, 1)
    }

    // MARK: - backgroundFiles

    func testTheBackgroundFilesAreReadFromTheBackgroundFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("auto-backup-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("bg", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([9, 9]).write(to: folder.appendingPathComponent("day.jpg"))

        let preset = ReaderBackgroundPreset(bgStr: "day.jpg", bgType: 2)
        let files = AutoBackup.backgroundFiles(presets: [preset], root: root)
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.name, "day.jpg")
        XCTAssertEqual(files.first?.data, Data([9, 9]))
    }

    func testAMissingBackgroundFileIsSkipped() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("auto-backup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let preset = ReaderBackgroundPreset(bgStr: "missing.jpg", bgType: 2)
        XCTAssertTrue(AutoBackup.backgroundFiles(presets: [preset], root: root).isEmpty)
    }

    func testTheSameBackgroundIsUploadedOnlyOnce() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("auto-backup-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("bg", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data([1]).write(to: folder.appendingPathComponent("day.jpg"))

        let preset = ReaderBackgroundPreset(bgStr: "day.jpg", bgType: 2, bgTypeNight: 2, bgTypeEInk: 2)
        let files = AutoBackup.backgroundFiles(presets: [preset], root: root)
        XCTAssertEqual(files.count, 1)
    }
}
