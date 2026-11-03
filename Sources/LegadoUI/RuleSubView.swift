//
//  RuleSubView.swift
//  LegadoUI
//
//  The port of
//  app/src/main/java/io/legado/app/ui/rss/subscription/RuleSubActivity.kt and
//  RuleSubAdapter.kt — the "规则订阅" screen.
//
//  The screen lists the addresses the app subscribes to. A tap on a row
//  imports the rules of that address (the upstream opens the import dialog
//  with the stored address), the edit button opens the editor and the menu
//  deletes the row.
//
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

// MARK: - The subscription list

/// The rule subscriptions — upstream `RuleSubActivity`.
public struct RuleSubView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var subs: [RuleSub] = []
    @State private var editing: RuleSub?
    @State private var status: String = ""
    @State private var isBusy = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            ForEach(subs) { sub in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(sub.name.isEmpty ? sub.url : sub.name)
                        Spacer()
                        Text(typeTitle(sub.type))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    Text(sub.url)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    HStack {
                        Button("导入") {
                            importSubscription(sub)
                        }
                        .font(.system(size: 12))
                        Button("编辑") {
                            editing = sub
                        }
                        .font(.system(size: 12))
                        Spacer()
                        Button("删除", role: .destructive) {
                            delete(sub)
                        }
                        .font(.system(size: 12))
                    }
                }
                .contentShape(Rectangle())
            }
            if !status.isEmpty {
                Section {
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("规则订阅")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("添加") {
                    editing = RuleSub(id: 0, name: "", url: "", type: 0, customOrder: nextOrder())
                }
            }
        }
        .sheet(item: $editing) { sub in
            RuleSubEditor(sub: sub) { saved in
                save(saved)
                reload()
            }
        }
        .onAppear {
            reload()
        }
    }

    /// The type name — upstream `R.array.rule_type`.
    private func typeTitle(_ type: Int64) -> String {
        switch RemoteImport.SubscriptionKind(rawValue: Int(type)) ?? .bookSource {
        case .bookSource: return "BookSource"
        case .rssSource: return "RssSource"
        case .replaceRule: return "ReplaceRule"
        }
    }

    private func nextOrder() -> Int64 {
        (subs.map(\.customOrder).max() ?? 0) + 1
    }

    private func reload() {
        subs = (try? model.environment.store.allRuleSubs())?
            .sorted { $0.customOrder < $1.customOrder } ?? []
    }

    private func save(_ sub: RuleSub) {
        var sub = sub
        let url = sub.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        sub.url = url
        // Upstream refuses a duplicate address (`RuleSubActivity.editSubscription`).
        if let existing = subs.first(where: { $0.url == url && $0.id != sub.id }) {
            status = "此地址已订阅(\(existing.name))"
            return
        }
        var row = sub
        if row.id == 0 {
            row.id = Int64(Date().timeIntervalSince1970 * 1000)
            row.customOrder = nextOrder()
        }
        try? model.environment.store.insert(row)
        reload()
    }

    private func delete(_ sub: RuleSub) {
        try? model.environment.store.deleteRuleSub(id: sub.id)
        reload()
    }

    /// Imports the rules of a subscription — upstream `openSubscription`.
    private func importSubscription(_ sub: RuleSub) {
        guard !isBusy else { return }
        isBusy = true
        status = "正在导入…"
        Task {
            do {
                let count = try await RemoteImport.importSubscription(
                    sub,
                    httpClient: model.environment.httpClient,
                    store: model.environment.store
                )
                status = "导入成功：\(count) 条"
            } catch {
                status = "导入失败：\(error.localizedDescription)"
            }
            isBusy = false
        }
    }
}

// MARK: - The editor

/// The editor of a subscription — upstream `DialogRuleSubEditBinding`.
struct RuleSubEditor: View {

    @State var sub: RuleSub
    @State var type: Int64 = 0
    @State var name: String = ""
    @State var url: String = ""
    let onSave: (RuleSub) -> Void

    @Environment(\.dismiss) private var dismiss

    init(sub: RuleSub, onSave: @escaping (RuleSub) -> Void) {
        self.sub = sub
        self.onSave = onSave
        _type = State(initialValue: sub.type)
        _name = State(initialValue: sub.name)
        _url = State(initialValue: sub.url)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则订阅") {
                    TextField("名称", text: $name)
                    TextField("地址", text: $url)
                    Picker("类型", selection: $type) {
                        Text("BookSource").tag(Int64(0))
                        Text("RssSource").tag(Int64(1))
                        Text("ReplaceRule").tag(Int64(2))
                    }
                }
            }
            .navigationTitle("规则订阅")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        var updated = sub
                        updated.name = name
                        updated.url = url
                        updated.type = type
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}
