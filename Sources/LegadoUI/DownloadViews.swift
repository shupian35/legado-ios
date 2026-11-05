//
//  DownloadViews.swift
//  LegadoUI
//
//  The offline cache — upstream
//  `app/src/main/java/io/legado/app/ui/book/read/BaseReadBookActivity.kt:266`
//  (`showDownloadDialog`) and
//  `app/src/main/java/io/legado/app/ui/book/cache/CacheActivity.kt`
//  (the cache / download screen).
//
//  The download engine itself is the port of upstream `model/CacheBook.kt` and
//  lives in the core (`Sources/LegadoCore/Net/BookCache.swift`); this file is
//  only the user interface.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The reader's "离线缓存" dialog — upstream `showDownloadDialog()`.
///
/// The dialog asks for the first and the last chapter of the range to cache;
/// the upstream submits `start - 1` and `end - 1` (the chapters are 0-based).
public struct ReaderDownloadDialog: View {

    @ObservedObject var model: LegadoAppModel
    let book: Book

    @State private var start: String = ""
    @State private var end: String = ""
    @State private var message: String?

    @Environment(\.dismiss) private var dismiss

    public init(model: LegadoAppModel, book: Book) {
        self.model = model
        self.book = book
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("离线缓存")
                .font(.system(size: 16, weight: .semibold))
            TextField("起始章节", text: $start)
                .textFieldStyle(.roundedBorder)
            TextField("结束章节", text: $end)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("确定") { submit() }
            }
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onAppear {
            start = String(book.durChapterIndex + 1)
            end = String(book.totalChapterNum)
        }
    }

    private func submit() {
        let first = Int(start) ?? 1
        let last = Int(end) ?? Int(book.totalChapterNum)
        guard first >= 1 else {
            message = "起始章节必须大于0"
            return
        }
        Task {
            await model.startCaching(book: book, start: first - 1, end: last - 1)
            dismiss()
        }
    }
}

/// The cache / download screen — upstream `ui/book/cache/CacheActivity.kt`.
///
/// It lists the books of the shelf with their download progress and offers
/// the per-book actions (cache from the current chapter, cache everything,
/// stop, export) plus the toolbar actions (cache everything, stop everything,
/// export everything, the app log).
public struct DownloadManageView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var books: [Book] = []
    @State private var isLogPresented = false
    @State private var message: String?
    /// The group filter — upstream `CacheActivity.menu_book_group`.
    @State private var groupId: Int64 = BookGroup.Id.all
    /// The name template of the exported file — upstream
    /// `AppConfig.episodeExportFileName`.
    @State private var exportFileName = ""
    /// The folder the exports are written to — upstream
    /// `CacheActivity.selectExportFolder`.
    @State private var exportFolder = ""
    /// The charset of the exported text — upstream `AppConfig.exportCharset`.
    @State private var exportCharset = "UTF-8"
    /// The export format (0 = txt, 1 = epub) — upstream `AppConfig.exportType`.
    @State private var exportType = 0
    /// The file name template of the export — upstream
    /// `AppConfig.bookExportFileName` (a JavaScript template).
    @State private var exportNameTemplate = ""
    /// The file that was exported last — it is offered to the share sheet.
    @State private var exportedURL: URL?
    @State private var isSharePresented = false
    /// The dialog that edits the file name template — upstream
    /// `CacheActivity.alertExportFileName`.
    @State private var isNameTemplatePresented = false
    @State private var nameTemplateDraft = ""
    /// The dialog that picks the export type — upstream
    /// `CacheActivity.showExportTypeConfig`.
    @State private var isTypePresented = false
    /// The dialog that picks the character set — upstream
    /// `CacheActivity.showCharsetConfig`.
    @State private var isCharsetPresented = false
    @State private var charsetDraft = "UTF-8"
    /// The folder picker — upstream `CacheActivity.selectExportFolder`.
    @State private var isSelectingExportFolder = false
    /// The dialog of the custom chapter export — upstream
    /// `CacheActivity.configExportSection`.
    @State private var isCustomExportPresented = false
    @State private var customScope = ""
    @State private var customSplitSize = 1
    /// The book the custom export dialog was opened for.
    @State private var customExportBook: Book?
    /// Whether the export of every book runs in parallel — upstream
    /// `AppConfig.parallelExportBook`.
    @State private var isExporting = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            // The generic file downloads — upstream
            // `app/src/main/java/io/legado/app/service/DownloadService.kt`.
            // The upstream writes the files into the public Download folder
            // (which iOS does not offer), so the port lists them here.
            if !model.downloads.isEmpty {
                Section("文件下载") {
                    ForEach(model.downloads) { info in
                        DownloadFileRow(info: info, model: model)
                    }
                    Button("清除已完成") {
                        model.downloadService?.removeFinished()
                        model.downloads = model.downloadService?.items ?? []
                    }
                }
            }
            if books.isEmpty {
                Text("没有书籍")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            ForEach(books, id: \.bookUrl) { book in
                DownloadBookRow(
                    book: book,
                    progress: model.cacheProgress[book.bookUrl],
                    onCache: { startCaching(book, from: Int(book.durChapterIndex)) },
                    onCacheAll: { startCaching(book, from: 0) },
                    onStop: { Task { await model.stopCaching(book: book) } },
                    onExport: { export(book) }
                )
            }
        }
        .navigationTitle(groupTitle)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("更多") {
                    Button("全部缓存") {
                        for book in books {
                            startCaching(book, from: 0)
                        }
                    }
                    Button("全部停止") {
                        Task {
                            for book in books {
                                await model.stopCaching(book: book)
                            }
                        }
                    }
                    // Upstream `CacheActivity.menu_export_all`.
                    Button("导出全部") {
                        exportAll()
                    }
                    // Upstream `CacheActivity.menu_enable_replace` and the
                    // other export switches — they are the `AppConfig` flags
                    // the export service reads.
                    Section("导出选项") {
                        Toggle("净化替换", isOn: settingBinding(.exportUseReplace))
                        Toggle("自定义导出章节", isOn: settingBinding(.enableCustomExport))
                        Toggle("不包含章节名", isOn: settingBinding(.exportNoChapterName))
                        Toggle("导出到WebDAV", isOn: settingBinding(.exportToWebDav))
                        Toggle("导出图片到文件夹", isOn: settingBinding(.exportPictureFile))
                        Toggle("并行导出书籍", isOn: settingBinding(.parallelExportBook))
                    }
                    Section("导出配置") {
                        // Upstream `CacheActivity.showExportTypeConfig` — the
                        // selector with the two export types.
                        Button("导出类型：\(exportFormat.displayName)") {
                            isTypePresented = true
                        }
                        // Upstream `CacheActivity.showCharsetConfig`.
                        Button("导出字符集：\(exportCharset)") {
                            charsetDraft = exportCharset
                            isCharsetPresented = true
                        }
                        // Upstream `CacheActivity.alertExportFileName` — the
                        // file name is a JavaScript template with the
                        // variables `name`, `author` and `epubIndex`.
                        Button("导出文件名：\(exportNameTemplate.isEmpty ? "默认" : exportNameTemplate)") {
                            nameTemplateDraft = exportNameTemplate
                            isNameTemplatePresented = true
                        }
                        // Upstream `CacheActivity.menu_export_folder` — the
                        // folder the exports are written into.
                        Button("导出文件夹：\(exportFolder.isEmpty ? "默认" : exportFolder)") {
                            isSelectingExportFolder = true
                        }
                    }
                    // Upstream `CacheActivity.menu_book_group` — the submenu
                    // with every group of the shelf.
                    Section("分组筛选") {
                        Button {
                            groupId = BookGroup.Id.all
                            reload()
                        } label: {
                            Label("全部", systemImage: groupId == BookGroup.Id.all ? "checkmark" : "")
                        }
                        ForEach(model.groups) { group in
                            Button {
                                groupId = group.groupId
                                reload()
                            } label: {
                                Label(
                                    group.groupName,
                                    systemImage: groupId == group.groupId ? "checkmark" : ""
                                )
                            }
                        }
                    }
                    Button("日志") {
                        isLogPresented = true
                    }
                }
            }
        }
        .sheet(isPresented: $isLogPresented) {
            AppLogView()
        }
        // Upstream `CacheActivity.showExportTypeConfig` — the selector with
        // the two export types.
        .sheet(isPresented: $isTypePresented) {
            ExportTypeSheet(current: exportFormat) { type in
                exportType = type.rawValue
                model.environment.settings.exportFormat = type
                isTypePresented = false
            }
        }
        // Upstream `CacheActivity.showCharsetConfig` — the character set of
        // the TXT export.
        .sheet(isPresented: $isCharsetPresented) {
            ExportCharsetSheet(current: charsetDraft) { value in
                exportCharset = value
                model.environment.settings.exportCharset = value
                isCharsetPresented = false
            }
        }
        // Upstream `CacheActivity.configExportSection` — the custom export of
        // a chapter range, split into several EPUB files.
        .sheet(isPresented: $isCustomExportPresented) {
            CustomExportSheet(
                scope: $customScope,
                splitSize: $customSplitSize,
                onExportAll: {
                    isCustomExportPresented = false
                    if let book = customExportBook { export(book) }
                },
                onExportScope: {
                    isCustomExportPresented = false
                    if let book = customExportBook { exportScope(book) }
                }
            )
        }
        // Upstream `CacheActivity.selectExportFolder` — the folder the
        // exports are written into.
        .fileImporter(
            isPresented: $isSelectingExportFolder,
            allowedContentTypes: [.folder]
        ) { result in
            if case let .success(url) = result {
                selectExportFolder(url)
            }
        }
        // The exported file is offered to the share sheet — the upstream
        // writes it into the folder the user picked, the port writes it into
        // the documents directory and lets the user send it on.
        .sheet(isPresented: $isSharePresented) {
            if let exportedURL {
                ShareSheet(items: [exportedURL])
            }
        }
        // Upstream `CacheActivity.alertExportFileName` — the file name is a
        // JavaScript template with the variables `name`, `author` and
        // `epubIndex`.
        .alert("导出文件名", isPresented: $isNameTemplatePresented) {
            TextField("文件名规则", text: $nameTemplateDraft)
            Button("取消") { isNameTemplatePresented = false }
            Button("确定") {
                exportNameTemplate = nameTemplateDraft
                model.environment.settings.bookExportFileName =
                    nameTemplateDraft.isEmpty ? nil : nameTemplateDraft
                isNameTemplatePresented = false
            }
        } message: {
            Text("可用变量：name（书名）、author（作者）、epubIndex（分卷序号）。留空使用默认名称。")
        }
        .alert("缓存管理", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        books = (try? model.environment.bookshelf().books(
            inGroup: groupId,
            settings: model.environment.settings
        )) ?? []
        exportType = model.environment.settings.exportType
        exportCharset = model.environment.settings.exportCharset.isEmpty
            ? "UTF-8"
            : model.environment.settings.exportCharset
        exportFileName = model.environment.settings.string(.episodeExportFileName) ?? ""
        exportNameTemplate = model.environment.settings.bookExportFileName ?? ""
        exportFolder = (try? model.environment.store.cache(
            "exportBookPath",
            now: Int64(Date().timeIntervalSince1970 * 1000)
        )) ?? ""
        Task {
            for book in books {
                await model.refreshCacheProgress(bookUrl: book.bookUrl)
            }
        }
    }

    private func startCaching(_ book: Book, from start: Int) {
        Task {
            await model.startCaching(book: book, start: start, end: Int.max)
            await model.refreshCacheProgress(bookUrl: book.bookUrl)
        }
    }

    private func export(_ book: Book) {
        // Upstream `CacheActivity.export` — the custom export dialog is only
        // shown for the EPUB format (`utils.enableCustomExport`).
        if model.environment.settings.enableCustomExport,
           exportFormat == .epub {
            customExportBook = book
            isCustomExportPresented = true
            return
        }
        let task = Task {
            do {
                let written = try await model.exportBookToFile(
                    book: book,
                    format: exportType == 0 ? .txt : .epub,
                    options: exportOptions(for: book)
                )
                exportedURL = written.url
                isSharePresented = true
                message = "已导出：\(written.fileName)"
            } catch {
                message = "导出失败：\(error.localizedDescription)"
            }
        }
        // The 取消 action of the export notification stops the export —
        // upstream `ExportBookService.stop`.
        model.exportTask.task = task
    }

    /// Exports a chapter range of a book as several EPUB files — upstream
    /// `CacheActivity.configExportSection` → `ExportBookService.CustomExporter`.
    private func exportScope(_ book: Book) {
        guard ExportScope.isValid(customScope) else {
            message = "请输入正确的范围，例如 1-5,8,10-18"
            return
        }
        let scope = ExportScope.parse(customScope)
        guard !scope.isEmpty else {
            message = "请输入正确的范围，例如 1-5,8,10-18"
            return
        }
        let task = Task {
            do {
                let written = try await model.exportBookParts(
                    book: book,
                    options: exportOptions(for: book),
                    scope: scope,
                    splitSize: max(1, customSplitSize)
                )
                if let first = written.first {
                    exportedURL = first.url
                    isSharePresented = true
                }
                message = "已导出 \(written.count) 个文件"
            } catch {
                message = "导出失败：\(error.localizedDescription)"
            }
        }
        // The 取消 action of the export notification stops the export —
        // upstream `ExportBookService.stop`.
        model.exportTask.task = task
    }

    /// Stores the folder the exports are written into — upstream
    /// `ACache.get().put(exportBookPathKey, path)`.
    private func selectExportFolder(_ url: URL) {
        exportFolder = url.path
        model.setExportDirectory(url)
    }

    /// Exports every book of the list — upstream `CacheActivity.exportAll`.
    ///
    /// The upstream runs the exports in parallel when
    /// `AppConfig.parallelExportBook` is on (`AppConst.MAX_THREAD` threads).
    private func exportAll() {
        let list = books
        let parallel = model.environment.settings.parallelExportBook
        let task = Task {
            isExporting = true
            defer { isExporting = false }
            var exported = 0
            var failed = 0
            var last: URL?
            if parallel {
                await withTaskGroup(of: URL?.self) { group in
                    var index = 0
                    let limit = min(list.count, 9)
                    while index < list.count {
                        if Task.isCancelled { break }
                        if index >= limit {
                            if let url = await group.next() {
                                last = url
                                exported += 1
                            } else {
                                failed += 1
                            }
                        }
                        let book = list[index]
                        group.addTask {
                            return try? await model.exportBookToFile(
                                book: book,
                                format: exportType == 0 ? .txt : .epub,
                                options: exportOptions(for: book)
                            ).url
                        }
                        index += 1
                    }
                    while let url = await group.next() {
                        if let url {
                            last = url
                            exported += 1
                        } else {
                            failed += 1
                        }
                    }
                }
            } else {
                for book in list {
                    if Task.isCancelled { break }
                    do {
                        let written = try await model.exportBookToFile(
                            book: book,
                            format: exportType == 0 ? .txt : .epub,
                            options: exportOptions(for: book)
                        )
                        last = written.url
                        exported += 1
                    } catch {
                        failed += 1
                    }
                }
            }
            message = failed == 0
                ? "已导出 \(exported) 本书"
                : "已导出 \(exported) 本，失败 \(failed) 本"
            if let last {
                exportedURL = last
                isSharePresented = true
            }
        }
        // The 取消 action of the export notification stops the export —
        // upstream `ExportBookService.stop`.
        model.exportTask.task = task
    }

    /// The options of the export — upstream `AppConfig.exportUseReplace`,
    /// `exportNoChapterName` and `exportPictureFile`.
    private func exportOptions(for book: Book) -> BookExportOptions {
        let settings = model.environment.settings
        return BookExportOptions(
            includeChapterTitle: !settings.exportNoChapterName,
            useReplaceRule: settings.exportUseReplace,
            exportPictureFile: settings.exportPictureFile,
            fileName: exportNameTemplate.isEmpty ? nil : exportNameTemplate
        )
    }

    /// The export format — upstream `AppConfig.exportType`.
    private var exportFormat: ExportType {
        ExportType(rawValue: exportType) ?? .txt
    }

    /// A binding for one of the export switches of the upstream — the value
    /// is stored in the preferences.
    private func settingBinding(_ key: SettingsKey) -> Binding<Bool> {
        Binding(
            get: { model.environment.settings.bool(key, default: false) },
            set: { model.environment.settings.set($0, for: key) }
        )
    }

    /// The title of the screen — upstream `CacheActivity` shows the name of
    /// the group in the subtitle.
    private var groupTitle: String {
        guard groupId != BookGroup.Id.all else { return "缓存管理" }
        let name = model.groups.first { $0.groupId == groupId }?.groupName ?? ""
        return "筛选 • \(name)"
    }
}

/// A row of the file download list — upstream
/// `app/src/main/java/io/legado/app/service/DownloadService.kt`.
///
/// The upstream has no screen for the downloads (the files land in the public
/// Download folder); the port lists them, so that the user can cancel a
/// download or send the finished file on.
public struct DownloadFileRow: View {

    let info: DownloadInfo
    @ObservedObject var model: LegadoAppModel

    @State private var isSharePresented = false

    public init(info: DownloadInfo, model: LegadoAppModel) {
        self.info = info
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.request.fileName)
                        .font(.system(size: 15))
                        .lineLimit(1)
                    Text(info.status.stateText)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if info.status.isFinished {
                    Button("分享") {
                        isSharePresented = true
                    }
                    .font(.system(size: 13))
                } else {
                    // The 取消 action of the notification of the download —
                    // upstream `IntentAction.stop`.
                    Button("取消") {
                        model.downloadService?.cancel(id: info.id)
                    }
                    .font(.system(size: 13))
                }
            }
            if let progress = info.status.progress {
                ProgressView(value: progress)
            }
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(items: [info.destination])
        }
    }
}

/// The export type picker — upstream `CacheActivity.showExportTypeConfig`.
public struct ExportTypeSheet: View {

    let current: ExportType
    let onSelect: (ExportType) -> Void

    public init(current: ExportType, onSelect: @escaping (ExportType) -> Void) {
        self.current = current
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(ExportType.allCases) { type in
                    Button {
                        onSelect(type)
                    } label: {
                        Label(
                            type.displayName,
                            systemImage: type == current ? "checkmark" : ""
                        )
                    }
                }
            }
            .navigationTitle("导出类型")
        }
    }
}

/// The character set picker — upstream `CacheActivity.showCharsetConfig`.
///
/// The upstream offers a free text field; the port lists the character sets
/// it can encode and still accepts a custom name.
public struct ExportCharsetSheet: View {

    let current: String
    let onSelect: (String) -> Void

    @State private var draft: String

    public init(current: String, onSelect: @escaping (String) -> Void) {
        self.current = current
        self.onSelect = onSelect
        _draft = State(initialValue: current)
    }

    public var body: some View {
        NavigationStack {
            List {
                Section("可选字符集") {
                    ForEach(ExportCharset.allCases) { charset in
                        Button {
                            draft = charset.rawValue
                        } label: {
                            Label(
                                charset.rawValue,
                                systemImage: charset.rawValue == current ? "checkmark" : ""
                            )
                        }
                    }
                }
                Section("自定义") {
                    TextField("字符集", text: $draft)
                }
            }
            .navigationTitle("导出字符集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { onSelect(current) }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("确定") { onSelect(draft.isEmpty ? "UTF-8" : draft) }
                }
            }
        }
    }
}

/// The custom export dialog — upstream `CacheActivity.configExportSection`.
///
/// The user enters the chapter range (`1-5,8,10-18`) and how many chapters
/// every exported EPUB file holds; the range is split into that many files.
public struct CustomExportSheet: View {

    @Binding var scope: String
    @Binding var splitSize: Int
    let onExportAll: () -> Void
    let onExportScope: () -> Void

    public init(
        scope: Binding<String>,
        splitSize: Binding<Int>,
        onExportAll: @escaping () -> Void,
        onExportScope: @escaping () -> Void
    ) {
        _scope = scope
        _splitSize = splitSize
        self.onExportAll = onExportAll
        self.onExportScope = onExportScope
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("导出范围") {
                    TextField("1-5,8,10-18", text: $scope)
                    Stepper(value: $splitSize, in: 1...100) {
                        Text("每个文件章节数：\(splitSize)")
                    }
                }
                Section {
                    Button("导出全部") { onExportAll() }
                    Button("导出选中章节") { onExportScope() }
                }
            }
            .navigationTitle("自定义导出")
        }
    }
}

/// One row of the cache screen — upstream `CacheAdapter`.
public struct DownloadBookRow: View {

    let book: Book
    let progress: CacheBookProgress?
    let onCache: () -> Void
    let onCacheAll: () -> Void
    let onStop: () -> Void
    let onExport: () -> Void

    public init(
        book: Book,
        progress: CacheBookProgress?,
        onCache: @escaping () -> Void,
        onCacheAll: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onExport: @escaping () -> Void
    ) {
        self.book = book
        self.progress = progress
        self.onCache = onCache
        self.onCacheAll = onCacheAll
        self.onStop = onStop
        self.onExport = onExport
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.name)
                .font(.system(size: 14, weight: .medium))
            Text(book.author)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            if let progress, !progress.isIdle {
                Text(progress.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            HStack {
                Button("缓存") { onCache() }
                Button("全部缓存") { onCacheAll() }
                Button("停止") { onStop() }
                Button("导出") { onExport() }
            }
            .font(.system(size: 12))
        }
        .padding(.vertical, 2)
    }
}
