import XCTest
@testable import LegadoCore

/// The port of `help/storage/BackupConfig.kt` — the groups that a restore
/// skips.
final class BackupIgnoreConfigTests: XCTestCase {

    func testTheEightGroupsExist() {
        XCTAssertEqual(BackupIgnoreKey.allCases.count, 8)
        XCTAssertEqual(
            Set(BackupIgnoreKey.allCases.map { $0.rawValue }),
            ["readConfig", "themeMode", "themeConfig", "coverConfig",
             "bookshelfLayout", "showRss", "threadCount", "localBook"]
        )
    }

    func testTheGroupsHaveTitles() {
        for key in BackupIgnoreKey.allCases {
            XCTAssertFalse(key.title.isEmpty)
        }
    }

    func testNothingIsIgnoredByDefault() {
        let config = BackupIgnoreConfig()
        for key in BackupIgnoreKey.allCases {
            XCTAssertFalse(config.isIgnored(key))
        }
        XCTAssertTrue(config.shouldRestore(SettingsKey.themeMode.rawValue))
        XCTAssertTrue(config.shouldRestore(SettingsKey.readStyleSelect.rawValue))
    }

    func testTheAlwaysIgnoredPreferencesAreNeverRestored() {
        let config = BackupIgnoreConfig()
        for key in BackupIgnoreConfig.alwaysIgnoredKeys {
            XCTAssertFalse(config.shouldRestore(key), key)
        }
        XCTAssertTrue(BackupIgnoreConfig.alwaysIgnoredKeys.contains(SettingsKey.launcherIcon.rawValue))
        XCTAssertTrue(BackupIgnoreConfig.alwaysIgnoredKeys.contains(SettingsKey.backupPath.rawValue))
    }

    func testTheReadingPreferencesAreSkipped() {
        var config = BackupIgnoreConfig()
        config.set(true, for: .readConfig)
        XCTAssertTrue(config.isIgnored(.readConfig))
        XCTAssertFalse(config.shouldRestore(SettingsKey.readStyleSelect.rawValue))
        XCTAssertFalse(config.shouldRestore(SettingsKey.hideStatusBar.rawValue))
        XCTAssertFalse(config.shouldRestore(SettingsKey.clickActionMC.rawValue))
        // The preferences of the other groups are untouched.
        XCTAssertTrue(config.shouldRestore(SettingsKey.colorPrimary.rawValue))
        XCTAssertTrue(config.shouldRestore(SettingsKey.useDefaultCover.rawValue))
    }

    func testTheThemePreferencesAreSkipped() {
        var config = BackupIgnoreConfig()
        config.set(true, for: .themeConfig)
        XCTAssertFalse(config.shouldRestore(SettingsKey.colorPrimary.rawValue))
        XCTAssertFalse(config.shouldRestore(SettingsKey.colorAccentNight.rawValue))
        XCTAssertFalse(config.shouldRestore(SettingsKey.backgroundImage.rawValue))
        XCTAssertFalse(config.shouldRestore(SettingsKey.colorBottomBackgroundNight.rawValue))
        XCTAssertTrue(config.shouldRestore(SettingsKey.readStyleSelect.rawValue))
    }

    func testTheCoverPreferencesAreSkipped() {
        var config = BackupIgnoreConfig()
        config.set(true, for: .coverConfig)
        XCTAssertFalse(config.shouldRestore(SettingsKey.useDefaultCover.rawValue))
        XCTAssertFalse(config.shouldRestore(SettingsKey.loadCoverOnlyWifi.rawValue))
        XCTAssertFalse(config.shouldRestore(SettingsKey.coverShowNameN.rawValue))
        XCTAssertTrue(config.shouldRestore(SettingsKey.colorPrimary.rawValue))
    }

    func testTheSinglePreferencesAreSkipped() {
        var config = BackupIgnoreConfig()
        config.set(true, for: .themeMode)
        config.set(true, for: .bookshelfLayout)
        config.set(true, for: .showRss)
        config.set(true, for: .threadCount)
        XCTAssertFalse(config.shouldRestore(SettingsKey.themeMode.rawValue))
        XCTAssertFalse(config.shouldRestore(SettingsKey.bookshelfLayout.rawValue))
        XCTAssertFalse(config.shouldRestore(SettingsKey.showRss.rawValue))
        XCTAssertFalse(config.shouldRestore(SettingsKey.threadCount.rawValue))
    }

    func testTheConfigurationRoundTrip() {
        let store = InMemorySettingsStore()
        var config = BackupIgnoreConfig()
        config.set(true, for: .readConfig)
        config.set(true, for: .localBook)
        config.save(to: store)

        let loaded = BackupIgnoreConfig.load(from: store)
        XCTAssertTrue(loaded.isIgnored(.readConfig))
        XCTAssertTrue(loaded.isIgnored(.localBook))
        XCTAssertFalse(loaded.isIgnored(.coverConfig))
    }

    func testThePreferencesAreRestored() {
        let store = InMemorySettingsStore()
        var config = BackupIgnoreConfig()
        config.set(true, for: .readConfig)
        config.save(to: store)

        let applied = LegadoBackup.applyPreferences(
            [
                SettingsKey.readStyleSelect.rawValue: "3",
                SettingsKey.colorPrimary.rawValue: "112233",
                SettingsKey.launcherIcon.rawValue: "Launcher1"
            ],
            to: store,
            ignore: BackupIgnoreConfig.load(from: store)
        )
        XCTAssertEqual(applied, 1)
        XCTAssertNil(store.string(forKey: SettingsKey.readStyleSelect.rawValue))
        XCTAssertEqual(store.string(forKey: SettingsKey.colorPrimary.rawValue), "112233")
        XCTAssertNil(store.string(forKey: SettingsKey.launcherIcon.rawValue))
    }

    func testEveryPreferenceIsRestoredWithoutTheIgnoreList() {
        let store = InMemorySettingsStore()
        let applied = LegadoBackup.applyPreferences(
            [SettingsKey.readStyleSelect.rawValue: "3", SettingsKey.launcherIcon.rawValue: "Launcher1"],
            to: store,
            ignore: nil
        )
        XCTAssertEqual(applied, 2)
        XCTAssertEqual(store.string(forKey: SettingsKey.readStyleSelect.rawValue), "3")
        XCTAssertEqual(store.string(forKey: SettingsKey.launcherIcon.rawValue), "Launcher1")
    }
}
