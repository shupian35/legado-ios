//
//  ShareLayoutTests.swift
//  LegadoCoreTests
//
//  The shared layout — upstream `ReadBookConfig.shareLayout`.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/help/config/ReadBookConfig.kt
//

import XCTest
@testable import LegadoCore

final class ShareLayoutTests: XCTestCase {

    // MARK: - The export layout

    func testExportConfigTakesTheLayoutFromTheSharedLayout() {
        var current = ReaderConfig()
        current.textSize = 20
        current.titleSize = 24
        var share = ReaderConfig()
        share.textSize = 30
        share.titleSize = 34

        let export = ShareLayout.exportConfig(current: current, share: share)

        XCTAssertEqual(export.textSize, 30)
        XCTAssertEqual(export.titleSize, 34)
    }

    func testExportConfigKeepsTheCurrentLayoutWhenTheSharedLayoutIsOff() {
        var current = ReaderConfig()
        current.textSize = 20
        var share = ReaderConfig()
        share.textSize = 30

        let export = ShareLayout.exportConfig(current: current, share: share, enabled: false)

        XCTAssertEqual(export.textSize, 20)
    }

    func testExportConfigKeepsTheColoursOfTheSharedLayout() {
        var current = ReaderConfig()
        current.textColor = "#000000"
        var share = ReaderConfig()
        share.textColor = "#FFFFFF"

        let export = ShareLayout.exportConfig(current: current, share: share)

        XCTAssertEqual(export.textColor, "#FFFFFF")
    }

    // MARK: - The layout that is used

    func testEffectiveConfigIsTheCurrentOneWhenTheSharedLayoutIsOff() {
        var current = ReaderConfig()
        current.textSize = 20
        var share = ReaderConfig()
        share.textSize = 30

        let effective = ShareLayout.effective(current: current, share: share, enabled: false)

        XCTAssertEqual(effective.textSize, 20)
    }

    func testEffectiveConfigIsTheSharedOneWhenItIsOn() {
        var current = ReaderConfig()
        current.textSize = 20
        var share = ReaderConfig()
        share.textSize = 30

        let effective = ShareLayout.effective(current: current, share: share, enabled: true)

        XCTAssertEqual(effective.textSize, 30)
    }

    func testEffectiveConfigFallsBackToTheCurrentOneWithoutASharedLayout() {
        var current = ReaderConfig()
        current.textSize = 20

        let effective = ShareLayout.effective(current: current, share: nil, enabled: true)

        XCTAssertEqual(effective.textSize, 20)
    }

    // MARK: - The store

    func testTheSharedLayoutIsStoredUnderItsOwnKeys() {
        let settings = AppSettings(store: InMemorySettingsStore())
        let configStore = ReaderConfigStore(settings: settings)

        var share = ReaderConfig()
        share.textSize = 31
        share.titleSize = 35
        configStore.saveShare(share)

        let loaded = configStore.loadShare()
        XCTAssertEqual(loaded.textSize, 31)
        XCTAssertEqual(loaded.titleSize, 35)
    }

    func testTheSharedLayoutDoesNotChangeTheCurrentOne() {
        let settings = AppSettings(store: InMemorySettingsStore())
        let configStore = ReaderConfigStore(settings: settings)

        var current = ReaderConfig()
        current.textSize = 20
        configStore.save(current)

        var share = ReaderConfig()
        share.textSize = 30
        configStore.saveShare(share)

        XCTAssertEqual(configStore.load().textSize, 20)
        XCTAssertEqual(configStore.loadShare().textSize, 30)
    }

    func testTheSharedLayoutFallsBackToTheDefaults() {
        let settings = AppSettings(store: InMemorySettingsStore())
        let configStore = ReaderConfigStore(settings: settings)

        let loaded = configStore.loadShare()

        XCTAssertEqual(loaded.textSize, ReaderConfig().textSize)
        XCTAssertTrue(loaded.textFullJustify)
    }

    func testTheSharedLayoutSwitchIsStored() {
        let settings = AppSettings(store: InMemorySettingsStore())

        XCTAssertFalse(settings.shareLayout)
        settings.shareLayout = true
        XCTAssertTrue(settings.shareLayout)
    }

    func testTheFileNameOfTheSharedLayout() {
        XCTAssertEqual(ShareLayout.configFileName, "shareReadConfig.json")
    }
}
