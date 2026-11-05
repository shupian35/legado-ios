//
//  DictRuleManager.swift
//  LegadoCore
//
//  The management of the dictionary rules.
//
//  Upstream source of truth:
//  app/src/main/java/io/legado/app/ui/dict/rule/DictRuleViewModel.kt:14-61
//  app/src/main/java/io/legado/app/ui/dict/rule/DictRuleActivity.kt:126-206
//  app/src/main/java/io/legado/app/ui/dict/DictDialog.kt:41-90
//

import Foundation

/// The errors of the import of a dictionary rule document.
public enum DictRuleImportError: Error, Equatable, LocalizedError {
    case invalidJSON
    case noRule

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: return "不是有效的 JSON"
        case .noRule: return "没有找到字典规则"
        }
    }
}

/// The management of the dictionary rules — upstream `DictRuleViewModel`.
public enum DictRuleManager {

    /// The rules in the order of the upstream `dictRuleDao.all` — the
    /// `sortNumber` ascending; the name breaks a tie.
    public static func sorted(_ rules: [DictRule]) -> [DictRule] {
        rules.sorted { lhs, rhs in
            if lhs.sortNumber != rhs.sortNumber { return lhs.sortNumber < rhs.sortNumber }
            return lhs.name < rhs.name
        }
    }

    /// The rules with a fresh order — upstream `DictRuleViewModel.upSortNumber`:
    /// the rules are numbered from 1 in the order of the list.
    public static func renumbered(_ rules: [DictRule]) -> [DictRule] {
        rules.enumerated().map { index, rule in
            var copy = rule
            copy.sortNumber = Int64(index + 1)
            return copy
        }
    }

    /// The rules with the enabled flag set — upstream
    /// `DictRuleViewModel.enableSelection` / `disableSelection`.
    public static func settingEnabled(_ rules: [DictRule], _ enabled: Bool) -> [DictRule] {
        rules.map { rule in
            var copy = rule
            copy.enabled = enabled
            return copy
        }
    }

    /// The enabled rules — upstream `dictRuleDao.enabled`.
    public static func enabled(_ rules: [DictRule]) -> [DictRule] {
        sorted(rules.filter(\.enabled))
    }

    /// The export of the rules — upstream `GSON.toJson(adapter.selection)`,
    /// written into the file `exportDictRule.json`.
    public static func exportJSON(_ rules: [DictRule]) -> String {
        DocumentExport.json(rules, row: { $0.row })
    }

    /// The name of the exported file — upstream `exportDictRule.json`.
    public static let exportFileName = "exportDictRule.json"

    /// The copy of one rule — upstream `DictRuleEditDialog.copyRule`:
    /// `context.sendToClip(GSON.toJson(dictRule))`.
    public static func copyJSON(_ rule: DictRule) -> String {
        DocumentExport.jsonValue(rule.row).jsonString
    }

    /// The paste of one rule — upstream `DictRuleEditDialog.pasteRule`:
    /// the clipboard text is parsed as a rule; an empty clipboard or a
    /// malformed document is an error.
    public static func paste(_ text: String) throws -> DictRule {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw DictRuleImportError.invalidJSON }
        let value: JSONValue
        do {
            value = try JSONValue.parse(trimmed)
        } catch {
            throw DictRuleImportError.invalidJSON
        }
        guard case .object = value else { throw DictRuleImportError.invalidJSON }
        guard let rule = DictRuleJSONBridge.decode(value) else {
            throw DictRuleImportError.noRule
        }
        return rule
    }

    /// The import of a document — upstream `DictRuleActivity.menu_import_local`
    /// (a `txt` or a `json` file) and `menu_import_onLine`.
    ///
    /// The document holds one object or an array of objects; every object
    /// needs a name.
    public static func parse(_ text: String) throws -> [DictRule] {
        let value: JSONValue
        do {
            value = try JSONValue.parse(text)
        } catch {
            throw DictRuleImportError.invalidJSON
        }
        let rows: [JSONValue]
        switch value {
        case .array(let items): rows = items
        case .object: rows = [value]
        default: throw DictRuleImportError.invalidJSON
        }
        let rules = rows.compactMap { DictRuleJSONBridge.decode($0) }
        guard !rules.isEmpty else { throw DictRuleImportError.noRule }
        return rules
    }
}
