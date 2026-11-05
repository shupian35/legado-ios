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
    @State private var isSharePresented = false
    @State private var exportedFileURL: URL?

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
            ToolbarItem(placement: .secondaryAction) {
                // Upstream `TxtTocRuleActivity.menu_export_selection` — the file
                // "exportTxtTocRule.json".
                Button("导出") {
                    export(rules: rules, fileName: "exportTxtTocRule.json")
                }
            }
        }
        .sheet(item: $editing) { rule in
            TxtTocRuleEditor(rule: rule) { saved in
                model.saveTxtTocRule(saved)
                reload()
            }
        }
        .sheet(isPresented: $isSharePresented) {
            if let exportedFileURL {
                ShareSheet(items: [exportedFileURL])
            }
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        rules = (try? model.environment.store.allTxtTocRules()) ?? []
    }

    /// Writes the rules into a file — upstream
    /// `TxtTocRuleActivity.menu_export_selection`.
    private func export(rules: [TxtTocRule], fileName: String) {
        let json = DocumentExport.json(rules, row: { $0.row })
        guard let data = json.data(using: .utf8) else { return }
        do {
            exportedFileURL = try DocumentExporter.write(data, fileName: fileName)
            isSharePresented = true
        } catch {
            AppLog.shared.put("导出失败：\(error.localizedDescription)", error: error)
        }
    }

    /// The accepted file types — upstream `AppPattern` accepts `txt` and
    /// `json` for the table of contents rules.
    public static var contentTypes: [UTType] {
        var types: [UTType] = [.data]
        for ext in ["txt", "json"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
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
    @State private var isSharePresented = false
    @State private var exportedFileURL: URL?
    /// The import of a document — upstream `DictRuleActivity.menu_import_onLine`.
    @State private var isImportPresented = false
    @State private var importText: String = ""

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
                // Upstream `DictRuleActivity.menu_import_onLine` — the import
                // of a document with the history of the urls.
                Button("导入") {
                    importText = ""
                    isImportPresented = true
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // Upstream `DictRuleViewModel.restoreDefault`.
                Button("恢复默认") {
                    try? DefaultData.importDefaultDictRules(store: model.environment.store)
                    reload()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                // Upstream `DictRuleActivity.menu_export_selection` — the file
                // "exportDictRule.json".
                Button("导出") {
                    export(rules: rules, fileName: "exportDictRule.json")
                }
            }
        }
        .sheet(item: $editing) { rule in
            DictRuleEditor(rule: rule) { saved in
                model.saveDictRule(saved)
                reload()
            }
        }
        .sheet(isPresented: $isImportPresented) {
            ImportDocumentView(model: model, kind: .dictRule, text: $importText)
        }
        .sheet(isPresented: $isSharePresented) {
            if let exportedFileURL {
                ShareSheet(items: [exportedFileURL])
            }
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        rules = (try? model.environment.store.allDictRules()) ?? []
    }

    /// Writes the rules into a file — upstream
    /// `DictRuleActivity.menu_export_selection`.
    private func export(rules: [DictRule], fileName: String) {
        let json = DocumentExport.json(rules, row: { $0.row })
        guard let data = json.data(using: .utf8) else { return }
        do {
            exportedFileURL = try DocumentExporter.write(data, fileName: fileName)
            isSharePresented = true
        } catch {
            AppLog.shared.put("导出失败：\(error.localizedDescription)", error: error)
        }
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
///
/// Upstream `app/src/main/java/io/legado/app/ui/about/ReadRecordActivity.kt`:
/// the search field, the total reading time, the sorting menu, the
/// "记录" switch, the 删除 button and the rows (the book name, the reading
/// duration, the last reading date, the per row delete).
public struct ReadRecordView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var records: [ReadRecordShow] = []
    @State private var totalTime: Int64 = 0
    @State private var keyword = ""
    @State private var sort: ReadRecordSort = .name
    @State private var isDeleteAllPresented = false
    @State private var deleteTarget: ReadRecordShow?
    @State private var openedBook: Book?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    /// The model of the records — upstream `ReadRecordDao`.
    private var recordModel: ReadRecordModel {
        ReadRecordModel(store: model.environment.store)
    }

    public var body: some View {
        List {
            Section {
                HStack {
                    Text("总阅读时长")
                    Spacer()
                    Text(totalTime > 0 ? ReadRecordShow(bookName: "", readTime: totalTime).readDurationText : "0秒")
                        .foregroundColor(.secondary)
                }
                if !records.isEmpty {
                    Button(role: .destructive) {
                        isDeleteAllPresented = true
                    } label: {
                        Label("清空阅读记录", systemImage: "trash")
                    }
                }
            }

            Section {
                ForEach(records) { record in
                    HStack {
                        Button {
                            open(record)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.bookName)
                                Text("阅读时长 \(record.readDurationText)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                if !record.lastReadText.isEmpty {
                                    Text(record.lastReadText)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        Spacer()
                        Button(role: .destructive) {
                            deleteTarget = record
                        } label: {
                            Text("删除")
                        }
                        .font(.system(size: 12))
                    }
                }
            }
        }
        .navigationTitle("阅读记录")
        .searchable(text: $keyword, prompt: "搜索")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Picker("排序", selection: $sort) {
                        ForEach(ReadRecordSort.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    Toggle("记录", isOn: Binding(
                        get: { model.environment.settings.enableReadRecord },
                        set: { model.environment.settings.enableReadRecord = $0 }
                    ))
                } label: {
                    Text("排序")
                }
            }
        }
        .onAppear {
            sort = model.environment.localConfig.readRecordSort
            reload()
        }
        .onChange(of: keyword) { _ in reload() }
        .onChange(of: sort) { newValue in
            model.environment.localConfig.readRecordSort = newValue
            reload()
        }
        .alert("删除", isPresented: $isDeleteAllPresented) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) {
                try? recordModel.clear()
                reload()
            }
        } message: {
            Text("确定要清空全部阅读记录吗？")
        }
        .alert("删除", isPresented: Binding(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) {
                if let target = deleteTarget {
                    try? recordModel.delete(bookName: target.bookName)
                }
                deleteTarget = nil
                reload()
            }
        } message: {
            Text("确定要删除\n\(deleteTarget?.bookName ?? "")\n的阅读记录吗？")
        }
        .sheet(item: $openedBook) { book in
            NavigationStack {
                BookDetailView(model: model, book: book)
            }
        }
    }

    private func reload() {
        records = (try? recordModel.records(searchKey: keyword, sort: sort)) ?? []
        totalTime = (try? recordModel.totalTime()) ?? 0
    }

    /// Opens the book — upstream `startActivityForBook(book)`.
    ///
    /// When the book is not on the shelf the upstream opens the search with
    /// the name of the book.
    private func open(_ record: ReadRecordShow) {
        let books = (try? model.environment.bookshelf().search(record.bookName)) ?? []
        if let book = books.first {
            openedBook = book
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
    /// The folder picker of the local books — upstream
    /// `OtherConfigFragment`'s 书籍存储位置.
    @State private var isSelectingBookFolder = false

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
                // Upstream `AppConfig.defaultBookTreeUri` — the folder the
                // imported books are copied into.
                Text("存储位置：\(model.localBookDirectory().path)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Button("选择书籍存储位置") {
                    isSelectingBookFolder = true
                }
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
        .fileImporter(
            isPresented: $isSelectingBookFolder,
            allowedContentTypes: [.folder]
        ) { result in
            if case let .success(url) = result {
                model.setLocalBookDirectory(url)
                message = "已设置书籍存储位置"
            }
        }
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
    @State private var logMessage: String?
    @State private var contactMessage: String?

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
            Section("项目") {
                // Upstream `AboutFragment.onPreferenceTreeClick` — the
                // contributors page.
                Link("贡献者", destination: URL(string: "https://github.com/gedoor/legado/graphs/contributors")!)
            }
            Section("联系") {
                // Upstream `AboutFragment.onPreferenceTreeClick` — the mail
                // address (`R.string.email`) and the public account
                // (`R.string.legado_gzh`, which is copied to the clipboard).
                Link("邮箱", destination: URL(string: "mailto:gekunfei@live.com")!)
                Button("公众号") {
                    copyPublicAccount()
                }
                if let contactMessage {
                    Text(contactMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            Section("文档") {
                NavigationLink(AboutDocument.updateLog.title) {
                    MarkdownView(document: .updateLog)
                }
                NavigationLink(AboutDocument.license.title) {
                    MarkdownView(document: .license)
                }
                NavigationLink(AboutDocument.disclaimer.title) {
                    MarkdownView(document: .disclaimer)
                }
                NavigationLink(AboutDocument.privacyPolicy.title) {
                    MarkdownView(document: .privacyPolicy)
                }
            }
            Section("帮助") {
                NavigationLink("规则帮助") {
                    RuleHelpView()
                }
            }
            Section("日志") {
                NavigationLink("崩溃日志") {
                    CrashLogView(model: model)
                }
                Button("保存日志") {
                    saveLog()
                }
                if let logMessage {
                    Text(logMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
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
                    // Upstream `UpdateDialog` — the release note is rendered
                    // as Markdown.
                    NavigationLink("更新日志") {
                        MarkdownView(
                            title: updateInfo.versionName,
                            markdown: updateInfo.note
                        )
                    }
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

    /// Saves the log into the backup directory — upstream
    /// `AboutFragment.saveLog`.
    private func saveLog() {
        do {
            try FileManager.default.createDirectory(
                at: backupDirectory,
                withIntermediateDirectories: true
            )
            let file = try LogExporter.export(to: backupDirectory)
            logMessage = "已保存至 \(file.lastPathComponent)"
        } catch {
            logMessage = "保存日志出错：\(error.localizedDescription)"
            AppLog.shared.put("保存日志出错\n\(error.localizedDescription)", error: error)
        }
    }

    /// The directory the local backups live in — upstream `PreferKey.backupPath`.
    private var backupDirectory: URL {
        if let path = model.environment.settings.backupPath, !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("backup", isDirectory: true)
    }

    /// Copies the name of the public account — upstream `gzGzh` calls
    /// `sendToClip(getString(R.string.legado_gzh))`.
    private func copyPublicAccount() {
        UIPasteboardShim.copy("开源阅读")
        contactMessage = "已复制公众号名称：开源阅读"
    }

    private func checkUpdate() {
        updateMessage = "正在检查…"
        Task {
            do {
                let info = try await AppUpdateChecker.check(
                    currentVersion: LegadoAppInfo.version,
                    variant: model.environment.settings.updateVariant,
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
