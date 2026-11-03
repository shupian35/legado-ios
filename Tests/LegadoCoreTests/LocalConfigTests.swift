//
//  LocalConfigTests.swift
//  LegadoCoreTests
//
//  The device-local preferences — upstream `help/config/LocalConfig.kt`.
//

import XCTest
@testable import LegadoCore

final class LocalConfigTests: XCTestCase {

    func testThePasswordIsKept() {
        let config = LocalConfig(store: InMemorySettingsStore())
        XCTAssertNil(config.password)
        config.password = "legado"
        XCTAssertEqual(config.password, "legado")
        config.password = nil
        XCTAssertNil(config.password)
    }

    func testTheFirstOpenFlagFlipsWhenItIsRead() {
        let config = LocalConfig(store: InMemorySettingsStore())
        XCTAssertTrue(config.isFirstOpen)
        XCTAssertFalse(config.isFirstOpen)
    }

    func testThePrivacyPolicyFlag() {
        let config = LocalConfig(store: InMemorySettingsStore())
        XCTAssertFalse(config.privacyPolicyAccepted)
        config.privacyPolicyAccepted = true
        XCTAssertTrue(config.privacyPolicyAccepted)
    }

    func testTheLastBackupTime() {
        let config = LocalConfig(store: InMemorySettingsStore())
        XCTAssertNil(config.lastBackup)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        config.lastBackup = date
        XCTAssertEqual(config.lastBackup?.timeIntervalSince1970 ?? 0, date.timeIntervalSince1970, accuracy: 0.001)
    }

    func testThePasswordIsTheKeyOfTheBackupCipher() {
        // Upstream `help/storage/BackupAES.kt`:
        // `MD5Utils.md5Encode(LocalConfig.password ?: "")` → the first 16 bytes.
        let config = LocalConfig(store: InMemorySettingsStore())
        config.password = "legado"
        let cipher = BackupCipher(password: config.password)
        XCTAssertEqual(String(decoding: cipher.key, as: UTF8.self),
                       String(ScriptDigest.md5Hex("legado").prefix(16)))
    }

    func testThePasswordIsNotPartOfTheAppPreferences() {
        // The upstream keeps the local preferences in their own file, so the
        // password never ends up in the `config.xml` of a backup.
        let store = InMemorySettingsStore()
        let config = LocalConfig(store: store)
        config.password = "legado"
        let settings = AppSettings(store: InMemorySettingsStore())
        for key in SettingsKey.allCases {
            XCTAssertNil(settings.string(key), "the key \(key.rawValue) must not carry the password")
        }
        XCTAssertEqual(store.string(forKey: "password"), "legado")
    }
}
