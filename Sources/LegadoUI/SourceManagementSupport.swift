//
//  SourceManagementSupport.swift
//  LegadoUI
//
//  The helpers of the source manager, the replace rules and the theme list.
//
//  Upstream references:
//  * `ui/book/source/manage/BookSourceViewModel.kt` — the magic search keys,
//    the sorting, the bulk operations and the group management;
//  * `ui/book/source/manage/GroupManageDialog.kt` — the group rename;
//  * `model/CheckSource.kt` and `ui/config/CheckSourceConfig.kt` — the
//    persisted options of the verification;
//  * `ui/replace/ReplaceRuleViewModel.kt` — the bulk operations of the rules;
//  * `ui/config/ThemeListDialog.kt` — the theme list.
//
//  See `AppModel.swift` for the state.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

// MARK: - The search keys of the book sources

/// The magic search keys of the source manager.
///
/// The upstream puts one of these strings into the search box when the user
/// picks a filter (`BookSourceActivity.onCompatOptionsItemSelected`) and the
/// DAO reads them back (`BookSourceViewModel.getBookSources`).
public enum BookSourceSearch {

    /// The enabled sources — upstream `R.string.enabled`.
    public static let enabled = "已启用"
    /// The disabled sources — upstream `R.string.disabled`.
    public static let disabled = "已禁用"
    /// The sources with a login — upstream `R.string.need_login`.
    public static let needLogin = "需登录"
    /// The sources without a group — upstream `R.string.no_group`.
    public static let noGroup = "无分组"
    /// The sources that may be discovered — upstream `R.string.enabled_explore`.
    public static let enabledExplore = "可发现"
    /// The sources that may not be discovered — upstream `R.string.disabled_explore`.
    public static let disabledExplore = "不可发现"

    /// The prefix of a group search — upstream `"group:"`.
    public static let groupPrefix = "group:"

    /// The filters of the menu, in the order the upstream shows them.
    public static let filters: [String] = [
        enabled, disabled, needLogin, noGroup, enabledExplore, disabledExplore
    ]

    /// The search key of a group — upstream `"group:" + title`.
    public static func groupKey(_ group: String) -> String {
        groupPrefix + group
    }

    /// Filters the sources the way the upstream DAO does.
    ///
    /// - `BookSourceDao.search` (L36-45) matches the name, the group, the url
    ///   and the comment.
    /// - `BookSourceDao.flowEnabled` / `flowDisabled` (L79-82).
    /// - `BookSourceDao.flowLogin` (L91-92) — the source has a login url.
    /// - `BookSourceDao.flowNoGroup` (L95-99).
    /// - `BookSourceDao.flowEnabledExplore` / `flowDisabledExplore` (L101-104).
    /// - `BookSourceDao.groupSearch` (L59-77).
    public static func filter(_ sources: [BookSource], key: String) -> [BookSource] {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return sources }
        if trimmed == enabled { return sources.filter { $0.enabled } }
        if trimmed == disabled { return sources.filter { !$0.enabled } }
        if trimmed == needLogin {
            return sources.filter { $0.loginUrl != nil || $0.loginUi != nil }
        }
        if trimmed == noGroup {
            return sources.filter { source in
                let group = (source.bookSourceGroup ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return group.isEmpty || group.contains("未分组")
            }
        }
        if trimmed == enabledExplore { return sources.filter { $0.enabledExplore } }
        if trimmed == disabledExplore { return sources.filter { !$0.enabledExplore } }
        if trimmed.hasPrefix(groupPrefix) {
            let group = String(trimmed.dropFirst(groupPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return sources.filter { $0.hasGroup(group) }
        }
        return sources.filter { source in
            source.bookSourceName.contains(trimmed)
                || (source.bookSourceGroup ?? "").contains(trimmed)
                || source.bookSourceUrl.contains(trimmed)
                || (source.bookSourceComment ?? "").contains(trimmed)
        }
    }
}

// MARK: - The domain of a source

/// The domain of a book source.
///
/// Upstream `BookSourceActivity.getSourceHost` (L692-696) uses
/// `NetworkUtils.getSubDomainOrNull` (L224-235) — the effective TLD+1 of the
/// host — and falls back to "#" when the url has no host.
public enum SourceHost {

    /// The domain of the source ("#" when it has none).
    public static func domain(of url: String) -> String {
        host(of: url) ?? "#"
    }

    /// The host of the url, without the port.
    public static func host(of url: String) -> String? {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard let host = URL(string: text)?.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        // An IP address is its own domain — upstream keeps it as it is.
        if isIPAddress(host) { return host }
        let labels = host.split(separator: ".")
        guard labels.count > 2 else { return host }
        return labels.suffix(2).joined(separator: ".")
    }

    /// Whether the host is an IPv4 or an IPv6 address.
    private static func isIPAddress(_ host: String) -> Bool {
        if host.contains(":") { return true }
        let parts = host.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { Int($0) != nil }
    }
}

// MARK: - The options of the verification

/// The persisted options of the verification.
///
/// Upstream `model/CheckSource.kt` keeps the options in the cache
/// (`checkSourceTimeout`, `checkSearch`, `checkDiscovery`, `checkInfo`,
/// `checkCategory` and `checkContent`) and `ui/config/CheckSourceConfig.kt`
/// edits them — the timeout in seconds, stored in milliseconds.
public struct SourceCheckConfig: Equatable {

    /// The upstream cache keys — `CheckSource.putConfig` (L47-54).
    public enum Key {
        public static let timeout = "checkSourceTimeout"
        public static let search = "checkSearch"
        public static let discovery = "checkDiscovery"
        public static let info = "checkInfo"
        public static let category = "checkCategory"
        public static let content = "checkContent"
        /// The keyword of the check — the upstream keeps it in the memory
        /// (`CheckSource.keyword`), the port stores it as well.
        public static let keyword = "checkSourceKeyword"
    }

    /// The options of the check.
    public var options: SourceCheckOptions

    public init(options: SourceCheckOptions = SourceCheckOptions()) {
        self.options = options
    }

    /// Loads the options — upstream `CheckSource` reads them from the cache.
    public static func load(from store: SettingsStore) -> SourceCheckConfig {
        var options = SourceCheckOptions()
        // The upstream stores the timeout in milliseconds.
        if let timeout = store.int(forKey: Key.timeout) {
            options.timeout = TimeInterval(timeout) / 1000
        }
        options.checkSearch = store.bool(forKey: Key.search) ?? options.checkSearch
        options.checkDiscovery = store.bool(forKey: Key.discovery) ?? options.checkDiscovery
        options.checkInfo = store.bool(forKey: Key.info) ?? options.checkInfo
        options.checkCategory = store.bool(forKey: Key.category) ?? options.checkCategory
        options.checkContent = store.bool(forKey: Key.content) ?? options.checkContent
        if let keyword = store.string(forKey: Key.keyword), !keyword.isEmpty {
            options.keyword = keyword
        }
        return SourceCheckConfig(options: options)
    }

    /// Saves the options — upstream `CheckSource.putConfig()`.
    public func save(to store: SettingsStore) {
        store.set(Int(options.timeout * 1000), forKey: Key.timeout)
        store.set(options.checkSearch, forKey: Key.search)
        store.set(options.checkDiscovery, forKey: Key.discovery)
        store.set(options.checkInfo, forKey: Key.info)
        store.set(options.checkCategory, forKey: Key.category)
        store.set(options.checkContent, forKey: Key.content)
        store.set(options.keyword, forKey: Key.keyword)
    }

    /// The summary of the options — upstream `CheckSource.summary` (L56-68).
    public var summary: String {
        var items: [String] = []
        if options.checkSearch { items.append("搜索") }
        if options.checkDiscovery { items.append("发现") }
        if options.checkInfo { items.append("详情") }
        if options.checkCategory { items.append("目录") }
        if options.checkContent { items.append("正文") }
        let scope = items.isEmpty ? "无" : items.joined(separator: " ")
        return "超时 \(Int(options.timeout)) 秒 · \(scope)"
    }

    /// The timeout in seconds — the upstream edits the timeout in seconds
    /// (`CheckSourceConfig`) but stores it in milliseconds.
    public var timeoutSeconds: Int {
        get { Int(options.timeout) }
        set { options.timeout = TimeInterval(newValue) }
    }
}

// MARK: - The search keys of the replace rules

/// The magic search keys of the replace rules — upstream
/// `ReplaceRuleActivity.observeReplaceRuleData` (L177-209).
public enum ReplaceRuleSearch {

    /// The rules without a group — upstream `R.string.no_group`.
    public static let noGroup = "无分组"

    /// The prefix of a group search — upstream `"group:"`.
    public static let groupPrefix = "group:"

    /// The search key of a group.
    public static func groupKey(_ group: String) -> String {
        groupPrefix + group
    }

    /// Filters the rules the way the upstream DAO does.
    ///
    /// - `ReplaceRuleDao.flowSearch` (L25-26) matches the group and the name.
    /// - `ReplaceRuleDao.flowGroupSearch` (L28-29).
    /// - `ReplaceRuleDao.flowNoGroup` (L34-35).
    public static func filter(_ rules: [ReplaceRule], key: String) -> [ReplaceRule] {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return rules }
        if trimmed == noGroup {
            return rules.filter { rule in
                let group = (rule.group ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return group.isEmpty || group.contains("未分组")
            }
        }
        if trimmed.hasPrefix(groupPrefix) {
            let group = String(trimmed.dropFirst(groupPrefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return rules.filter { rule in
                rule.groupNames.contains(group)
            }
        }
        return rules.filter { rule in
            rule.name.contains(trimmed)
                || (rule.group ?? "").contains(trimmed)
        }
    }
}

// MARK: - The groups of a replace rule

extension ReplaceRule {

    /// The groups of the rule, split on the upstream separator — upstream
    /// `ReplaceRuleViewModel.upGroup` (L106-119) splits the group on ",".
    public var groupNames: [String] {
        guard let group, !group.isEmpty else { return [] }
        return group
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Whether the rule is in the group.
    public func hasGroup(_ group: String) -> Bool {
        groupNames.contains(group.trimmingCharacters(in: .whitespaces))
    }

    /// Adds the rule to the group — upstream `ReplaceRule.addGroup`.
    public mutating func addGroup(_ group: String) {
        let trimmed = group.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = groupNames
        if !current.contains(trimmed) { current.append(trimmed) }
        self.group = current.joined(separator: ",")
    }

    /// Removes the rule from the group — upstream `ReplaceRule.removeGroup`.
    public mutating func removeGroup(_ group: String) {
        let trimmed = group.trimmingCharacters(in: .whitespaces)
        let current = groupNames.filter { $0 != trimmed }
        self.group = current.isEmpty ? nil : current.joined(separator: ",")
    }
}

// MARK: - The bulk operations

extension LegadoAppModel {

    // MARK: The book sources

    /// Moves the sources to the top — upstream `BookSourceViewModel.topSource`
    /// (L29-38): the sources get the smallest `customOrder`.
    public func topSources(_ sources: [BookSource]) {
        guard !sources.isEmpty else { return }
        let minOrder = (sources.map(\.customOrder).min() ?? 0) - 1
        for (index, source) in sources.enumerated() {
            var updated = source
            updated.customOrder = minOrder - Int64(index)
            try? environment.store.insert(updated)
        }
        reloadSources()
    }

    /// Moves the sources to the bottom — upstream
    /// `BookSourceViewModel.bottomSource` (L40-49).
    public func bottomSources(_ sources: [BookSource]) {
        guard !sources.isEmpty else { return }
        var maxOrder = (sources.map(\.customOrder).max() ?? 0) + 1
        for source in sources {
            var updated = source
            updated.customOrder = maxOrder
            maxOrder += 1
            try? environment.store.insert(updated)
        }
        reloadSources()
    }

    /// Moves a source to a new position in the list — upstream
    /// `BookSourceAdapter.swap` (L307-319) + `BookSourceAdapter.onClearView`
    /// (L323-339).
    ///
    /// The two sources exchange their `customOrder`; when the moved sources
    /// end up with the same order the whole list is renumbered by its
    /// position (the upstream's `upOrder` branch).
    public func moveSource(from source: BookSource, to target: BookSource, ascending: Bool = true) {
        guard source.bookSourceUrl != target.bookSourceUrl else { return }
        let (first, second) = SourceOrdering.swap(source, target)
        let moved = [first, second]
        if SourceOrdering.hasOrderCollision(moved) {
            let ordered = sources.sorted { $0.customOrder < $1.customOrder }
            for updated in SourceOrdering.renumber(ordered, ascending: ascending) {
                try? environment.store.insert(updated)
            }
        } else {
            for updated in moved {
                try? environment.store.insert(updated)
            }
        }
        reloadSources()
    }

    /// Renumbers the sources by their position — upstream
    /// `BookSourceAdapter.onClearView` (`upOrder`).
    public func renumberSources(ascending: Bool = true) {
        for updated in SourceOrdering.renumber(sources, ascending: ascending) {
            try? environment.store.insert(updated)
        }
        reloadSources()
    }

    /// Writes the order of the sources — upstream
    /// `BookSourceAdapter.onClearView` (`upOrder(getItems().mapIndexed { index, … })`).
    ///
    /// The sources are numbered by their position in the list.
    public func applySourceOrder(_ ordered: [BookSource]) {
        for updated in SourceOrdering.renumber(ordered, ascending: true) {
            try? environment.store.insert(updated)
        }
        reloadSources()
    }

    /// Enables or disables the discovery of the sources — upstream
    /// `BookSourceViewModel.enableExplore` (L86-90).
    public func setSourcesExplore(_ sources: [BookSource], enabled: Bool) {
        for source in sources {
            var updated = source
            updated.enabledExplore = enabled
            try? environment.store.insert(updated)
        }
        reloadSources()
    }

    /// Adds the sources to a group — upstream
    /// `BookSourceViewModel.selectionAddToGroups` (L104-113).
    public func addSourcesToGroup(_ sources: [BookSource], group: String) {
        let name = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        for source in sources {
            var updated = source
            updated.addGroup(name)
            try? environment.store.insert(updated)
        }
        reloadSources()
    }

    /// Removes the sources from a group — upstream
    /// `BookSourceViewModel.selectionRemoveFromGroups` (L115-124).
    public func removeSourcesFromGroup(_ sources: [BookSource], group: String) {
        for source in sources {
            var updated = source
            updated.removeGroup(group)
            try? environment.store.insert(updated)
        }
        reloadSources()
    }

    /// Creates a group — upstream `BookSourceViewModel.addGroup` (L251-259):
    /// every source **without** a group gets the new group.
    public func addSourceGroup(_ group: String) {
        let name = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        for source in sources {
            let current = (source.bookSourceGroup ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard current.isEmpty else { continue }
            var updated = source
            updated.addGroup(name)
            try? environment.store.insert(updated)
        }
        reloadSources()
    }

    /// Renames a group — upstream `BookSourceViewModel.upGroup` (L261-274) and
    /// `GroupManageDialog.editGroup` (L90-103).
    public func renameSourceGroup(_ group: String, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != group else { return }
        for source in sources where source.hasGroup(group) {
            var updated = source
            updated.removeGroup(group)
            updated.addGroup(name)
            try? environment.store.insert(updated)
        }
        reloadSources()
    }

    /// The sources as a JSON document — upstream
    /// `BookSourceViewModel.saveToFile` (L126-165) and
    /// `AppEnvironment.exportSources`.
    public func exportedSources(_ sources: [BookSource]) -> String {
        JSONValue.array(sources.map { BookSourceJSONBridge.encode($0) }).jsonString
    }

    // MARK: The replace rules

    /// The groups of the replace rules — upstream `ReplaceRuleDao.flowGroups`.
    public func replaceRuleGroups() -> [String] {
        var groups: [String] = []
        for rule in replaceRules {
            for group in rule.groupNames where !groups.contains(group) {
                groups.append(group)
            }
        }
        return groups.sorted()
    }

    /// Enables or disables the rules — upstream
    /// `ReplaceRuleViewModel.enableSelection` / `disableSelection` (L72-88).
    public func setReplaceRulesEnabled(_ rules: [ReplaceRule], enabled: Bool) {
        for rule in rules {
            var updated = rule
            updated.isEnabled = enabled
            try? environment.store.insert(updated)
        }
        reloadReplaceRules()
    }

    /// Moves the rules to the top — upstream `ReplaceRuleViewModel.topSelect`
    /// (L35-43).
    public func topReplaceRules(_ rules: [ReplaceRule]) {
        guard !rules.isEmpty else { return }
        let minOrder = (replaceRules.map(\.sortOrder).min() ?? 0) - Int64(rules.count)
        for (index, rule) in rules.enumerated() {
            var updated = rule
            updated.sortOrder = minOrder + Int64(index) + 1
            try? environment.store.insert(updated)
        }
        reloadReplaceRules()
    }

    /// Moves the rules to the bottom — upstream
    /// `ReplaceRuleViewModel.bottomSelect` (L52-60).
    public func bottomReplaceRules(_ rules: [ReplaceRule]) {
        guard !rules.isEmpty else { return }
        var maxOrder = replaceRules.map(\.sortOrder).max() ?? 0
        for rule in rules {
            var updated = rule
            updated.sortOrder = maxOrder
            maxOrder += 1
            try? environment.store.insert(updated)
        }
        reloadReplaceRules()
    }

    /// Renumbers the rules after a drag — upstream
    /// `ReplaceRuleViewModel.upOrder` (L62-70) and
    /// `ReplaceRuleAdapter.swap` (L173-198).
    ///
    /// Only the order of the rules that the user sees changes; the rules that
    /// the search hides keep their place.
    public func moveReplaceRules(
        _ visible: [ReplaceRule],
        from offsets: IndexSet,
        to destination: Int
    ) {
        var reordered = visible
        reordered.move(fromOffsets: offsets, toOffset: destination)
        let orders = visible.map(\.sortOrder).sorted()
        for (index, rule) in reordered.enumerated() where index < orders.count {
            var updated = rule
            updated.sortOrder = orders[index]
            try? environment.store.insert(updated)
        }
        reloadReplaceRules()
    }

    /// Deletes a group of the rules — upstream `ReplaceRuleViewModel.delGroup`
    /// (L121-134).
    public func removeReplaceRuleGroup(_ group: String) {
        for rule in replaceRules where rule.hasGroup(group) {
            var updated = rule
            updated.removeGroup(group)
            try? environment.store.insert(updated)
        }
        reloadReplaceRules()
    }

    /// Deletes the rules — upstream `ReplaceRuleViewModel.delSelection`
    /// (L90-94).
    public func deleteReplaceRules(_ rules: [ReplaceRule]) {
        for rule in rules {
            try? environment.store.deleteReplaceRule(id: rule.id)
        }
        reloadReplaceRules()
    }

    /// Adds the rules to a group — upstream `ReplaceRuleViewModel.addGroup`
    /// (L96-104) assigns the group to every rule **without** a group.
    public func addReplaceRulesToGroup(_ rules: [ReplaceRule], group: String) {
        let name = group.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        for rule in rules {
            var updated = rule
            updated.addGroup(name)
            try? environment.store.insert(updated)
        }
        reloadReplaceRules()
    }

    /// Removes the rules from a group — upstream
    /// `ReplaceRuleViewModel.delGroup` (L121-134).
    public func removeReplaceRulesFromGroup(_ rules: [ReplaceRule], group: String) {
        for rule in rules {
            var updated = rule
            updated.removeGroup(group)
            try? environment.store.insert(updated)
        }
        reloadReplaceRules()
    }

    /// Renames a group of the rules — upstream `ReplaceRuleViewModel.upGroup`
    /// (L106-119).
    public func renameReplaceRuleGroup(_ group: String, to newName: String) {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != group else { return }
        for rule in replaceRules where rule.hasGroup(group) {
            var updated = rule
            updated.removeGroup(group)
            updated.addGroup(name)
            try? environment.store.insert(updated)
        }
        reloadReplaceRules()
    }

    /// The rules as a JSON document — upstream
    /// `ReplaceRuleActivity.onMenuItemClick` (`menu_export_selection`).
    public func exportedReplaceRules(_ rules: [ReplaceRule]) -> String {
        JSONValue.array(rules.map { ReplaceRuleJSONBridge.encode($0) }).jsonString
    }

    // MARK: The RSS sources

    /// The RSS sources as a JSON document — upstream
    /// `RssSourceActivity` (`menu_export_selection`).
    public func exportedRSSSources(_ sources: [RssSource]) -> String {
        JSONValue.array(sources.map { RssSourceJSONBridge.encode($0) }).jsonString
    }

    // MARK: The themes

    /// Adds a theme — upstream `ThemeConfig.addConfig` (L119-142): a theme with
    /// the same name **replaces** the old one.
    @discardableResult
    public func addTheme(_ theme: AppTheme) -> Bool {
        if let index = themeManager.themes.firstIndex(where: { $0.themeName == theme.themeName }) {
            themeManager.update(index: index, theme: theme)
        } else {
            guard themeManager.add(theme) else { return false }
        }
        themeManager.save()
        return true
    }

    /// Deletes a theme — upstream `ThemeConfig.delConfig` (L114-117).
    public func deleteTheme(index: Int) {
        themeManager.delete(index: index)
        themeManager.save()
    }
}

// MARK: - The import sheet

/// The import sheet — upstream `ImportBookSourceDialog` and
/// `ImportReplaceRuleDialog`.
///
/// The upstream accepts a JSON document or the url of a document; the port
/// does the same and remembers the last url like the upstream's `ACache`
/// (the `bookSourceRecordKey` / `replaceRuleRecordKey` caches).
public struct ImportDocumentView: View {

    @ObservedObject var model: LegadoAppModel

    /// The kind of the imported document.
    let kind: ImportKind

    /// The pasted text or the typed url.
    @Binding var text: String

    @State private var isURL = false
    @State private var isLoading = false
    @State private var message: String?

    @Environment(\.dismiss) private var dismiss

    public init(model: LegadoAppModel, kind: ImportKind, text: Binding<String>) {
        self.model = model
        self.kind = kind
        self._text = text
    }

    /// The title of the sheet.
    public var title: String {
        switch kind {
        case .bookSource: return "导入书源"
        case .rssSource: return "导入订阅源"
        case .replaceRule: return "导入替换规则"
        default: return "导入"
        }
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("从网络链接导入", isOn: $isURL)
                }
                Section {
                    if isURL {
                        TextField("https://…", text: $text)
                    } else {
                        TextEditor(text: $text)
                            .frame(minHeight: 220)
                    }
                }
                if let message {
                    Section {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("导入") {
                        performImport()
                    }
                    .disabled(isLoading)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }

    /// The import itself — upstream `ImportBookSourceViewModel.importSource`.
    private func performImport() {
        let payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else {
            message = "内容为空"
            return
        }
        if isURL {
            isLoading = true
            Task {
                await importFromURL(payload)
                isLoading = false
            }
        } else {
            message = importJSON(payload)
        }
    }

    /// Downloads the document and imports it.
    private func importFromURL(_ url: String) async {
        guard let body = await DocumentImporter.download(url, model: model) else {
            message = DocumentImporter.failureMessage
            return
        }
        message = DocumentImporter.importJSON(body, kind: kind, model: model)
        dismiss()
    }

    /// Imports the JSON document — upstream `DeepLink.importJSON`.
    private func importJSON(_ json: String) -> String {
        let result = DocumentImporter.importJSON(json, kind: kind, model: model)
        if result != DocumentImporter.failureMessage {
            dismiss()
        }
        return result
    }
}

// MARK: - The prompt of a name

/// The prompt of a name — upstream the alerts with an `EditText`
/// (`GroupManageDialog.addGroup` L72-88, `BookSourceActivity.selectionAddToGroups`
/// L539-577).
public struct TextPromptView: View {

    /// The title of the prompt.
    let title: String
    /// The hint of the field.
    let placeholder: String
    /// The initial value of the field.
    let initial: String
    /// The action of the confirmation.
    let onSubmit: (String) -> Void

    @State private var text: String

    @Environment(\.dismiss) private var dismiss

    public init(
        title: String,
        placeholder: String = "",
        initial: String = "",
        onSubmit: @escaping (String) -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.initial = initial
        self.onSubmit = onSubmit
        _text = State(initialValue: initial)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(placeholder, text: $text)
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("确定") {
                        onSubmit(text)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - The import of the RSS sources

/// The import of the RSS sources — upstream
/// `ui/association/ImportRssSourceViewModel.importSourceAwait` (L106-158).
///
/// The upstream accepts a JSON object with `$.sourceUrls`, a JSON array of the
/// sources or an absolute url that points to such a document.
public enum RssSourceImporter {

    /// The message of a failed import — upstream "格式不对".
    public static let failureMessage = "格式不对,添加失败"

    /// Imports the text of the user.
    @discardableResult
    public static func importText(_ text: String, model: LegadoAppModel) async -> String {
        let payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return "内容为空" }
        if payload.hasPrefix("{") || payload.hasPrefix("[") {
            if let urls = sourceURLs(in: payload) {
                var count = 0
                for url in urls {
                    count += await importURL(url, model: model)
                }
                model.reloadRSS()
                return count > 0 ? "已导入 \(count) 个" : failureMessage
            }
            do {
                let summary = try DeepLink.importJSON(payload, kind: .rssSource, store: model.environment.store)
                model.reloadRSS()
                return "已导入 \(summary.count) 个"
            } catch {
                return failureMessage
            }
        }
        if isAbsoluteURL(payload) {
            let count = await importURL(payload, model: model)
            model.reloadRSS()
            return count > 0 ? "已导入 \(count) 个" : failureMessage
        }
        return failureMessage
    }

    /// The urls of a `$.sourceUrls` document — upstream
    /// `ImportRssSourceViewModel.importSourceAwait` (L106-120).
    public static func sourceURLs(in json: String) -> [String]? {
        guard let value = try? JSONValue.parse(json),
              let members = value.objectValue,
              let urls = members["sourceUrls"]?.arrayValue else {
            return nil
        }
        return urls.compactMap { $0.stringValue }.filter { !$0.isEmpty }
    }

    /// Whether the text is an absolute url.
    public static func isAbsoluteURL(_ text: String) -> Bool {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return false
        }
        return true
    }

    /// Downloads a document and imports the sources it holds.
    private static func importURL(_ url: String, model: LegadoAppModel) async -> Int {
        do {
            let response = try await model.environment.httpClient.send(HttpRequest(url: url))
            guard response.isSuccessful else { return 0 }
            guard let body = response.body ?? response.data.map({ String(decoding: $0, as: UTF8.self) }) else {
                return 0
            }
            if let urls = sourceURLs(in: body) {
                var count = 0
                for nested in urls {
                    count += await importURL(nested, model: model)
                }
                return count
            }
            let summary = try DeepLink.importJSON(body, kind: .rssSource, store: model.environment.store)
            return summary.count
        } catch {
            return 0
        }
    }
}

// MARK: - The import of the documents

/// The import of a document of sources or of rules.
///
/// Upstream `ui/association/ImportBookSourceDialog.kt` (L120-126) imports a
/// source that is a JSON document **or** the url of such a document; the
/// replace rules do the same (`ImportReplaceRuleDialog`).
public enum DocumentImporter {

    /// The message of a failed import — upstream "格式不对".
    public static let failureMessage = "格式不对,添加失败"

    /// Imports the text of the user.
    @discardableResult
    public static func importText(_ text: String, kind: ImportKind, model: LegadoAppModel) async -> String {
        let payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return "内容为空" }
        if kind == .rssSource {
            return await RssSourceImporter.importText(payload, model: model)
        }
        if payload.hasPrefix("{") || payload.hasPrefix("[") {
            return importJSON(payload, kind: kind, model: model)
        }
        if RssSourceImporter.isAbsoluteURL(payload) {
            guard let body = await download(payload, model: model) else {
                return failureMessage
            }
            return importJSON(body, kind: kind, model: model)
        }
        return failureMessage
    }

    /// Imports a JSON document.
    @discardableResult
    public static func importJSON(_ json: String, kind: ImportKind, model: LegadoAppModel) -> String {
        do {
            let summary = try DeepLink.importJSON(json, kind: kind, store: model.environment.store)
            reload(kind, model: model)
            return "已导入 \(summary.count) 个"
        } catch {
            return failureMessage
        }
    }

    /// Downloads a document.
    public static func download(_ url: String, model: LegadoAppModel) async -> String? {
        do {
            let response = try await model.environment.httpClient.send(HttpRequest(url: url))
            guard response.isSuccessful else { return nil }
            return response.body ?? response.data.map({ String(decoding: $0, as: UTF8.self) })
        } catch {
            return nil
        }
    }

    /// Reloads the list of the imported kind.
    public static func reload(_ kind: ImportKind, model: LegadoAppModel) {
        switch kind {
        case .bookSource: model.reloadSources()
        case .rssSource: model.reloadRSS()
        case .replaceRule: model.reloadReplaceRules()
        default: break
        }
    }
}

// MARK: - The help

/// The help of the source manager — upstream
/// `BookSourceActivity.menu_help` (L264) shows the `SourceMBookHelp` document
/// (`app/src/main/assets/web/help/md/SourceMBookHelp.md`).
public struct SourceHelpView: View {

    public init() {}

    public var body: some View {
        ScrollView {
            Text(SourceHelp.text)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .navigationTitle("书源帮助")
    }
}

/// The text of the help of the source manager — the upstream document.
public enum SourceHelp {
    /// The upstream `SourceMBookHelp.md`.
    public static let text = """
    # 书源管理界面帮助

    * 书源右上角标志
      * 绿点表示书源有发现,且启用了发现
      * 红点表示书源有发现,但是未启用
      * 没有标志表示此书源没有发现
    * 右上角有分组菜单,可以按分组筛选书源
    * 右上角更多菜单里包含
      * 新建书源
      * 本地导入
      * 网络导入
      * 二维码导入
      * 分享选中源
    * 选择源的更多操作在右下角的菜单里面,操作都是针对选择的书源
      * 启用所选
      * 禁用所选
      * 添加分组
      * 移除分组
      * 启用发现
      * 禁用发现
      * 置顶所选
      * 置底所选
      * 导出所选
      * 校验所选
    * 校验书源可批量校验书源，由于网络等原因结果仅限参考
      * "校验成功"是指所选的校验项目全部通过
      * 可正常识别搜索为空、发现为空、搜索(发现)目录为空、搜索(发现)正文为空、校验超时、js执行错误导致的失效，其余的原因视为网站失效
      * 校验搜索优先使用书源填写的校验关键词，不存在时使用用户输入的关键词
      * 校验结束后会自动筛选"失效"书源
    """
}

/// The help of the replace rules — upstream
/// `ReplaceRuleActivity.menu_help` (L235) shows the `replaceRuleHelp`
/// document (`app/src/main/assets/web/help/md/replaceRuleHelp.md`).
public struct ReplaceRuleHelpView: View {

    public init() {}

    public var body: some View {
        ScrollView {
            Text(ReplaceRuleHelp.text)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .navigationTitle("帮助")
    }
}

/// The text of the help of the replace rules — the upstream document.
public enum ReplaceRuleHelp {
    /// The upstream `replaceRuleHelp.md`.
    public static let text = """
    # 替换管理界面帮助

    * 替换规则是用来替换正文内容的一种规则
      * 菜单可以新建和导入规则
      * 可以拖动排序
      * 可以选择操作
    """
}
