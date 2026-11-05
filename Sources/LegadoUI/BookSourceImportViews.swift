//
//  BookSourceImportViews.swift
//  LegadoUI
//
//  The preview of the import of the book sources.
//
//  Upstream:
//  - `ui/association/ImportBookSourceDialog.kt` — the preview of the import,
//  - `ui/association/ImportBookSourceViewModel.kt` — the options of the
//    import.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The preview of the import of the book sources — upstream
/// `ui/association/ImportBookSourceDialog.kt`.
///
/// The upstream lists every imported source with a check box, its name and
/// its state ("新增", "更新" or "已有"), the footer has 全选/反选 with the
/// number of the selected sources, 取消 and 确定, and the menu holds the
/// options of the import (保留名称 / 保留分组 / 保留启用 / 新建分组).
public struct BookSourceImportPreviewView: View {

    @ObservedObject var model: LegadoAppModel

    /// The imported sources.
    let sources: [BookSource]

    /// The action of the import — the prepared sources are handed over.
    let onImport: ([BookSource]) -> Void

    /// The preview — upstream `comparisonSource`.
    @State private var items: [BookSourceImport.Item] = []

    /// The options of the import — upstream `importSelect`.
    @State private var options = BookSourceImport.Options()

    /// The group of the import — upstream `menu_new_group`.
    @State private var groupName: String = ""

    /// Whether the group prompt is shown.
    @State private var isGroupPromptPresented = false

    /// The source whose JSON is shown — upstream `CodeDialog`.
    @State private var codeItem: BookSourceImport.Item?

    public init(
        model: LegadoAppModel,
        sources: [BookSource],
        onImport: @escaping ([BookSource]) -> Void
    ) {
        self.model = model
        self.sources = sources
        self.onImport = onImport
    }

    public var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Button(item.selected ? "☑" : "☐") {
                            toggle(item.id)
                        }
                        .buttonStyle(PlainButtonStyle())
                        Button {
                            codeItem = item
                        } label: {
                            Text(item.source.bookSourceName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                        Text(item.state.rawValue)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section {
                HStack {
                    Button(selectedAll ? "反选" : "全选") {
                        selectAll()
                    }
                    Spacer()
                    Text("已选 \(selectedCount) 个")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Button("确定") {
                    confirm()
                }
            }
        }
        .navigationTitle("导入书源")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                // The upstream `res/menu/import_source.xml`.
                Menu("选项") {
                    Toggle("保留原名称", isOn: $options.keepName)
                    Toggle("保留原分组", isOn: $options.keepGroup)
                    Toggle("保留原启用状态", isOn: $options.keepEnable)
                    Button("新建分组") {
                        isGroupPromptPresented = true
                    }
                }
            }
        }
        .alert("新建分组", isPresented: $isGroupPromptPresented) {
            Button("取消", role: .cancel) {}
            Button("确定") {
                options.groupName = groupName
            }
        } message: {
            Text("导入的书源将放入该分组")
        }
        .alert("书源", isPresented: Binding(
            get: { codeItem != nil },
            set: { if !$0 { codeItem = nil } }
        )) {
            Button("关闭", role: .cancel) {}
        } message: {
            Text(codeItem.map { BookSourceJSONBridge.encode($0.source).jsonString } ?? "")
        }
        .onAppear {
            reload()
        }
    }

    // MARK: - The helpers

    /// The number of the selected sources.
    private var selectedCount: Int {
        items.filter { $0.selected }.count
    }

    /// Whether every source is selected.
    private var selectedAll: Bool {
        !items.isEmpty && selectedCount == items.count
    }

    /// Builds the preview — upstream `comparisonSource`.
    private func reload() {
        items = (try? model.environment.sourceImportPreview(sources)) ?? []
    }

    /// Selects or deselects a source.
    private func toggle(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].selected.toggle()
    }

    /// Selects every source, or deselects them all — upstream `selectAll`.
    private func selectAll() {
        let all = selectedAll
        for index in items.indices {
            items[index].selected = !all
        }
    }

    /// The import — upstream `importSelect`.
    private func confirm() {
        let local = (try? model.environment.store.allSources()) ?? []
        let prepared = BookSourceImport.prepare(items, local: local, options: options)
        onImport(prepared)
    }
}
