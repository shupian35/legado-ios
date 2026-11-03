//
//  SourceManagerView.swift
//  LegadoUI
//
//  The book source manager — upstream `ui/book/source/SourceManageActivity`.
//
//  It lists the sources, enables and disables them, deletes them and imports
//  or exports them as JSON.
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

/// The source manager.
public struct SourceManagerView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var importText: String = ""
    @State private var isImportPresented = false
    @State private var isCheckPresented = false
    @State private var loginSource: BookSource?
    @State private var isLoginPresented = false
    @State private var isSharePresented = false
    @State private var isQRCodePresented = false
    @State private var editingSource: BookSource?
    @State private var isEditorPresented = false
    @State private var isGroupPresented = false
    @State private var isDebugPresented = false
    @State private var isManaging = false
    @State private var selection: Set<String> = []

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.sources, id: \.bookSourceUrl) { source in
                        SourceRow(
                            source: source,
                            isSelected: selection.contains(source.bookSourceUrl),
                            onToggle: { enabled in model.setSource(source, enabled: enabled) },
                            onDelete: { model.deleteSource(source) },
                            onSelect: {
                                if isManaging {
                                    if selection.contains(source.bookSourceUrl) {
                                        selection.remove(source.bookSourceUrl)
                                    } else {
                                        selection.insert(source.bookSourceUrl)
                                    }
                                }
                            },
                            onLogin: {
                                loginSource = source
                                isLoginPresented = true
                            },
                            onEdit: {
                                editingSource = source
                                isEditorPresented = true
                            }
                        )
                    }
                }
                if isManaging {
                    Section {
                        HStack {
                            Button("全选") {
                                selection = Set(model.sources.map(\.bookSourceUrl))
                            }
                            Button("取消") {
                                selection.removeAll()
                            }
                            Button("启用") {
                                model.setSources(selectedSources, enabled: true)
                            }
                            Button("禁用") {
                                model.setSources(selectedSources, enabled: false)
                            }
                            Button("删除") {
                                model.deleteSources(selectedSources)
                                selection.removeAll()
                            }
                        }
                        .font(.system(size: 13))
                    }
                }
            }
            .navigationTitle("书源")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("导入") {
                        isImportPresented = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("校验") {
                        isCheckPresented = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("分享") {
                        isSharePresented = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("二维码") {
                        isQRCodePresented = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("分组") {
                        isGroupPresented = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("调试") {
                        isDebugPresented = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(isManaging ? "完成" : "管理") {
                        isManaging.toggle()
                        if !isManaging { selection.removeAll() }
                    }
                }
            }
            .sheet(isPresented: $isDebugPresented) {
                SourceDebugView(model: model)
            }
            .sheet(isPresented: $isGroupPresented) {
                NavigationStack {
                    SourceGroupView(model: model)
                }
            }
            .sheet(isPresented: $isImportPresented) {
                ImportSourceView(model: model, text: $importText)
            }
            .sheet(isPresented: $isCheckPresented) {
                NavigationStack {
                    SourceCheckView(model: model)
                }
            }
            .sheet(isPresented: $isLoginPresented) {
                if let loginSource {
                    NavigationStack {
                        SourceLoginView(source: loginSource, model: model)
                    }
                }
            }
            .sheet(isPresented: $isSharePresented) {
                ShareSheet(items: [model.exportedSources()])
            }
            .sheet(isPresented: $isQRCodePresented) {
                NavigationStack {
                    QRCodeView(text: model.exportedSources())
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                if let editingSource {
                    NavigationStack {
                        SourceEditorView(model: model, source: editingSource)
                    }
                }
            }
            .onAppear {
                model.reloadSources()
            }
        }
    }

    /// The sources of the multi-selection.
    private var selectedSources: [BookSource] {
        model.sources.filter { selection.contains($0.bookSourceUrl) }
    }
}

/// One source of the manager.
struct SourceRow: View {

    let source: BookSource
    var isSelected: Bool = false
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void
    var onSelect: (() -> Void)?
    var onLogin: (() -> Void)?
    var onEdit: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.bookSourceName)
                    .font(.system(size: 16))
                Text(source.bookSourceUrl)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                if let comment = source.bookSourceComment, !comment.isEmpty {
                    Text(comment)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if onSelect != nil {
                Button(isSelected ? "已选" : "选择", action: { onSelect?() })
                    .font(.system(size: 12))
            }
            if let onLogin, source.loginUrl != nil || source.loginUi != nil {
                Button("登录", action: onLogin)
                    .font(.system(size: 12))
            }
            if let onEdit {
                Button("编辑", action: onEdit)
                    .font(.system(size: 12))
            }
            Toggle("启用", isOn: Binding(get: { source.enabled }, set: onToggle))
                .labelsHidden()
            Button("删除", action: onDelete)
                .font(.system(size: 12))
                .foregroundColor(.red)
        }
        .padding(.vertical, 4)
    }
}

/// The import sheet — upstream `SourceManageActivity.importBookSource`.
struct ImportSourceView: View {

    @ObservedObject var model: LegadoAppModel
    @Binding var text: String

    public init(model: LegadoAppModel, text: Binding<String>) {
        self.model = model
        self._text = text
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("粘贴书源 JSON")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                TextEditor(text: $text)
                    .font(.system(size: 13))
                    .frame(minHeight: 240)
                    .border(Color.gray.opacity(0.3))
                Button("导入") {
                    model.importSources(json: text)
                }
                Spacer()
            }
            .padding(16)
            .navigationTitle("导入书源")
        }
    }
}
