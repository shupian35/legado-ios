//
//  ManageViews.swift
//  LegadoUI
//
//  The management screens that the upstream spreads over its own activities:
//
//  * the replace rules — upstream `ui/book/replace/ReplaceRuleActivity.kt`
//  * the bookmarks — upstream `ui/book/manage/BookmarkActivity.kt`
//  * the book groups — upstream `ui/main/bookshelf/groups/ManageGroupActivity.kt`
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

// MARK: - The replace rules

/// The replace rule list and the editor.
///
/// Upstream `ui/replace/ReplaceRuleActivity.kt` shows the rules with a search
/// box (L145-149), a menu with the import of the rules (local, online and QR
/// code — L221-245), the groups (L265-270), the help and the selection bar
/// with the enable / disable, the move to the top / the bottom and the export
/// of the selection (L247-263). The rules can be dragged to be reordered
/// (L128-143).
public struct ReplaceRuleView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var editing: ReplaceRule?
    @State private var isEditorPresented = false
    @State private var testText: String = ""
    @State private var testResult: String = ""

    // The search — upstream `initSearchView` (L145-149).
    @State private var searchText: String = ""
    // The selection — upstream `ReplaceRuleAdapter.selected` (L26-33).
    @State private var isManaging = false
    @State private var selection: Set<Int64> = []
    // The import and the help.
    @State private var isImportPresented = false
    @State private var importText: String = ""
    @State private var isFileImporterPresented = false
    @State private var isQRScannerPresented = false
    @State private var qrResult: String?
    @State private var isHelpPresented = false
    @State private var isGroupPresented = false
    @State private var isSharePresented = false
    @State private var message: String?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section("规则") {
                if visibleRules.isEmpty {
                    Text("还没有替换净化规则")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(visibleRules, id: \.id) { rule in
                        ReplaceRuleRow(
                            rule: rule,
                            isSelected: selection.contains(rule.id),
                            onToggle: { enabled in
                                var updated = rule
                                updated.isEnabled = enabled
                                model.saveReplaceRule(updated)
                            },
                            onSelect: {
                                if isManaging {
                                    if selection.contains(rule.id) {
                                        selection.remove(rule.id)
                                    } else {
                                        selection.insert(rule.id)
                                    }
                                }
                            },
                            onEdit: {
                                editing = rule
                                testText = ""
                                testResult = ""
                                isEditorPresented = true
                            },
                            onTop: {
                                model.topReplaceRules([rule])
                            },
                            onBottom: {
                                model.bottomReplaceRules([rule])
                            },
                            onDelete: {
                                model.deleteReplaceRule(rule)
                                selection.remove(rule.id)
                            }
                        )
                    }
                    // Upstream `itemTouchCallback.isCanDrag = true` (L130).
                    .onMove { offsets, destination in
                        model.moveReplaceRules(visibleRules, from: offsets, to: destination)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.deleteReplaceRule(visibleRules[index])
                        }
                    }
                }
            }
            if isManaging {
                Section("已选 \(selection.count) 个") {
                    Menu {
                        // Upstream `menu_enable_selection` / `menu_disable_selection`.
                        Button("启用所选") {
                            model.setReplaceRulesEnabled(selectedRules, enabled: true)
                        }
                        Button("禁用所选") {
                            model.setReplaceRulesEnabled(selectedRules, enabled: false)
                        }
                        // Upstream `menu_top_sel` / `menu_bottom_sel`.
                        Button("置顶所选") {
                            model.topReplaceRules(selectedRules)
                        }
                        Button("置底所选") {
                            model.bottomReplaceRules(selectedRules)
                        }
                        // Upstream `menu_export_selection`.
                        Button("导出所选") {
                            UIPasteboardShim.copy(model.exportedReplaceRules(selectedRules))
                            message = "已导出 \(selectedRules.count) 个规则"
                        }
                        // Upstream `menu_del_selection`.
                        Button("删除所选", role: .destructive) {
                            model.deleteReplaceRules(selectedRules)
                            selection.removeAll()
                        }
                    } label: {
                        Text("批量操作")
                    }
                    HStack {
                        Button("全选") {
                            selection = Set(visibleRules.map(\.id))
                        }
                        Button("取消选择") {
                            selection.removeAll()
                        }
                    }
                    .font(.system(size: 13))
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
        .navigationTitle("替换净化")
        .searchable(text: $searchText, prompt: "搜索替换净化")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Upstream `menu_add_replace_rule`.
                Button("添加") {
                    editing = ReplaceRule()
                    testText = ""
                    testResult = ""
                    isEditorPresented = true
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    // Upstream `menu_import_local`.
                    Button("导入本地") {
                        isFileImporterPresented = true
                    }
                    // Upstream `menu_import_onLine`.
                    Button("导入网络") {
                        importText = ""
                        isImportPresented = true
                    }
                    // Upstream `menu_import_qr`.
                    Button("二维码导入") {
                        isQRScannerPresented = true
                    }
                } label: {
                    Text("导入")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    // Upstream `upGroupMenu` (L265-270) and `menu_group_null`.
                    Button("无分组") {
                        searchText = ReplaceRuleSearch.noGroup
                    }
                    ForEach(model.replaceRuleGroups(), id: \.self) { group in
                        Button(group) {
                            searchText = ReplaceRuleSearch.groupKey(group)
                        }
                    }
                    Divider()
                    // Upstream `menu_group_manage`.
                    Button("分组管理") {
                        isGroupPresented = true
                    }
                } label: {
                    Text("分组")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                // Upstream `menu_help` — the `replaceRuleHelp` document.
                Button("帮助") {
                    isHelpPresented = true
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Button(isManaging ? "完成" : "管理") {
                    isManaging.toggle()
                    if !isManaging { selection.removeAll() }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                // Upstream `menu_export_selection` of the whole list.
                Button("导出") {
                    UIPasteboardShim.copy(model.exportedReplaceRules(visibleRules))
                    message = "已导出 \(visibleRules.count) 个规则"
                }
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            if let editing {
                NavigationStack {
                    ReplaceRuleEditor(
                        model: model,
                        rule: editing,
                        testText: $testText,
                        testResult: $testResult
                    )
                }
            }
        }
        .sheet(isPresented: $isImportPresented) {
            ImportDocumentView(model: model, kind: .replaceRule, text: $importText)
        }
        .sheet(isPresented: $isQRScannerPresented) {
            NavigationStack {
                QRScannerView(result: $qrResult)
            }
        }
        .sheet(isPresented: $isHelpPresented) {
            NavigationStack {
                ReplaceRuleHelpView()
            }
        }
        .sheet(isPresented: $isGroupPresented) {
            NavigationStack {
                ReplaceRuleGroupView(model: model)
            }
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(items: [model.exportedReplaceRules(visibleRules)])
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: ReplaceRuleView.contentTypes,
            onCompletion: { result in
                importFile(result)
            }
        )
        .onChange(of: qrResult) { _, value in
            guard let value, !value.isEmpty else { return }
            qrResult = nil
            Task {
                message = await DocumentImporter.importText(value, kind: .replaceRule, model: model)
            }
        }
        .onAppear {
            model.reloadReplaceRules()
        }
    }

    /// The rules of the list — upstream `ReplaceRuleActivity.observeReplaceRuleData`
    /// (L177-209).
    private var visibleRules: [ReplaceRule] {
        ReplaceRuleSearch.filter(model.replaceRules, key: searchText)
    }

    /// The rules of the selection.
    private var selectedRules: [ReplaceRule] {
        model.replaceRules.filter { selection.contains($0.id) }
    }

    /// The accepted file types — upstream `AppPattern` accepts `txt` and
    /// `json` for the rules.
    public static var contentTypes: [UTType] {
        var types: [UTType] = [.data]
        for ext in ["txt", "json"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    /// Imports a local file — upstream `menu_import_local`.
    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                message = DocumentImporter.failureMessage
                return
            }
            message = await DocumentImporter.importText(text, kind: .replaceRule, model: model)
        }
    }
}

/// One rule of the list — upstream `ReplaceRuleAdapter.convert` (L99-124) and
/// `ReplaceRuleAdapter.showMenu` (L155-171).
struct ReplaceRuleRow: View {

    let rule: ReplaceRule
    var isSelected: Bool = false
    let onToggle: (Bool) -> Void
    let onSelect: () -> Void
    let onEdit: () -> Void
    let onTop: () -> Void
    let onBottom: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name.isEmpty ? rule.pattern : rule.name)
                    .font(.system(size: 15))
                Text(rule.pattern)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let group = rule.group, !group.isEmpty {
                    Text(group)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(isSelected ? "已选" : "选择", action: onSelect)
                .font(.system(size: 12))
            Toggle("启用", isOn: Binding(get: { rule.isEnabled }, set: onToggle))
                .labelsHidden()
            Menu {
                Button("置顶", action: onTop)
                Button("置底", action: onBottom)
                Button("编辑", action: onEdit)
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Text("更多")
                    .font(.system(size: 12))
            }
        }
        .padding(.vertical, 4)
    }
}

/// The manager of the groups of the replace rules — upstream
/// `ui/replace/GroupManageDialog.kt` (add — L78-93, rename — L96-107 and
/// delete — L122-125).
public struct ReplaceRuleGroupView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var groups: [String] = []
    @State private var newGroup: String = ""
    @State private var isRenamePresented = false
    @State private var editingGroup: String = ""
    @State private var editName: String = ""

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section("分组") {
                ForEach(groups, id: \.self) { group in
                    HStack {
                        Text(group)
                        Spacer()
                        Button("重命名") {
                            editingGroup = group
                            editName = group
                            isRenamePresented = true
                        }
                        .font(.system(size: 12))
                        Button("删除", role: .destructive) {
                            model.removeReplaceRuleGroup(group)
                            reload()
                        }
                        .font(.system(size: 12))
                    }
                }
            }
            Section("新建分组") {
                TextField("分组名称", text: $newGroup)
                Button("添加") {
                    add()
                }
            }
        }
        .navigationTitle("分组管理")
        .sheet(isPresented: $isRenamePresented) {
            TextPromptView(title: "重命名分组", placeholder: "分组名称", initial: editName) { name in
                model.renameReplaceRuleGroup(editingGroup, to: name)
                reload()
            }
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        groups = model.replaceRuleGroups()
    }

    /// Adds a group — upstream `ReplaceRuleViewModel.addGroup` (L96-104):
    /// every rule **without** a group gets the new group.
    private func add() {
        let name = newGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.addReplaceRulesToGroup(model.replaceRules, group: name)
        newGroup = ""
        reload()
    }
}

/// The replace rule editor — upstream `ReplaceRuleDialog`.
public struct ReplaceRuleEditor: View {

    @ObservedObject var model: LegadoAppModel

    @State private var rule: ReplaceRule
    @Binding var testText: String
    @Binding var testResult: String

    public init(
        model: LegadoAppModel,
        rule: ReplaceRule,
        testText: Binding<String>,
        testResult: Binding<String>
    ) {
        self.model = model
        self._rule = State(initialValue: rule)
        self._testText = testText
        self._testResult = testResult
    }

    public var body: some View {
        Form {
            Section("规则") {
                TextField("名称", text: Binding(
                    get: { rule.name },
                    set: { rule.name = $0 }
                ))
                TextField("分组", text: Binding(
                    get: { rule.group ?? "" },
                    set: { rule.group = $0.isEmpty ? nil : $0 }
                ))
                TextField("匹配文本", text: Binding(
                    get: { rule.pattern },
                    set: { rule.pattern = $0 }
                ))
                TextField("替换为", text: Binding(
                    get: { rule.replacement },
                    set: { rule.replacement = $0 }
                ))
                Toggle("正则表达式", isOn: Binding(
                    get: { rule.isRegex },
                    set: { rule.isRegex = $0 }
                ))
                Toggle("启用", isOn: Binding(
                    get: { rule.isEnabled },
                    set: { rule.isEnabled = $0 }
                ))
                Toggle("作用于标题", isOn: Binding(
                    get: { rule.scopeTitle },
                    set: { rule.scopeTitle = $0 }
                ))
                Toggle("作用于正文", isOn: Binding(
                    get: { rule.scopeContent },
                    set: { rule.scopeContent = $0 }
                ))
                TextField("作用范围（书名,作者）", text: Binding(
                    get: { rule.scope ?? "" },
                    set: { rule.scope = $0.isEmpty ? nil : $0 }
                ))
            }

            Section("测试") {
                TextField("测试文本", text: $testText)
                Button("测试") {
                    testResult = (try? ReplaceRuleEngine.apply(rule, to: testText)) ?? "规则无效"
                }
                Text(testResult)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("替换规则")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("保存") {
                    model.saveReplaceRule(rule)
                }
            }
        }
    }
}

// MARK: - The bookmarks

/// The bookmark list — upstream `ui/book/manage/BookmarkActivity.kt`.
public struct BookmarkView: View {

    @ObservedObject var model: LegadoAppModel

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            if model.bookmarks.isEmpty {
                Text("还没有书签")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                ForEach(model.bookmarks, id: \.time) { bookmark in
                    VStack(alignment: .leading) {
                        Text(bookmark.chapterName.isEmpty ? bookmark.bookName : bookmark.chapterName)
                        Text("\(bookmark.bookName) · \(bookmark.bookAuthor)")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        if !bookmark.content.isEmpty {
                            Text(bookmark.content)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        model.deleteBookmark(model.bookmarks[index])
                    }
                }
            }
        }
        .navigationTitle("书签")
        .onAppear {
            model.reloadBookmarks()
        }
    }
}

// MARK: - The book groups

/// The group management — upstream `ui/main/bookshelf/groups/ManageGroupActivity.kt`.
public struct BookGroupView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var newGroupName: String = ""

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section {
                HStack {
                    TextField("分组名称", text: $newGroupName)
                    Button("添加") {
                        model.addGroup(name: newGroupName)
                        newGroupName = ""
                    }
                }
            }

            Section("分组") {
                ForEach(model.groups, id: \.groupId) { group in
                    HStack {
                        Text(group.groupName)
                        Spacer()
                        Text("\(model.bookCount(inGroup: group.groupId))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .onDelete { offsets in
                    for index in offsets {
                        model.deleteGroup(model.groups[index])
                    }
                }
            }
        }
        .navigationTitle("分组管理")
        .onAppear {
            model.reloadBookshelf()
        }
    }
}
