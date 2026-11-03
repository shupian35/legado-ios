//
//  MineViews.swift
//  LegadoUI
//
//  The screens of the "我的" tab.
//
//  Upstream `ui/main/MainActivity` opens these from the "我的" menu:
//  the TXT table of contents rules (`ui/book/toc/rule/TxtTocRuleActivity`),
//  the dictionary rules (`ui/dict/rule/DictRuleActivity`), the reading
//  records (`ui/about/ReadRecordActivity`), the file management
//  (`ui/file/FileManageActivity`), the about screen (`ui/about/AboutActivity`)
//  and the help.
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

// MARK: - The TXT table of contents rules

/// The TXT table of contents rules — upstream `TxtTocRuleActivity`.
public struct TxtTocRuleView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var rules: [TxtTocRule] = []
    @State private var editing: TxtTocRule?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            ForEach(rules, id: \.id) { rule in
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name)
                        .font(.system(size: 16))
                    Text(rule.rule)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editing = rule
                }
            }
        }
        .navigationTitle("TXT目录规则")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("添加") {
                    editing = TxtTocRule(id: 0, name: "", rule: "")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // Upstream `TxtTocRuleViewModel.restoreDefault`.
                Button("恢复默认") {
                    try? DefaultData.importDefaultTocRules(store: model.environment.store)
                    reload()
                }
            }
        }
        .sheet(item: $editing) { rule in
            TxtTocRuleEditor(rule: rule) { saved in
                model.saveTxtTocRule(saved)
                reload()
            }
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        rules = (try? model.environment.store.allTxtTocRules()) ?? []
    }
}

/// The editor of a TXT table of contents rule.
struct TxtTocRuleEditor: View {

    @State var rule: TxtTocRule
    /// The example is optional — the editor keeps it as a plain string.
    @State var example: String = ""
    let onSave: (TxtTocRule) -> Void

    @Environment(\.dismiss) private var dismiss

    init(rule: TxtTocRule, onSave: @escaping (TxtTocRule) -> Void) {
        self.rule = rule
        self.onSave = onSave
        _example = State(initialValue: rule.example ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("规则") {
                    TextField("名称", text: $rule.name)
                    TextField("正则", text: $rule.rule)
                    TextField("示例", text: $example)
                    Toggle("启用", isOn: $rule.enable)
                }
            }
            .navigationTitle("TXT目录规则")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        var updated = rule
                        updated.example = example.isEmpty ? nil : example
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - The dictionary rules

/// The dictionary rules — upstream `DictRuleActivity`.
public struct DictRuleView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var rules: [DictRule] = []
    @State private var editing: DictRule?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            ForEach(rules, id: \.name) { rule in
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.name)
                    Text(rule.urlRule)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editing = rule
                }
            }
        }
        .navigationTitle("字典规则")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("添加") {
                    editing = DictRule(name: "", urlRule: "", showRule: "")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // Upstream `DictRuleViewModel.restoreDefault`.
                Button("恢复默认") {
                    try? DefaultData.importDefaultDictRules(store: model.environment.store)
                    reload()
                }
            }
        }
        .sheet(item: $editing) { rule in
            DictRuleEditor(rule: rule) { saved in
                model.saveDictRule(saved)
                reload()
            }
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        rules = (try? model.environment.store.allDictRules()) ?? []
    }
}

/// The editor of a dictionary rule.
struct DictRuleEditor: View {

    @State var rule: DictRule
    let onSave: (DictRule) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("规则") {
                    TextField("名称", text: $rule.name)
                    TextField("地址规则", text: $rule.urlRule)
                    TextField("显示规则", text: $rule.showRule)
                    Toggle("启用", isOn: $rule.enabled)
                }
            }
            .navigationTitle("字典规则")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        onSave(rule)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - The reading records

/// The reading records — upstream `ReadRecordActivity`.
public struct ReadRecordView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var records: [ReadRecord] = []

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            ForEach(records, id: \.bookName) { record in
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.bookName)
                    Text("阅读时长 \(record.readDurationText)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(record.lastReadText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("阅读记录")
        .onAppear {
            records = (try? model.environment.store.allReadRecords()) ?? []
        }
    }
}

// MARK: - The HTTP text to speech engines

/// The HTTP TTS engines — upstream `HttpTTSActivity`.
public struct HttpTTSView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var engines: [HttpTTS] = []
    @State private var editing: HttpTTS?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            ForEach(engines, id: \.id) { engine in
                VStack(alignment: .leading, spacing: 4) {
                    Text(engine.name)
                    Text(engine.url)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editing = engine
                }
            }
        }
        .navigationTitle("HTTP TTS")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("添加") {
                    editing = HttpTTS(id: 0, name: "", url: "")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // Upstream `SpeakEngineViewModel.restoreDefault`.
                Button("恢复默认") {
                    try? DefaultData.importDefaultHttpTTS(store: model.environment.store)
                    reload()
                }
            }
        }
        .sheet(item: $editing) { engine in
            HttpTTSEditor(engine: engine) { saved in
                model.saveHttpTTS(saved)
                reload()
            }
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        engines = (try? model.environment.store.allHttpTTS()) ?? []
    }
}

/// The editor of a HTTP TTS engine.
struct HttpTTSEditor: View {

    @State var engine: HttpTTS
    /// The optional fields are edited as plain strings.
    @State var contentType: String = ""
    @State var header: String = ""
    @State var loginUrl: String = ""
    let onSave: (HttpTTS) -> Void

    @Environment(\.dismiss) private var dismiss

    init(engine: HttpTTS, onSave: @escaping (HttpTTS) -> Void) {
        self.engine = engine
        self.onSave = onSave
        _contentType = State(initialValue: engine.contentType ?? "")
        _header = State(initialValue: engine.header ?? "")
        _loginUrl = State(initialValue: engine.loginUrl ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("引擎") {
                    TextField("名称", text: $engine.name)
                    TextField("地址", text: $engine.url)
                    TextField("内容类型（正则）", text: $contentType)
                    TextField("请求头（JSON）", text: $header)
                    TextField("登录地址", text: $loginUrl)
                }
            }
            .navigationTitle("HTTP TTS")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        var updated = engine
                        updated.contentType = contentType.isEmpty ? nil : contentType
                        updated.header = header.isEmpty ? nil : header
                        updated.loginUrl = loginUrl.isEmpty ? nil : loginUrl
                        onSave(updated)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - The file management

/// The file management — upstream `FileManageActivity`.
///
/// The upstream lists the cache folders, the downloaded books and the
/// backups; the port lists the same three groups and can delete them.
public struct FileManageView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var message: String?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section("书籍缓存") {
                Text("缓存目录：\(model.environment.cacheStorage?.layout.root.path ?? "未启用")")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Button("清空缓存", role: .destructive) {
                    clearCache()
                }
                // Upstream `ManageCacheActivity` — the per-book cache list.
                NavigationLink("缓存管理") {
                    CacheManageView(model: model)
                }
            }
            Section("本地书籍") {
                ForEach(model.localBooks, id: \.bookUrl) { book in
                    HStack {
                        Text(book.name)
                        Spacer()
                        Button("删除", role: .destructive) {
                            model.deleteLocalBook(book)
                        }
                    }
                }
            }
            Section("备份") {
                NavigationLink("备份与恢复") {
                    BackupView(model: model)
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
        .navigationTitle("文件管理")
        .onAppear {
            model.reloadLocalBooks()
        }
    }

    private func clearCache() {
        guard let storage = model.environment.cacheStorage else {
            message = "缓存未启用"
            return
        }
        for book in model.books {
            try? storage.clearCache(book: book)
        }
        message = "缓存已清空"
    }
}

// MARK: - The about screen

/// The about screen — upstream `AboutActivity`.
public struct AboutView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var updateMessage: String?
    @State private var updateInfo: AppUpdateInfo?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section("关于") {
                LabeledRow(title: "名称", value: "阅读")
                LabeledRow(title: "版本", value: LegadoAppInfo.version)
                LabeledRow(title: "上游包名", value: LegadoAppInfo.upstreamPackage)
            }
            Section("说明") {
                Text("这是 Android 阅读 (Legado) 的 iOS 移植版，保留了规则引擎、书源、本地书、朗读、漫画、备份与本地服务器等功能。")
                    .font(.system(size: 13))
            }
            Section("帮助") {
                NavigationLink("规则帮助") {
                    RuleHelpView()
                }
            }
            Section("更新") {
                // Upstream `AboutFragment.checkUpdate` — the GitHub release
                // check.
                Button("检查更新") {
                    checkUpdate()
                }
                if let updateInfo {
                    Text("发现新版本 \(updateInfo.versionName)")
                        .font(.system(size: 13))
                    Text(updateInfo.note)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Link("下载", destination: URL(string: updateInfo.downloadURL) ?? URL(string: "https://github.com/gedoor/legado")!)
                }
                if let updateMessage {
                    Text(updateMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("关于")
    }

    private func checkUpdate() {
        updateMessage = "正在检查…"
        Task {
            do {
                let info = try await AppUpdateChecker.check(
                    currentVersion: LegadoAppInfo.version,
                    httpClient: model.environment.httpClient
                )
                updateInfo = info
                updateMessage = nil
            } catch {
                updateInfo = nil
                if case AppUpdateError.alreadyLatest = error {
                    updateMessage = "已是最新版本"
                } else {
                    updateMessage = "检查更新失败：\(error.localizedDescription)"
                }
            }
        }
    }
}

/// A label + a value row.
struct LabeledRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}
