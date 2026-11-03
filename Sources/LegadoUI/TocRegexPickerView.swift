//
//  TocRegexPickerView.swift
//  LegadoUI
//
//  The table of contents rule picker — upstream
//  `ui/book/toc/rule/TxtTocRuleDialog.kt` (the `menu_toc_regex` dialog of the
//  table of contents screen and of the reader).
//
//  The upstream shows the **managed** list of the TXT table of contents rules:
//  every row can be selected (it is then used for the current book), enabled
//  or disabled (it is then used for the automatic detection of every TXT
//  book), edited and deleted. The menu adds a rule, imports the rules from a
//  file, from the network, from a QR code or from the defaults, and shows the
//  help.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The table of contents rule picker.
public struct TocRegexPickerView: View {

    @ObservedObject var model: LegadoAppModel

    /// Called with the regex of the selected rule.
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var rules: [TxtTocRule] = []
    @State private var selectedName: String?
    @State private var editing: TxtTocRule?
    @State private var deleting: TxtTocRule?
    @State private var isFileImporterPresented = false
    @State private var isQRScannerPresented = false
    @State private var isImportUrlPresented = false
    @State private var isHelpPresented = false
    @State private var importUrl = ""
    @State private var qrResult: String?
    @State private var message: String?

    public init(model: LegadoAppModel, onSelect: @escaping (String) -> Void) {
        self.model = model
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(rules, id: \.id) { rule in
                    HStack {
                        Button {
                            selectedName = rule.name
                        } label: {
                            Image(systemName: rule.name == selectedName ? "largecircle.filled.circle" : "circle")
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
                                .font(.system(size: 16))
                            if let example = rule.example, !example.isEmpty {
                                Text(example)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { rule.enable },
                            set: { value in
                                setEnabled(value, for: rule)
                            }
                        ))
                        .labelsHidden()
                        Button("编辑") {
                            editing = rule
                        }
                        .font(.system(size: 13))
                        Button("删除") {
                            deleting = rule
                        }
                        .font(.system(size: 13))
                    }
                }
                if let message {
                    Section {
                        Text(message)
                            .font(.system(size: 13))
                    }
                }
            }
            .navigationTitle("TXT目录规则")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        // Upstream `menu_add`.
                        Button("新增") {
                            editing = TxtTocRule(id: 0, name: "", rule: "")
                        }
                        Button("导入本地") {
                            isFileImporterPresented = true
                        }
                        Button("导入网络") {
                            importUrl = ""
                            isImportUrlPresented = true
                        }
                        Button("导入二维码") {
                            isQRScannerPresented = true
                        }
                        // Upstream `menu_import_default`.
                        Button("导入默认") {
                            importDefaults()
                        }
                        Button("帮助") {
                            isHelpPresented = true
                        }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    // Upstream `tvOk` — the selected rule is returned.
                    Button("确定") {
                        confirm()
                    }
                }
            }
            .sheet(item: $editing) { rule in
                TxtTocRuleEditor(rule: rule) { saved in
                    model.saveTxtTocRule(saved)
                    reload()
                }
            }
            .alert("删除", isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            )) {
                Button("删除") {
                    if let deleting {
                        try? model.environment.store.deleteTxtTocRule(deleting)
                    }
                    deleting = nil
                    reload()
                }
                Button("取消", role: ButtonRole.cancel) {
                    deleting = nil
                }
            } message: {
                Text(deleting.map { "确定删除?\n\($0.name)" } ?? "")
            }
            .sheet(isPresented: $isQRScannerPresented) {
                NavigationStack {
                    QRScannerView(result: $qrResult)
                }
            }
            .sheet(isPresented: $isHelpPresented) {
                NavigationStack {
                    TxtTocRuleHelpView()
                }
            }
            .alert("导入网络", isPresented: $isImportUrlPresented) {
                TextField("url", text: $importUrl)
                Button("导入") {
                    let url = importUrl
                    isImportUrlPresented = false
                    importOnline(url)
                }
                Button("取消", role: ButtonRole.cancel) {
                    isImportUrlPresented = false
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: TxtTocRuleView.contentTypes,
                onCompletion: { result in
                    importFile(result)
                }
            )
            .onChange(of: qrResult) { _, value in
                guard let value, !value.isEmpty else { return }
                qrResult = nil
                Task {
                    message = await DocumentImporter.importText(value, kind: .txtRule, model: model)
                    reload()
                }
            }
            .onAppear {
                reload()
            }
        }
    }

    // MARK: - The actions

    private func reload() {
        rules = (try? model.environment.store.allTxtTocRules()) ?? []
        if selectedName == nil, let first = rules.first {
            selectedName = first.name
        }
    }

    /// Applies the selected rule — upstream `onTocRegexDialogResult`.
    private func confirm() {
        guard let rule = rules.first(where: { $0.name == selectedName }) else {
            message = "请选择一个规则"
            return
        }
        onSelect(rule.rule)
        dismiss()
    }

    private func setEnabled(_ enabled: Bool, for rule: TxtTocRule) {
        var changed = rule
        changed.enable = enabled
        try? model.environment.store.insert(changed)
        reload()
    }

    private func importDefaults() {
        do {
            try DefaultData.importDefaultTocRules(store: model.environment.store)
            message = "已导入默认规则"
        } catch {
            message = "导入失败"
        }
        reload()
    }

    private func importOnline(_ url: String) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        Task {
            message = await DocumentImporter.importText(trimmed, kind: .txtRule, model: model)
            reload()
        }
    }

    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task {
            message = await DocumentImporter.importText(url.absoluteString, kind: .txtRule, model: model)
            reload()
        }
    }
}

/// The help of the table of contents rules — upstream
/// `app/src/main/assets/web/help/md/txtTocRuleHelp.md`.
public struct TxtTocRuleHelpView: View {

    public init() {}

    public var body: some View {
        ScrollView {
            Text(TxtTocRuleHelp.text)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .navigationTitle("TXT目录规则帮助")
    }
}

/// The text of the help of the table of contents rules.
public enum TxtTocRuleHelp {
    public static let text = """
    ## Txt目录正则说明

    ### 菜单区

    - 新增目录规则，当Legado自带的规则不能够满足需求时，用户可根据自己的情况自定义目录规则
    - 导入默认规则 在旧版本中，Legado自带的规则不会随着软件的更新而更新。用户需要使用最新规则或对自带规则修改后需要重置时，可点击 导入默认规则。
    - 网络导入 为了方便异步调试以及用户导入他人的目录规则，Legado增加目录规则的网络导入功能。
    - 拆分超长章节 根据目录正则分章时若单章超过三万字左右将自动分为多章

    ### 操作区

    - 按钮① 选中时表示当前书籍使用的目录正则 如果Legado的自动识别的目录情况不太理想，用户可以手动点击各个规则前面的按钮，临时对本书启用该规则，该按钮仅针对当前书籍生效。
    - 按钮组② 左边的开关被点亮时，表示该规则将会在自动识别目录时尝试进行匹配，该规则针对所有TXT书籍生效；中间的按钮表示编辑当前规则；右边的按钮表示删除当前规则。
    - 按钮组③ 在当前界面进行操作后，需要点击确认按钮使得选择生效。
    """
}
