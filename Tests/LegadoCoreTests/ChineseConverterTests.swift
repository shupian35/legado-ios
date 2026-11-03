//
//  ChineseConverterTests.swift
//  LegadoCoreTests
//

import XCTest
@testable import LegadoCore

final class ChineseConverterTests: XCTestCase {

    // MARK: - Traditional → simplified

    func testTraditionalIsConvertedToSimplified() {
        XCTAssertEqual(ChineseConverter.toSimplified("這是一個測試"), "这是一个测试")
        XCTAssertEqual(ChineseConverter.toSimplified("龍"), "龙")
        XCTAssertEqual(ChineseConverter.toSimplified("書"), "书")
    }

    func testSimplifiedTextIsUnchangedByTheSimplifiedDirection() {
        XCTAssertEqual(ChineseConverter.toSimplified("这是一个测试"), "这是一个测试")
    }

    func testTheLatinTextIsUntouched() {
        XCTAssertEqual(ChineseConverter.toSimplified("Hello 世界 123"), "Hello 世界 123")
        XCTAssertEqual(ChineseConverter.toTraditional("Hello 世界 123"), "Hello 世界 123")
    }

    // MARK: - Simplified → traditional

    func testSimplifiedIsConvertedToTraditional() {
        XCTAssertEqual(ChineseConverter.toTraditional("这是一个测试"), "這是一個測試")
        XCTAssertEqual(ChineseConverter.toTraditional("龙"), "龍")
        XCTAssertEqual(ChineseConverter.toTraditional("书"), "書")
    }

    // MARK: - The excluded words

    func testTheExcludedWordsAreNotConverted() {
        // Upstream `ChineseUtils.fixT2sDict` keeps these words as they are.
        XCTAssertEqual(ChineseConverter.toSimplified("华乐"), "华乐")
        XCTAssertEqual(ChineseConverter.toSimplified("载入"), "载入")
        XCTAssertEqual(ChineseConverter.toSimplified("菲林"), "菲林")
        XCTAssertEqual(ChineseConverter.toSimplified("房价"), "房价")
        XCTAssertEqual(ChineseConverter.toSimplified("巨集"), "巨集")
        XCTAssertEqual(ChineseConverter.toSimplified("酵素"), "酵素")
        XCTAssertEqual(ChineseConverter.toSimplified("變數"), "變數")
    }

    func testOnlyTheExcludedOccurrenceIsProtected() {
        // The same character outside the word is converted.
        XCTAssertEqual(ChineseConverter.toSimplified("载"), "载")
        XCTAssertEqual(ChineseConverter.toSimplified("载入"), "载入")
        XCTAssertEqual(ChineseConverter.toSimplified("载入之后"), "载入之后")
    }

    func testTheExcludeListIsTheUpstreamList() {
        XCTAssertTrue(ChineseConverter.excludedTraditionalWords.contains("华乐"))
        XCTAssertTrue(ChineseConverter.excludedTraditionalWords.contains("奇幻魔法Melody"))
        XCTAssertEqual(ChineseConverter.excludedTraditionalWords.count, 112)
    }

    // MARK: - The mode

    func testTheModeSelectsTheDirection() {
        XCTAssertEqual(
            ChineseConverter.convert("测试", mode: .off),
            "测试"
        )
        XCTAssertEqual(
            ChineseConverter.convert("測試", mode: .traditionalToSimplified),
            "测试"
        )
        XCTAssertEqual(
            ChineseConverter.convert("测试", mode: .simplifiedToTraditional),
            "測試"
        )
    }

    func testTheModeValuesMatchTheUpstreamPreference() {
        XCTAssertEqual(ChineseConversionMode.off.rawValue, 0)
        XCTAssertEqual(ChineseConversionMode.traditionalToSimplified.rawValue, 1)
        XCTAssertEqual(ChineseConversionMode.simplifiedToTraditional.rawValue, 2)
    }

    // MARK: - The protocol conformance

    func testTheDefaultConverterUsesTheTables() {
        let converter = DefaultChineseConverter()
        XCTAssertEqual(converter.toSimplified("測試"), "测试")
        XCTAssertEqual(converter.toTraditional("测试"), "測試")
    }

    // MARK: - The table

    func testTheTableHasBothDirections() {
        XCTAssertGreaterThan(ChineseCharacters.traditionalToSimplifiedSource.count, 3000)
        XCTAssertGreaterThan(ChineseCharacters.simplifiedToTraditionalSource.count, 3000)
        XCTAssertEqual(
            ChineseCharacters.traditionalToSimplifiedSource.count,
            ChineseCharacters.traditionalToSimplifiedTarget.count
        )
        XCTAssertEqual(
            ChineseCharacters.simplifiedToTraditionalSource.count,
            ChineseCharacters.simplifiedToTraditionalTarget.count
        )
    }
}
