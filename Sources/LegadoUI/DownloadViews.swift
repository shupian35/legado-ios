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

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
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
                        Button(exportType == 0 ? "导出类型：TXT" : "导出类型：EPUB") {
                            exportType = exportType == 0 ? 1 : 0
                            model.environment.settings.set(exportType, for: .exportType)
                        }
                        Button("导出字符集：\(exportCharset)") {
                            exportCharset = exportCharset == "UTF-8" ? "GBK" : "UTF-8"
                            model.environment.settings.set(exportCharset, for: .exportCharset)
                        }
                        Button("导出文件名：\(exportFileName.isEmpty ? "默认" : exportFileName)") {
                            exportFileName = exportFileName.isEmpty ? "{bookName}" : ""
                            model.environment.settings.set(exportFileName, for: .episodeExportFileName)
                        }
                        Button("导出文件夹：\(exportFolder.isEmpty ? "默认" : exportFolder)") {
                            exportFolder = exportFolder.isEmpty ? "书籍导出" : ""
                            try? model.environment.store.putCache(
                                "exportBookPath",
                                value: exportFolder,
                                deadline: 0
                            )
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
        Task {
            do {
                let file = try await model.exportBook(
                    book: book,
                    format: exportType == 0 ? .txt : .epub,
                    options: exportOptions(for: book)
                )
                message = "已导出：\(file.fileName)"
            } catch {
                message = "导出失败：\(error.localizedDescription)"
            }
        }
    }

    /// Exports every book of the list — upstream `CacheActivity.exportAll`.
    private func exportAll() {
        let list = books
        Task {
            var exported = 0
            var failed = 0
            for book in list {
                do {
                    _ = try await model.exportBook(
                        book: book,
                        format: exportType == 0 ? .txt : .epub,
                        options: exportOptions(for: book)
                    )
                    exported += 1
                } catch {
                    failed += 1
                }
            }
            message = failed == 0
                ? "已导出 \(exported) 本书"
                : "已导出 \(exported) 本，失败 \(failed) 本"
        }
    }

    /// The options of the export — upstream `AppConfig.exportUseReplace`,
    /// `exportNoChapterName` and `exportPictureFile`.
    private func exportOptions(for book: Book) -> BookExportOptions {
        let settings = model.environment.settings
        return BookExportOptions(
            includeChapterTitle: !settings.exportNoChapterName,
            useReplaceRule: settings.exportUseReplace,
            exportPictureFile: settings.exportPictureFile,
            fileName: exportFileName.isEmpty ? nil : exportFileName
        )
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
