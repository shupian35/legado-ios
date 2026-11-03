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

import LegadoCore

// MARK: - The replace rules

/// The replace rule list and the editor.
public struct ReplaceRuleView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var editing: ReplaceRule?
    @State private var isEditorPresented = false
    @State private var testText: String = ""
    @State private var testResult: String = ""

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section {
                Button("添加规则") {
                    editing = ReplaceRule()
                    testText = ""
                    testResult = ""
                    isEditorPresented = true
                }
            }

            Section("规则") {
                if model.replaceRules.isEmpty {
                    Text("还没有替换净化规则")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(model.replaceRules, id: \.id) { rule in
                        Button {
                            editing = rule
                            testText = ""
                            testResult = ""
                            isEditorPresented = true
                        } label: {
                            VStack(alignment: .leading) {
                                Text(rule.name.isEmpty ? rule.pattern : rule.name)
                                Text(rule.pattern)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            model.deleteReplaceRule(model.replaceRules[index])
                        }
                    }
                }
            }
        }
        .navigationTitle("替换净化")
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
        .onAppear {
            model.reloadReplaceRules()
        }
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
