//
//  DirectLinkUploadView.swift
//  LegadoUI
//
//  The configuration of the direct link upload — the port of
//  `app/src/main/java/io/legado/app/ui/config/DirectLinkUploadConfig.kt`.
//
//  The upstream edits the rule of the service (the upload address, the rule
//  that extracts the download link, the name of the service and whether the
//  payload is zipped), can import one of the three default rules, copies and
//  pastes the rule and tests the upload.
//
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The configuration of the direct link upload — upstream
/// `ui/config/DirectLinkUploadConfig.kt`.
public struct DirectLinkUploadConfigView: View {

    @ObservedObject var model: LegadoAppModel

    /// The action of the confirmation — the caller may close the screen.
    var onSave: ((DirectLinkUploadRule) -> Void)?

    @State private var uploadUrl: String = ""
    @State private var downloadUrlRule: String = ""
    @State private var summary: String = ""
    @State private var compress: Bool = false
    @State private var message: String?
    @State private var isTesting = false
    @State private var isDefaultPickerPresented = false
    /// The result of the test upload — the upstream shows it in an alert.
    @State private var testResult: String?
    @State private var isTestResultPresented = false

    public init(model: LegadoAppModel, onSave: ((DirectLinkUploadRule) -> Void)? = nil) {
        self.model = model
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("上传地址") {
                    TextField("上传Url", text: $uploadUrl, axis: .vertical)
                }
                Section("下载地址规则") {
                    TextField("下载Url规则", text: $downloadUrlRule, axis: .vertical)
                }
                Section("注释") {
                    TextField("名称", text: $summary)
                }
                Section("压缩") {
                    Toggle("压缩上传", isOn: $compress)
                }
                if let message {
                    Section {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                Section {
                    Button(isTesting ? "测试中…" : "测试") {
                        test()
                    }
                    .disabled(isTesting)
                }
            }
            .navigationTitle("直链上传")
            .alert("result", isPresented: $isTestResultPresented, actions: {
                Button("好") {
                    isTestResultPresented = false
                }
                Button("复制文本") {
                    if let testResult {
                        UIPasteboardShim.copy(testResult)
                    }
                    isTestResultPresented = false
                }
            }, message: {
                Text(testResult ?? "")
            })
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("确定") {
                        save()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onSave?(currentRule)
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button("导入默认") {
                            isDefaultPickerPresented = true
                        }
                        Button("复制规则") {
                            copyRule()
                        }
                        Button("粘贴规则") {
                            pasteRule()
                        }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isDefaultPickerPresented) {
                NavigationStack {
                    List {
                        Section {
                            ForEach(Array(DirectLinkUpload.defaultRules.enumerated()), id: \.offset) { index, rule in
                                Button(rule.summary) {
                                    applyDefault(index: index)
                                    isDefaultPickerPresented = false
                                }
                            }
                        } header: {
                            Text("选择默认规则")
                        }
                    }
                    .navigationTitle("导入默认")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") {
                                isDefaultPickerPresented = false
                            }
                        }
                    }
                }
            }
            .onAppear {
                load()
            }
        }
    }

    /// The rule the form currently holds.
    private var currentRule: DirectLinkUploadRule {
        DirectLinkUploadRule(
            uploadUrl: uploadUrl,
            downloadUrlRule: downloadUrlRule,
            summary: summary,
            compress: compress
        )
    }

    /// Loads the stored rule — upstream `DirectLinkUploadConfig.onFragmentCreated`.
    private func load() {
        let rule = DirectLinkUpload.getRule(store: model.environment.settings.settingsStore)
        uploadUrl = rule.uploadUrl
        downloadUrlRule = rule.downloadUrlRule
        summary = rule.summary
        compress = rule.compress
    }

    /// Validates and stores the rule — upstream `getRule` + `putConfig`.
    private func save() {
        let rule = currentRule
        if rule.uploadUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "上传Url不能为空"
            return
        }
        if rule.downloadUrlRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "下载Url规则不能为空"
            return
        }
        if rule.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            message = "注释不能为空"
            return
        }
        DirectLinkUpload.putConfig(rule, store: model.environment.settings.settingsStore)
        onSave?(rule)
    }

    /// Copies the rule to the pasteboard — upstream `menu_copy_rule`.
    private func copyRule() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(currentRule), let json = String(data: data, encoding: .utf8) {
            UIPasteboardShim.copy(json)
        }
    }

    /// Pastes the rule from the pasteboard — upstream `menu_paste_rule`.
    private func pasteRule() {
        guard let json = UIPasteboardShim.paste(), !json.isEmpty else {
            message = "剪贴板为空或格式不对"
            return
        }
        guard let data = json.data(using: .utf8),
              let rule = try? JSONDecoder().decode(DirectLinkUploadRule.self, from: data) else {
            message = "剪贴板为空或格式不对"
            return
        }
        uploadUrl = rule.uploadUrl
        downloadUrlRule = rule.downloadUrlRule
        summary = rule.summary
        compress = rule.compress
    }

    /// Applies one of the default rules — upstream `importDefault` (the
    /// upstream shows a selector over the default rules).
    private func applyDefault(index: Int) {
        guard DirectLinkUpload.defaultRules.indices.contains(index) else { return }
        let rule = DirectLinkUpload.defaultRules[index]
        uploadUrl = rule.uploadUrl
        downloadUrlRule = rule.downloadUrlRule
        summary = rule.summary
        compress = rule.compress
    }

    /// Uploads a test file — upstream `test`.
    private func test() {
        let rule = currentRule
        guard !rule.uploadUrl.isEmpty, !rule.downloadUrlRule.isEmpty else {
            message = "上传Url不能为空"
            return
        }
        isTesting = true
        message = nil
        Task {
            do {
                let url = try await DirectLinkUpload.upload(
                    fileName: "test.json",
                    file: Data("{}".utf8),
                    contentType: "application/json",
                    rule: rule,
                    dependencies: model.environment.dependencies()
                )
                // The upstream shows the result in an alert with a copy button.
                testResult = url
                isTestResultPresented = true
            } catch {
                testResult = error.localizedDescription
                isTestResultPresented = true
            }
            isTesting = false
        }
    }
}
