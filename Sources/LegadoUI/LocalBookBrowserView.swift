//
//  LocalBookBrowserView.swift
//  LegadoUI
//
//  The in-app browser of the local books — upstream
//  `ui/book/import/local/ImportBookActivity.kt`.
//
//  The screen shows the folders of the app storage, lets the user walk into
//  them, select several books, import them into the shelf, delete them and
//  scan a whole folder tree.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The browser of the local books.
public struct LocalBookBrowserView: View {

    @ObservedObject var model: LegadoAppModel

    /// The folders the user walked into — upstream `ImportBookViewModel.subDocs`.
    @State private var path: [URL] = []
    /// The entries of the current folder.
    @State private var entries: [LocalBookEntry] = []
    /// The paths of the selected entries.
    @State private var selected: Set<String> = []
    /// The search filter — upstream `ImportBookViewModel.filterKey`.
    @State private var filterKey = ""
    /// The sort of the list.
    @State private var sort: LocalBookBrowser.Sort = .name
    /// Whether the folder tree is being scanned.
    @State private var isScanning = false
    /// Whether the folder picker is open.
    @State private var isFolderPickerPresented = false
    /// Whether the file-name rule editor is open.
    @State private var isTemplatePresented = false
    /// The JavaScript rule of the file names.
    @State private var templateText = ""
    /// The last message.
    @State private var message: String?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    // MARK: - The folder

    /// The current folder — the last one of the path.
    private var currentFolder: URL {
        path.last ?? rootFolder
    }

    /// The folder the browser starts in — upstream
    /// `AppConfig.importBookPath` (the storage of the app when it is unset).
    private var rootFolder: URL {
        let settings = model.environment.settings
        if let stored = settings.importBookPath, !stored.isEmpty {
            let url = URL(fileURLWithPath: stored)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first
            ?? FileManager.default.temporaryDirectory
    }

    /// The path shown above the list — upstream `upDocs`.
    private var pathText: String {
        var text = currentFolder.lastPathComponent + "/"
        for folder in path.dropLast() {
            text += folder.lastPathComponent + "/"
        }
        return text
    }

    // MARK: - The body

    public var body: some View {
        List {
            Section {
                TextField("搜索", text: $filterKey)
                    .font(.system(size: 13))
            }

            Section {
                if entries.isEmpty {
                    Text("没有可导入的文件")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(entries) { entry in
                        row(entry)
                    }
                }
            } header: {
                HStack {
                    Text(pathText)
                    Spacer()
                    if isScanning {
                        ProgressView()
                    }
                }
            }

            if !selected.isEmpty {
                Section {
                    Button("加入书架 (\(selected.count))") {
                        importSelected()
                    }
                    Button("删除所选") {
                        deleteSelected()
                    }
                    Button("全选") {
                        selected = Set(entries.filter { !$0.isDirectory }.map(\.id))
                    }
                    Button("反选") {
                        let files = entries.filter { !$0.isDirectory }
                        for entry in files {
                            if selected.contains(entry.id) {
                                selected.remove(entry.id)
                            } else {
                                selected.insert(entry.id)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("导入本地书")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("选择文件夹") { isFolderPickerPresented = true }
                    Button("扫描文件夹") { scanFolder() }
                    Button("导入文件名规则") { editTemplate() }
                    Divider()
                    ForEach(LocalBookBrowser.Sort.allCases, id: \.rawValue) { mode in
                        Button(mode.displayName) {
                            sort = mode
                            model.environment.settings.localBookImportSort = mode.rawValue
                            reload()
                        }
                    }
                } label: {
                    Text("更多")
                }
            }
        }
        .fileImporter(
            isPresented: $isFolderPickerPresented,
            allowedContentTypes: [.folder],
            onCompletion: { result in
                switch result {
                case let .success(url):
                    path = [url]
                    model.environment.settings.importBookPath = url.path
                    reload()
                case let .failure(error):
                    message = error.localizedDescription
                }
            }
        )
        .alert("导入文件名规则", isPresented: $isTemplatePresented) {
            TextField("js", text: $templateText)
            Button("保存") { saveTemplate() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("使用js处理文件名变量src，将书名作者分别赋值到变量name author")
        }
        .onAppear {
            sort = LocalBookBrowser.Sort(
                rawValue: model.environment.settings.localBookImportSort
            ) ?? .name
            templateText = model.environment.settings.bookImportFileName ?? ""
            reload()
        }
    }

    // MARK: - The rows

    @ViewBuilder
    private func row(_ entry: LocalBookEntry) -> some View {
        if entry.isDirectory {
            Button {
                path.append(entry.url)
                reload()
            } label: {
                HStack {
                    Text(entry.name)
                    Spacer()
                    Image(systemName: "folder")
                }
            }
        } else {
            HStack {
                Button {
                    toggle(entry)
                } label: {
                    Text(selected.contains(entry.id) ? "☑" : "☐")
                        .font(.system(size: 16))
                }
                VStack(alignment: .leading) {
                    Text(entry.name)
                    Text(sizeText(entry.size))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
    }

    /// The size of a file — upstream `Formatter.formatFileSize`.
    private func sizeText(_ size: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }

    // MARK: - The actions

    /// Selects or deselects an entry.
    private func toggle(_ entry: LocalBookEntry) {
        if selected.contains(entry.id) {
            selected.remove(entry.id)
        } else {
            selected.insert(entry.id)
        }
    }

    /// Reads the current folder — upstream `ImportBookViewModel.loadDoc`.
    private func reload() {
        let listed = LocalBookBrowser.list(directory: currentFolder)
        let filtered = LocalBookBrowser.filter(listed, key: filterKey)
        entries = LocalBookBrowser.sort(filtered, by: sort)
        selected = selected.filter { path in
            filtered.contains { $0.id == path }
        }
    }

    /// Scans the current folder and all its sub-folders — upstream
    /// `ImportBookViewModel.scanDoc`.
    private func scanFolder() {
        isScanning = true
        let folder = currentFolder
        Task {
            let result = LocalBookScanner.scan(directory: folder)
            let books = LocalBookScanner.supportedBooks(of: result)
            let imported = await model.importLocalBooks(books)
            await MainActor.run {
                isScanning = false
                message = imported > 0 ? "已导入 \(imported) 本书" : "没有找到可导入的书"
                reload()
            }
        }
    }

    /// Imports the selected files — upstream
    /// `ImportBookViewModel.addToBookshelf`.
    private func importSelected() {
        let urls = entries.filter { selected.contains($0.id) }.map(\.url)
        guard !urls.isEmpty else { return }
        Task {
            let count = await model.importLocalBooks(urls)
            await MainActor.run {
                message = "已导入 \(count) 本书"
                selected.removeAll()
                reload()
            }
        }
    }

    /// Deletes the selected files — upstream `ImportBookViewModel.deleteDoc`.
    private func deleteSelected() {
        let urls = entries.filter { selected.contains($0.id) }.map(\.url)
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
        selected.removeAll()
        reload()
        message = "已删除 \(urls.count) 个文件"
    }

    /// Edits the JavaScript rule of the file names — upstream
    /// `ImportBookActivity.alertImportFileName`.
    private func editTemplate() {
        templateText = model.environment.settings.bookImportFileName ?? ""
        isTemplatePresented = true
    }

    /// Saves the JavaScript rule of the file names.
    private func saveTemplate() {
        model.environment.settings.bookImportFileName = templateText
    }
}
