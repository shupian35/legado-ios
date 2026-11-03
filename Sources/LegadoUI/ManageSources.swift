//
//  ManageSources.swift
//  LegadoUI
//
//  The management of the book sources and the RSS sources.
//
//  Upstream `ui/book/source/manage/SourceManageActivity.kt` lists the
//  sources with their groups, lets the user sort them, edit them in bulk
//  (the enable / delete / move to a group / export) and open the group
//  manager (`GroupManageDialog.kt`). The RSS sources have their own screen
//  (`ui/rss/source/SourceActivity.kt`).
//
//  See `AppModel.swift` for the state.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

// MARK: - The source groups

/// The manager of the source groups — upstream `GroupManageDialog`.
public struct SourceGroupView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var groups: [String] = []
    @State private var newGroup: String = ""

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
                        Button("删除", role: .destructive) {
                            delete(group)
                        }
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
        .onAppear {
            reload()
        }
    }

    private func reload() {
        groups = model.sourceGroups()
    }

    private func add() {
        let name = newGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        newGroup = ""
        reload()
    }

    private func delete(_ group: String) {
        model.removeSourceGroup(group)
        reload()
    }
}

// MARK: - The RSS sources

/// The RSS sources — upstream `ui/rss/source/SourceActivity`.
public struct RssSourceManagerView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var sources: [RssSource] = []
    @State private var editing: RssSource?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            ForEach(sources, id: \.sourceUrl) { source in
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.sourceName)
                    Text(source.sourceUrl)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editing = source
                }
            }
        }
        .navigationTitle("订阅源")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("添加") {
                    editing = RssSource(sourceUrl: "", sourceName: "")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // Upstream `RssSourceViewModel.restoreDefault`.
                Button("恢复默认") {
                    try? DefaultData.importDefaultRssSources(store: model.environment.store)
                    reload()
                }
            }
        }
        .sheet(item: $editing) { source in
            RssSourceEditor(source: source) { saved in
                model.saveRssSource(saved)
                reload()
            }
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        sources = (try? model.environment.store.allRssSources()) ?? []
    }
}

/// The editor of a RSS source — upstream `ui/rss/source/EditRssSourceActivity`.
struct RssSourceEditor: View {

    @State var source: RssSource
    /// The optional fields are edited as plain strings.
    @State var group: String = ""
    @State var ruleArticles: String = ""
    @State var ruleContent: String = ""
    @State var ruleNextPage: String = ""
    let onSave: (RssSource) -> Void

    @Environment(\.dismiss) private var dismiss

    init(source: RssSource, onSave: @escaping (RssSource) -> Void) {
        self.source = source
        self.onSave = onSave
        _group = State(initialValue: source.sourceGroup ?? "")
        _ruleArticles = State(initialValue: source.ruleArticles ?? "")
        _ruleContent = State(initialValue: source.ruleContent ?? "")
        _ruleNextPage = State(initialValue: source.ruleNextPage ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("订阅源") {
                    TextField("名称", text: $source.sourceName)
                    TextField("地址", text: $source.sourceUrl)
                    TextField("分组", text: $group)
                    Toggle("启用", isOn: $source.enabled)
                }
                Section("规则") {
                    TextField("文章列表", text: $ruleArticles)
                    TextField("正文", text: $ruleContent)
                    TextField("下一篇", text: $ruleNextPage)
                }
            }
            .navigationTitle("订阅源")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        var updated = source
                        updated.sourceGroup = group.isEmpty ? nil : group
                        updated.ruleArticles = ruleArticles.isEmpty ? nil : ruleArticles
                        updated.ruleContent = ruleContent.isEmpty ? nil : ruleContent
                        updated.ruleNextPage = ruleNextPage.isEmpty ? nil : ruleNextPage
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - The source sorting

/// The sorting of the book sources — upstream `BookSourceSortDialog`.
public enum BookSourceSort: String, CaseIterable, Identifiable {
    /// The manual order (`customOrder`).
    case custom = "手动排序"
    /// The name.
    case name = "名称"
    /// The group.
    case group = "分组"
    /// The response time.
    case respondTime = "响应时间"
    /// The last update time.
    case updateTime = "更新时间"
    /// The weight.
    case weight = "权重"

    public var id: String { rawValue }

    public var title: String { rawValue }
}

/// Sorts the book sources the way the upstream dialog does.
public enum BookSourceSorter {
    /// Sorts the sources by the given criterion.
    public static func sort(_ sources: [BookSource], by sort: BookSourceSort) -> [BookSource] {
        switch sort {
        case .custom:
            return sources.sorted { lhs, rhs in
                if lhs.customOrder != rhs.customOrder { return lhs.customOrder < rhs.customOrder }
                return lhs.bookSourceName < rhs.bookSourceName
            }
        case .name:
            return sources.sorted { $0.bookSourceName < $1.bookSourceName }
        case .group:
            return sources.sorted { lhs, rhs in
                let left = lhs.bookSourceGroup ?? ""
                let right = rhs.bookSourceGroup ?? ""
                if left != right { return left < right }
                return lhs.bookSourceName < rhs.bookSourceName
            }
        case .respondTime:
            return sources.sorted { lhs, rhs in
                if lhs.respondTime != rhs.respondTime { return lhs.respondTime < rhs.respondTime }
                return lhs.bookSourceName < rhs.bookSourceName
            }
        case .updateTime:
            return sources.sorted { lhs, rhs in
                if lhs.lastUpdateTime != rhs.lastUpdateTime { return lhs.lastUpdateTime > rhs.lastUpdateTime }
                return lhs.bookSourceName < rhs.bookSourceName
            }
        case .weight:
            return sources.sorted { lhs, rhs in
                if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
                return lhs.bookSourceName < rhs.bookSourceName
            }
        }
    }
}
