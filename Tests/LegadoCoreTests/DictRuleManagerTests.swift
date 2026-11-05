//
//  DictRuleManagerTests.swift
//  LegadoCoreTests
//
//  The management of the dictionary rules — upstream `DictRuleViewModel`.
//

import XCTest
@testable import LegadoCore

final class DictRuleManagerTests: XCTestCase {

    private func rule(
        _ name: String,
        enabled: Bool = true,
        sortNumber: Int64 = 0
    ) -> DictRule {
        DictRule(
            name: name,
            urlRule: "https://dict.example.com/\(name)",
            showRule: "$.result",
            enabled: enabled,
            sortNumber: sortNumber
        )
    }

    // MARK: - The order

    func testSortedBySortNumber() {
        let rules = [
            rule("b", sortNumber: 2),
            rule("a", sortNumber: 1),
            rule("c", sortNumber: 3)
        ]
        XCTAssertEqual(DictRuleManager.sorted(rules).map(\.name), ["a", "b", "c"])
    }

    func testSortedBreaksTheTieWithTheName() {
        let rules = [
            rule("z", sortNumber: 1),
            rule("a", sortNumber: 1)
        ]
        XCTAssertEqual(DictRuleManager.sorted(rules).map(\.name), ["a", "z"])
    }

    // MARK: - The renumbering — upstream `upSortNumber`

    func testRenumberedStartsAtOne() {
        let rules = [rule("a", sortNumber: 7), rule("b", sortNumber: 9), rule("c", sortNumber: 11)]
        let renumbered = DictRuleManager.renumbered(rules)
        XCTAssertEqual(renumbered.map(\.sortNumber), [1, 2, 3])
        XCTAssertEqual(renumbered.map(\.name), ["a", "b", "c"])
    }

    func testRenumberedKeepsTheOtherFields() {
        let rules = [rule("a", enabled: false, sortNumber: 4)]
        let renumbered = DictRuleManager.renumbered(rules)
        XCTAssertFalse(renumbered[0].enabled)
        XCTAssertEqual(renumbered[0].urlRule, "https://dict.example.com/a")
    }

    // MARK: - The enabled flag — upstream `enableSelection` / `disableSelection`

    func testSettingEnabled() {
        let rules = [rule("a"), rule("b")]
        XCTAssertTrue(DictRuleManager.settingEnabled(rules, false).allSatisfy { !$0.enabled })
        XCTAssertTrue(DictRuleManager.settingEnabled(rules, true).allSatisfy(\.enabled))
    }

    func testEnabledFiltersTheDisabledRules() {
        let rules = [
            rule("a", enabled: true, sortNumber: 2),
            rule("b", enabled: false, sortNumber: 1),
            rule("c", enabled: true, sortNumber: 3)
        ]
        XCTAssertEqual(DictRuleManager.enabled(rules).map(\.name), ["a", "c"])
    }

    // MARK: - The import

    func testParseOneObject() throws {
        let text = """
        {"name": "测试", "urlRule": "https://a.com/s?q={key}", "showRule": "$.data"}
        """
        let rules = try DictRuleManager.parse(text)
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules[0].name, "测试")
        XCTAssertEqual(rules[0].urlRule, "https://a.com/s?q={key}")
        XCTAssertEqual(rules[0].showRule, "$.data")
    }

    func testParseAnArray() throws {
        let text = """
        [{"name": "一", "urlRule": "u1"}, {"name": "二", "urlRule": "u2"}]
        """
        let rules = try DictRuleManager.parse(text)
        XCTAssertEqual(rules.map(\.name), ["一", "二"])
    }

    func testParseWithoutANameIsSkipped() throws {
        let text = """
        [{"urlRule": "u1"}, {"name": "二", "urlRule": "u2"}]
        """
        let rules = try DictRuleManager.parse(text)
        XCTAssertEqual(rules.map(\.name), ["二"])
    }

    func testParseInvalidJSONThrows() {
        XCTAssertThrowsError(try DictRuleManager.parse("not json")) { error in
            XCTAssertEqual(error as? DictRuleImportError, .invalidJSON)
        }
    }

    func testParseWithoutARuleThrows() {
        XCTAssertThrowsError(try DictRuleManager.parse("[]")) { error in
            XCTAssertEqual(error as? DictRuleImportError, .noRule)
        }
        XCTAssertThrowsError(try DictRuleManager.parse("123")) { error in
            XCTAssertEqual(error as? DictRuleImportError, .invalidJSON)
        }
    }

    // MARK: - The export

    func testExportJSONRoundTrip() throws {
        let rules = [rule("a"), rule("b")]
        let json = DictRuleManager.exportJSON(rules)
        let parsed = try DictRuleManager.parse(json)
        XCTAssertEqual(parsed.map(\.name), ["a", "b"])
        XCTAssertEqual(parsed[0].urlRule, "https://dict.example.com/a")
    }

    func testTheExportFileName() {
        // Upstream `DictRuleActivity.menu_export_selection`.
        XCTAssertEqual(DictRuleManager.exportFileName, "exportDictRule.json")
    }

    // MARK: - The store

    func testTheStoreKeepsTheRules() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        let rules = [rule("a"), rule("b")]
        for rule in rules { try store.insert(rule) }
        let rows = try store.allDictRules()
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.name)), ["a", "b"])
    }

    func testTheStoreDeletesTheRules() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        let rules = [rule("a"), rule("b")]
        for rule in rules { try store.insert(rule) }
        try store.deleteDictRule(rules[0])
        let rows = try store.allDictRules()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "b")
    }

    func testTheStoreDeletesSeveralRules() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        let rules = [rule("a"), rule("b"), rule("c")]
        for rule in rules { try store.insert(rule) }
        try store.deleteDictRules([rules[0], rules[2]])
        let rows = try store.allDictRules()
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].name, "b")
    }

    func testTheStoreUpdatesTheRules() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        let rules = [rule("a")]
        for rule in rules { try store.insert(rule) }
        let updated = DictRuleManager.settingEnabled(rules, false)
        try store.updateDictRules(updated)
        let rows = try store.allDictRules()
        XCTAssertEqual(rows.count, 1)
        XCTAssertFalse(rows[0].enabled)
    }

    func testTheStoreRenumbersTheRules() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        let rules = [rule("a", sortNumber: 5), rule("b", sortNumber: 6)]
        for rule in rules { try store.insert(rule) }
        try store.updateDictRules(DictRuleManager.renumbered(rules))
        let rows = try store.allDictRules()
        XCTAssertEqual(rows.map(\.sortNumber).sorted(), [1, 2])
    }
}
