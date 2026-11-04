//
//  RssSourceManagementView.swift
//  LegadoUI
//
//  The management of the RSS sources.
//
//  Upstream:
//  - `ui/rss/source/manage/RssSourceActivity.kt` — the list of the sources,
//    the search, the filters, the import (local / online / QR code), the
//    group manager, the drag and the actions of the selected sources,
//  - `ui/rss/source/manage/RssSourceViewModel.kt` — the actions of the
//    selected sources (enable, disable, to top, to bottom, the groups),
//  - `data/dao/RssSourceDao.kt` — the search of the sources,
//  - `ui/rss/source/edit/RssSourceEditActivity.kt` — the editor of a source
//    (the tabs "Basic", "List" and "WEB_VIEW").
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

// MARK: - The list of the RSS sources

/// The RSS sources — upstream `ui/rss/source/manage/RssSourceActivity`.
///
/// The upstream lists the sources, lets the user search and filter them,
/// import them (from a file, from an url or from a QR code), reorder them
/// with a drag, manage their groups and edit them in bulk (enable, disable,
/// move to a group, to top, to bottom, export and delete).
public struct RssSourceManageView: View {

    @ObservedObject var model: LegadoAppModel

    /// The sources of the list.
    @State private var sources: [RssSource] = []
    /// The search of the list — upstream `initSearchView`.
    @State private var searchText: String = ""
    /// The selected sources (their URLs) — upstream the selection of the
    /// recycler view.
    @State private var selection: Set<String> = []
    /// Whether the selection mode is on.
    @State private var isManaging = false
    /// The edited source.
    @State private var editing: RssSourceItem?
    /// The source that is deleted — upstream `RssSourceActivity.del`.
    @State private var deletedURL: String?
    /// The group manager — upstream `menu_group_manage`.
    @State private var isGroupPresented = false
    /// The import from an url — upstream `menu_import_onLine`.
    @State private var isImportPresented = false
    @State private var importText: String = ""
    /// The import from a file — upstream `menu_import_local`.
    @State private var isFileImporterPresented = false
    /// The import from a QR code — upstream `menu_import_qr`.
    @State private var isQRScannerPresented = false
    @State private var qrResult: String?
    /// The message of the last action.
    @State private var message: String?
    /// The group the selected sources are added to or removed from — upstream
    /// `RssSourceViewModel.selectionAddToGroups`.
    @State private var newGroup: String = ""
    /// The sources of the import preview — upstream
    /// `ImportRssSourceDialog`.
    @State private var importSources: [RssSource] = []
    /// Whether the import preview is shown.
    @State private var isImportPreviewPresented = false
    /// The file that was written for the export — upstream
    /// `RssSourceViewModel.saveToFile`.
    @State private var exportedFileURL: URL?
    /// The JSON that is shared as text — upstream
    /// `RssSourceActivity.menu_share_source`.
    @State private var shareText: String?
    /// Whether the exported file is shared.
    @State private var isSharePresented = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            ForEach(filteredSources, id: \.sourceUrl) { source in
                row(source)
            }
            // The drag of the sources — upstream `initRecyclerView` attaches
            // an `ItemTouchHelper` and `upOrder` writes the new order.
            .onMove { offsets, destination in
                move(from: offsets, to: destination)
            }
            if let message {
                Section {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            if isManaging {
                // The actions of the selected sources — upstream the selection
                // menu of `RssSourceActivity`.
                Section("已选 \(selection.count) 个") {
                    HStack {
                        Button("全选") {
                            selection = Set(filteredSources.map(\.sourceUrl))
                        }
                        Button("取消") {
                            selection = []
                        }
                    }
                    HStack {
                        // Upstream `RssSourceViewModel.enableSelection`.
                        Button("启用") {
                            setEnabled(true)
                        }
                        // Upstream `RssSourceViewModel.disableSelection`.
                        Button("禁用") {
                            setEnabled(false)
                        }
                        // Upstream `RssSourceViewModel.topSource`.
                        Button("置顶") {
                            toTop()
                        }
                        // Upstream `RssSourceViewModel.bottomSource`.
                        Button("置底") {
                            toBottom()
                        }
                    }
                    HStack {
                        // Upstream `RssSourceViewModel.selectionAddToGroups`.
                        Button("添加分组") {
                            addGroupToSelection()
                        }
                        // Upstream `RssSourceViewModel.selectionRemoveFromGroups`.
                        Button("移除分组") {
                            removeGroupFromSelection()
                        }
                    }
                    HStack {
                        // Upstream `RssSourceViewModel.saveToFile`.
                        Button("导出") {
                            exportSelection()
                        }
                        // Upstream `RssSourceActivity.menu_share_source` —
                        // the JSON of the selected sources is shared as text.
                        Button("分享") {
                            shareSelection()
                        }
                        // Upstream `RssSourceAdapter.checkSelectedInterval`.
                        Button("检查所选区间") {
                            checkSelectedInterval()
                        }
                        // Upstream `RssSourceActivity.del`.
                        Button("删除", role: .destructive) {
                            deleteSelection()
                        }
                    }
                }
            }
        }
        .navigationTitle("订阅源")
        .searchable(text: $searchText, prompt: "搜索订阅源")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Upstream `menu_add`.
                Button("添加") {
                    editing = RssSourceItem(source: RssSource(sourceUrl: "", sourceName: ""))
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // Upstream `RssSourceViewModel.importDefault`.
                Button("恢复默认") {
                    try? DefaultData.importDefaultRssSources(store: model.environment.store)
                    reload()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                // Upstream `menu_import_local` / `menu_import_onLine` /
                // `menu_import_qr`.
                Menu {
                    Button("本地导入") {
                        isFileImporterPresented = true
                    }
                    Button("网络导入") {
                        importText = ""
                        isImportPresented = true
                    }
                    Button("二维码导入") {
                        isQRScannerPresented = true
                    }
                } label: {
                    Text("导入")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                // Upstream `menu_enabled_group`, `menu_disabled_group`,
                // `menu_group_login`, `menu_group_null` and the groups.
                Menu {
                    ForEach(RssSourceManageView.filters, id: \.key) { filter in
                        Button(filter.title) {
                            searchText = filter.key
                        }
                    }
                    if !groups.isEmpty {
                        Divider()
                        ForEach(groups, id: \.name) { group in
                            // Upstream the group items of the menu set the
                            // search to "group:<name>".
                            Button(group.name) {
                                searchText = RssSourceManageView.groupPrefix + group.name
                            }
                        }
                    }
                    Divider()
                    Button("清除筛选") {
                        searchText = ""
                    }
                } label: {
                    Text("筛选")
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                // Upstream `menu_group_manage`.
                Button("分组") {
                    isGroupPresented = true
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                // The selection mode.
                Button(isManaging ? "完成" : "多选") {
                    isManaging.toggle()
                    if !isManaging { selection = [] }
                }
            }
        }
        .sheet(item: $editing) { item in
            RssSourceEditView(
                model: model,
                source: item.source,
                onSave: { saved in
                    model.saveRssSource(saved)
                    reload()
                },
                onClose: {
                    editing = nil
                }
            )
        }
        .sheet(isPresented: $isGroupPresented) {
            NavigationStack {
                RssSourceGroupManageView(model: model)
            }
        }
        .sheet(isPresented: $isImportPresented) {
            NavigationStack {
                RssSourceImportView(model: model) { text in
                    await importText(text)
                }
            }
        }
        .sheet(isPresented: $isImportPreviewPresented) {
            NavigationStack {
                RssSourceImportPreviewView(model: model, sources: importSources) { prepared in
                    do {
                        let count = try model.environment.insertRssSources(prepared)
                        message = "导入 \(count) 个订阅源"
                    } catch {
                        message = "导入失败: \(error.localizedDescription)"
                    }
                    isImportPreviewPresented = false
                    reload()
                }
            }
        }
        .sheet(isPresented: $isQRScannerPresented) {
            NavigationStack {
                QRScannerView(result: $qrResult)
            }
        }
        .sheet(isPresented: $isSharePresented) {
            if let exportedFileURL {
                ShareSheet(items: [exportedFileURL])
            } else if let shareText {
                ShareSheet(items: [shareText])
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: RssSourceManageView.contentTypes,
            onCompletion: { result in
                importFile(result)
            }
        )
        .alert(
            "删除订阅源",
            isPresented: Binding(get: { deletedURL != nil }, set: { if !$0 { deletedURL = nil } })
        ) {
            Button("取消", role: .cancel) {
                deletedURL = nil
            }
            Button("删除", role: .destructive) {
                if let url = deletedURL {
                    delete(url)
                }
                deletedURL = nil
            }
        } message: {
            Text("确定删除该订阅源吗？")
        }
        .onChange(of: qrResult) { _, value in
            guard let value, !value.isEmpty else { return }
            qrResult = nil
            Task {
                await importText(value)
            }
        }
        .onAppear {
            reload()
        }
    }

    // MARK: - Parts

    /// A row of the list.
    private func row(_ source: RssSource) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if isManaging {
                Button {
                    if selection.contains(source.sourceUrl) {
                        selection.remove(source.sourceUrl)
                    } else {
                        selection.insert(source.sourceUrl)
                    }
                } label: {
                    Text(selection.contains(source.sourceUrl) ? "☑" : "☐")
                        .font(.system(size: 16))
                }
                .buttonStyle(PlainButtonStyle())
            }
            Button {
                editing = RssSourceItem(source: source)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.sourceName.isEmpty ? source.sourceUrl : source.sourceName)
                        .font(.system(size: 16))
                    Text(source.sourceUrl)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    if let group = source.sourceGroup, !group.isEmpty {
                        Text(group)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(PlainButtonStyle())
            Toggle(isOn: Binding(
                get: { source.enabled },
                set: { value in
                    var changed = source
                    changed.enabled = value
                    model.saveRssSource(changed)
                    reload()
                }
            )) {
                Text("启用")
                    .font(.system(size: 12))
            }
            Button("删除", role: .destructive) {
                deletedURL = source.sourceUrl
            }
            .font(.system(size: 12))
        }
        // Upstream `RssSourceAdapter.showMenu` — the popup of a row holds
        // 置顶, 置底 and 删除.
        .contextMenu {
            Button("置顶") {
                moveToTop(source)
            }
            Button("置底") {
                moveToBottom(source)
            }
            Button("删除", role: .destructive) {
                deletedURL = source.sourceUrl
            }
        }
    }

    /// The sources of the list — upstream `RssSourceActivity.upSourceFlow`.
    ///
    /// The search box holds the special keys of the upstream ("启用", "禁用",
    /// "需要登录", "无分组" and "group:<name>"), every other key searches the
    /// name, the address, the group and the comment of the source.
    private var filteredSources: [RssSource] {
        let key = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return sources }
        if key == RssSourceManageView.enabled { return sources.filter { $0.enabled } }
        if key == RssSourceManageView.disabled { return sources.filter { !$0.enabled } }
        if key == RssSourceManageView.needLogin {
            return sources.filter { !($0.loginUrl ?? "").isEmpty }
        }
        if key == RssSourceManageView.noGroup {
            return sources.filter { RssLibrary.splitGroups($0.sourceGroup).isEmpty }
        }
        if key.hasPrefix(RssSourceManageView.groupPrefix) {
            let group = String(key.dropFirst(RssSourceManageView.groupPrefix.count))
            return sources.filter { RssLibrary.splitGroups($0.sourceGroup).contains(group) }
        }
        return sources.filter {
            $0.sourceName.contains(key)
                || $0.sourceUrl.contains(key)
                || ($0.sourceGroup ?? "").contains(key)
                || ($0.sourceComment ?? "").contains(key)
        }
    }

    /// The groups of the sources — upstream `initGroupFlow`.
    private var groups: [RssLibrary.Group] {
        RssLibrary.sourceGroups(sources)
    }

    // MARK: - Actions

    private func reload() {
        sources = (try? model.environment.store.allRssSources()) ?? []
    }

    /// The special keys of the search box — upstream `upSourceFlow`.
    static let enabled = "启用"
    static let disabled = "禁用"
    static let needLogin = "需要登录"
    static let noGroup = "无分组"
    static let groupPrefix = "group:"

    /// The filters of the menu — upstream `RssSourceActivity.initMenu`.
    static let filters: [(title: String, key: String)] = [
        (enabled, enabled),
        (disabled, disabled),
        (needLogin, needLogin),
        (noGroup, noGroup)
    ]

    /// The accepted file types — upstream `AppPattern` accepts `txt` and
    /// `json` for the sources.
    public static var contentTypes: [UTType] {
        var types: [UTType] = [.data]
        for ext in ["txt", "json"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }

    /// Deletes a source — upstream `RssSourceActivity.del`.
    private func delete(_ url: String) {
        guard let source = sources.first(where: { $0.sourceUrl == url }) else { return }
        model.deleteRssSource(source)
        selection.remove(url)
        reload()
    }

    /// Deletes the selected sources — upstream `RssSourceActivity.del`.
    private func deleteSelection() {
        for url in selection {
            if let source = sources.first(where: { $0.sourceUrl == url }) {
                model.deleteRssSource(source)
            }
        }
        selection = []
        reload()
    }

    /// Enables or disables the selected sources — upstream
    /// `RssSourceViewModel.enableSelection` / `disableSelection`.
    private func setEnabled(_ enabled: Bool) {
        for url in selection {
            guard var source = sources.first(where: { $0.sourceUrl == url }) else { continue }
            source.enabled = enabled
            save(source)
        }
        reload()
    }

    /// Moves the selected sources to the top — upstream
    /// `RssSourceViewModel.topSource` (`customOrder = minOrder - 1 - index`).
    private func toTop() {
        let selected = selection
        let minOrder = sources.map(\.customOrder).min() ?? 0
        var order = minOrder - 1
        for url in selected.sorted() {
            guard var source = sources.first(where: { $0.sourceUrl == url }) else { continue }
            source.customOrder = order
            order -= 1
            save(source)
        }
        reload()
    }

    /// Moves the selected sources to the bottom — upstream
    /// `RssSourceViewModel.bottomSource` (`customOrder = maxOrder + 1 + index`).
    private func toBottom() {
        let selected = selection
        let maxOrder = sources.map(\.customOrder).max() ?? 0
        var order = maxOrder + 1
        for url in selected.sorted() {
            guard var source = sources.first(where: { $0.sourceUrl == url }) else { continue }
            source.customOrder = order
            order += 1
            save(source)
        }
        reload()
    }

    /// Moves a source to the top — upstream `RssSourceViewModel.topSource`
    /// with a single source (`customOrder = minOrder - 1`).
    private func moveToTop(_ source: RssSource) {
        var changed = source
        changed.customOrder = (sources.map(\.customOrder).min() ?? 0) - 1
        save(changed)
        reload()
    }

    /// Moves a source to the bottom — upstream
    /// `RssSourceViewModel.bottomSource` with a single source
    /// (`customOrder = maxOrder + 1`).
    private func moveToBottom(_ source: RssSource) {
        var changed = source
        changed.customOrder = (sources.map(\.customOrder).max() ?? 0) + 1
        save(changed)
        reload()
    }

    /// Adds a group to the selected sources — upstream
    /// `RssSourceViewModel.selectionAddToGroups`.
    private func addGroupToSelection() {
        guard !newGroup.isEmpty else { return }
        for url in selection {
            guard var source = sources.first(where: { $0.sourceUrl == url }) else { continue }
            RssLibrary.addGroup(newGroup, to: &source)
            save(source)
        }
        newGroup = ""
        reload()
    }

    /// Removes a group from the selected sources — upstream
    /// `RssSourceViewModel.selectionRemoveFromGroups`.
    private func removeGroupFromSelection() {
        guard !newGroup.isEmpty else { return }
        for url in selection {
            guard var source = sources.first(where: { $0.sourceUrl == url }) else { continue }
            RssLibrary.removeGroup(newGroup, from: &source)
            save(source)
        }
        newGroup = ""
        reload()
    }

    /// Exports the selected sources — upstream `RssSourceViewModel.saveToFile`
    /// (the file "exportRssSource.json").
    private func exportSelection() {
        let exported = sources.filter { selection.contains($0.sourceUrl) }
        let json = JSONValue.array(exported.map { RssSourceJSONBridge.encode($0) }).jsonString
        guard let data = json.data(using: .utf8) else { return }
        do {
            exportedFileURL = try DocumentExporter.write(data, fileName: "exportRssSource.json")
            isSharePresented = true
            message = "已导出 \(exported.count) 个订阅源"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    /// Shares the selected sources — upstream
    /// `RssSourceActivity.menu_share_source` (`viewModel.saveToFile { share(it) }`):
    /// the JSON of the selected sources is shared as text.
    private func shareSelection() {
        let exported = sources.filter { selection.contains($0.sourceUrl) }
        let json = JSONValue.array(exported.map { RssSourceJSONBridge.encode($0) }).jsonString
        exportedFileURL = nil
        shareText = json
        isSharePresented = true
        message = "已分享 \(exported.count) 个订阅源"
    }

    /// Selects the interval between the first and the last selected source —
    /// upstream `RssSourceAdapter.checkSelectedInterval`.
    private func checkSelectedInterval() {
        let urls = sources.map(\.sourceUrl)
        selection = SourceSelection.interval(selected: selection, in: urls)
    }

    /// Moves a source with a drag — upstream `RssSourceActivity.initRecyclerView`
    /// and `RssSourceViewModel.upOrder` (`customOrder = index + 1`).
    private func move(from offsets: IndexSet, to destination: Int) {
        guard searchText.isEmpty else { return }
        var ordered = sources
        let indexes = offsets.sorted()
        let moving = indexes.map { ordered[$0] }
        for index in indexes.reversed() {
            ordered.remove(at: index)
        }
        let removed = indexes.filter { $0 < destination }.count
        let target = max(0, min(ordered.count, destination - removed))
        ordered.insert(contentsOf: moving, at: target)
        for (index, var source) in ordered.enumerated() {
            source.customOrder = Int64(index + 1)
            save(source)
        }
        reload()
    }

    /// Saves a source in the store.
    private func save(_ source: RssSource) {
        try? model.environment.store.insert(source)
    }

    /// Imports a file — upstream `menu_import_local`.
    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                message = "读取文件失败"
                return
            }
            await importText(text)
        }
    }

    /// Imports a text — upstream `ImportRssSourceViewModel.importSourceAwait`.
    ///
    /// The text is either an url (the document is downloaded) or a JSON
    /// document with the sources. The upstream shows the preview of the
    /// import before the sources are inserted.
    private func importText(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let sources: [RssSource]
            if RssSourceImport.isAbsoluteURL(trimmed) {
                // Upstream the url is remembered in the `ACache` before the
                // import (`RssSourceActivity.showImportDialog`).
                _ = ImportUrlHistory.add(trimmed, .rssSource, store: model.environment.store)
                sources = try await model.environment.rssSourcesOfImport(url: trimmed)
            } else {
                sources = try await model.environment.rssSourcesOfImport(json: trimmed)
            }
            guard !sources.isEmpty else {
                message = "没有可导入的订阅源"
                return
            }
            importSources = sources
            isImportPreviewPresented = true
        } catch {
            message = "导入失败: \(error.localizedDescription)"
        }
        reload()
    }
}

// MARK: - The import of the RSS sources

/// The import of the RSS sources from an url — upstream
/// `RssSourceActivity.showImportDialog`.
struct RssSourceImportView: View {

    @ObservedObject var model: LegadoAppModel

    let onImport: (String) async -> Void

    @State private var url: String = ""
    @State private var isImporting = false
    /// The urls the sources were imported from — upstream the `ACache`
    /// (`RssSourceActivity.showImportDialog`).
    @State private var history: [String] = []

    init(model: LegadoAppModel, onImport: @escaping (String) async -> Void) {
        self.model = model
        self.onImport = onImport
    }

    var body: some View {
        Form {
            Section("订阅源地址") {
                TextField("https://", text: $url)
                Button {
                    isImporting = true
                    let value = url
                    Task {
                        await onImport(value)
                        isImporting = false
                    }
                } label: {
                    if isImporting {
                        ProgressView("导入中")
                    } else {
                        Text("导入")
                    }
                }
            }
            if !history.isEmpty {
                // Upstream the edit field has a filter with the urls of the
                // cache and a delete callback.
                Section("最近导入") {
                    ForEach(history, id: \.self) { entry in
                        HStack {
                            Button(entry) {
                                url = entry
                            }
                            .buttonStyle(PlainButtonStyle())
                            Spacer()
                            Button {
                                history = ImportUrlHistory.remove(
                                    entry,
                                    .rssSource,
                                    store: model.environment.store
                                )
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
        .navigationTitle("网络导入")
        .onAppear {
            history = ImportUrlHistory.urls(.rssSource, store: model.environment.store)
        }
    }
}

// MARK: - The groups of the RSS sources

/// The groups of the RSS sources — upstream `GroupManageDialog`.
///
/// The upstream adds a group (every source without a group gets it),
/// renames it and deletes it.
public struct RssSourceGroupManageView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var groups: [String] = []
    @State private var newGroup: String = ""
    @State private var renamedGroup: String = ""
    @State private var newName: String = ""

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section("分组") {
                ForEach(groups, id: \.self) { group in
                    HStack {
                        Text(group)
                        Spacer()
                        Button("重命名") {
                            renamedGroup = group
                            newName = group
                        }
                        .font(.system(size: 12))
                        Button("删除", role: .destructive) {
                            delete(group)
                        }
                        .font(.system(size: 12))
                    }
                }
            }
            Section("新建分组") {
                TextField("分组名称", text: $newGroup)
                Button("添加") {
                    add()
                }
            }
        }
        .navigationTitle("分组管理")
        .alert(
            "重命名分组",
            isPresented: Binding(get: { !renamedGroup.isEmpty }, set: { if !$0 { renamedGroup = "" } })
        ) {
            TextField("分组名称", text: $newName)
            Button("取消", role: .cancel) {
                renamedGroup = ""
            }
            Button("确定") {
                rename(renamedGroup, to: newName)
                renamedGroup = ""
            }
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        groups = RssLibrary.sourceGroups((try? model.environment.store.allRssSources()) ?? [])
            .map(\.name)
    }

    /// Adds a group — upstream `RssSourceViewModel.addGroup`: every source
    /// without a group gets the new one.
    private func add() {
        let name = newGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        for var source in (try? model.environment.store.allRssSources()) ?? [] {
            guard RssLibrary.splitGroups(source.sourceGroup).isEmpty else { continue }
            RssLibrary.addGroup(name, to: &source)
            try? model.environment.store.insert(source)
        }
        newGroup = ""
        reload()
    }

    /// Renames a group — upstream `RssSourceViewModel.upGroup`.
    private func rename(_ group: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        for var source in (try? model.environment.store.allRssSources()) ?? [] {
            var groups = RssLibrary.splitGroups(source.sourceGroup)
            guard groups.contains(group) else { continue }
            groups = groups.map { $0 == group ? trimmed : $0 }
            source.sourceGroup = groups.joined(separator: ",")
            try? model.environment.store.insert(source)
        }
        reload()
    }

    /// Deletes a group — upstream `RssSourceViewModel.delGroup`.
    private func delete(_ group: String) {
        for var source in (try? model.environment.store.allRssSources()) ?? [] {
            guard RssLibrary.splitGroups(source.sourceGroup).contains(group) else { continue }
            RssLibrary.removeGroup(group, from: &source)
            try? model.environment.store.insert(source)
        }
        reload()
    }
}

// MARK: - The editor of an RSS source

/// The editor of an RSS source — upstream
/// `ui/rss/source/edit/RssSourceEditActivity`.
///
/// The upstream has three tabs: "Basic" (the source itself), "List" (the
/// rules of the article list) and "WEB_VIEW" (the rules of the web view of
/// the article).
public struct RssSourceEditView: View {

    /// The model — the login, the debug and the share need it.
    @ObservedObject var model: LegadoAppModel

    /// The edited source.
    @State private var draft: RssSource
    /// The tab of the editor.
    @State private var tab: Int = 0
    /// The action of the save.
    let onSave: (RssSource) -> Void
    /// The action of the close — the upstream asks whether the changes are to
    /// be discarded (`exit_no_save`).
    let onClose: (() -> Void)?
    /// The message of the last action.
    @State private var message: String = ""
    /// Whether the rules are completed automatically — upstream
    /// `menu_auto_complete`.
    @State private var autoComplete = false
    /// The debugger — upstream `menu_debug`.
    @State private var isDebugPresented = false
    /// The variables of the source — upstream `menu_set_source_variable`.
    @State private var isVariablesPresented = false
    @State private var variableText: String = ""
    /// The share sheet — upstream `menu_share_source`.
    @State private var isSharePresented = false
    /// The QR code — upstream `menu_qr_code`.
    @State private var isQRPresented = false
    /// Whether the source was changed.
    @State private var isChanged = false
    /// Whether the confirmation of the exit is shown.
    @State private var isExitConfirmationPresented = false

    public init(
        model: LegadoAppModel,
        source: RssSource,
        onSave: @escaping (RssSource) -> Void,
        onClose: (() -> Void)? = nil
    ) {
        self.model = model
        _draft = State(initialValue: source)
        self.onSave = onSave
        self.onClose = onClose
    }

    public var body: some View {
        Form {
            Section {
                Picker("标签", selection: $tab) {
                    Text("订阅源").tag(0)
                    Text("规则").tag(1)
                    Text("WEB_VIEW").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
            }
            switch tab {
            case 1:
                listTab
            case 2:
                webViewTab
            default:
                baseTab
            }
            if !message.isEmpty {
                Section {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("订阅源")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("保存") {
                    save()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button("关闭") {
                    close()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                // The upstream `res/menu/source_edit.xml`.
                Menu("更多") {
                    Button("调试") {
                        onSave(draft)
                        isDebugPresented = true
                    }
                    if let loginUrl = draft.loginUrl, !loginUrl.isEmpty {
                        Button("登录") {
                            model.presentLogin(for: draft)
                        }
                    }
                    Button("源变量") {
                        variableText = BookSourceVariables.sourceVariables(draft.key) ?? ""
                        isVariablesPresented = true
                    }
                    Button("清除Cookie") {
                        model.environment.cookieStore.removeCookie(url: draft.sourceUrl)
                        message = "已清除该订阅源的Cookie"
                    }
                    Button(autoComplete ? "自动补全：开" : "自动补全：关") {
                        autoComplete.toggle()
                        message = autoComplete ? "规则将自动补全" : "规则不再自动补全"
                    }
                    Button("复制源") {
                        UIPasteboardShim.copy(sourceJSON)
                        message = "已复制订阅源"
                    }
                    Button("粘贴源") {
                        pasteSource()
                    }
                    Button("二维码分享") {
                        isQRPresented = true
                    }
                    Button("分享") {
                        isSharePresented = true
                    }
                    NavigationLink("帮助") {
                        RuleHelpView()
                    }
                }
            }
        }
        .sheet(isPresented: $isDebugPresented) {
            NavigationStack {
                RssSourceDebugView(model: model, sourceUrl: draft.sourceUrl)
            }
        }
        .sheet(isPresented: $isVariablesPresented) {
            NavigationStack {
                VariableEditorView(
                    title: "源变量",
                    comment: "源变量可在js中通过source.getVariable()获取",
                    value: variableText
                ) { value in
                    saveVariables(value)
                }
            }
        }
        .sheet(isPresented: $isQRPresented) {
            NavigationStack {
                QRCodeView(text: sourceJSON)
                    .navigationTitle("订阅源二维码")
            }
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(items: [sourceJSON])
        }
        .alert("退出", isPresented: $isExitConfirmationPresented) {
            Button("取消", role: .cancel) {}
            Button("放弃修改", role: .destructive) {
                onClose?()
            }
        } message: {
            Text("是否放弃本次修改？")
        }
    }

    // MARK: - The tabs

    /// The tab of the source — upstream `sourceEntities`.
    private var baseTab: some View {
        Section("订阅源") {
            Toggle(isOn: $draft.enabled) {
                Text("启用")
            }
            Toggle(isOn: $draft.singleUrl) {
                Text("单地址")
            }
            Toggle(isOn: $draft.enabledCookieJar) {
                Text("启用Cookie")
            }
            TextField("名称(sourceName)", text: $draft.sourceName)
            TextField("地址(sourceUrl)", text: $draft.sourceUrl)
            TextField("图标(sourceIcon)", text: $draft.sourceIcon)
            TextField("分组(sourceGroup)", text: field(\.sourceGroup))
            TextField("注释(sourceComment)", text: field(\.sourceComment))
            TextField("分类地址(sortUrl)", text: field(\.sortUrl))
            TextField("登录地址(loginUrl)", text: field(\.loginUrl))
            TextField("登录页面(loginUi)", text: field(\.loginUi))
            TextField("封面解码(coverDecodeJs)", text: field(\.coverDecodeJs))
            TextField("HTTP Header(header)", text: field(\.header))
            TextField("变量说明(variableComment)", text: field(\.variableComment))
            TextField("并发率(concurrentRate)", text: field(\.concurrentRate))
            TextField("jsLib", text: field(\.jsLib))
        }
    }

    /// The tab of the rules of the list — upstream `listEntities`.
    private var listTab: some View {
        Section("列表规则") {
            TextField("文章列表(ruleArticles)", text: field(\.ruleArticles))
            TextField("下一页(ruleNextPage)", text: ruleField(\.ruleNextPage, .link))
            TextField("标题(ruleTitle)", text: ruleField(\.ruleTitle, .text))
            TextField("发表时间(rulePubDate)", text: ruleField(\.rulePubDate, .text))
            TextField("摘要(ruleDescription)", text: ruleField(\.ruleDescription, .text))
            TextField("图片(ruleImage)", text: ruleField(\.ruleImage, .image))
            TextField("链接(ruleLink)", text: ruleField(\.ruleLink, .text))
        }
    }

    /// The tab of the web view — upstream `webViewEntities`.
    private var webViewTab: some View {
        Section("WEB_VIEW") {
            Toggle(isOn: $draft.enableJs) {
                Text("启用JS(enableJs)")
            }
            Toggle(isOn: $draft.loadWithBaseUrl) {
                Text("加载BaseUrl(loadWithBaseUrl)")
            }
            TextField("正文(ruleContent)", text: ruleField(\.ruleContent, .text))
            TextField("样式(style)", text: field(\.style))
            TextField("注入JS(injectJs)", text: field(\.injectJs))
            TextField("白名单(contentWhitelist)", text: field(\.contentWhitelist))
            TextField("黑名单(contentBlacklist)", text: field(\.contentBlacklist))
            TextField("链接拦截(shouldOverrideUrlLoading)", text: field(\.shouldOverrideUrlLoading))
        }
    }

    // MARK: - Helpers

    /// A binding of an optional field — the empty text is `nil`.
    private func field(_ keyPath: WritableKeyPath<RssSource, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { value in
                draft[keyPath: keyPath] = value.isEmpty ? nil : value
                isChanged = true
            }
        )
    }

    /// A binding of a rule — the rule is completed when the auto-completion
    /// is on — upstream `RssSourceEditActivity.getRssSource`.
    private func ruleField(
        _ keyPath: WritableKeyPath<RssSource, String?>,
        _ type: RuleCompleteType
    ) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { value in
                var updated = value
                if autoComplete {
                    updated = RuleComplete.autoComplete(
                        rules: value,
                        preRule: draft.ruleArticles,
                        type: type
                    ) ?? value
                }
                draft[keyPath: keyPath] = updated.isEmpty ? nil : updated
                isChanged = true
            }
        )
    }

    /// The source as a JSON document — the upstream `GSON.toJson(source)`.
    private var sourceJSON: String {
        RssSourceJSONBridge.encode(draft).jsonString
    }

    /// Saves the source.
    private func save() {
        onSave(draft)
        isChanged = false
        message = "已保存"
    }

    /// Closes the editor — the upstream asks whether the changes are to be
    /// discarded.
    private func close() {
        if isChanged {
            isExitConfirmationPresented = true
        } else {
            onClose?()
        }
    }

    /// Pastes a source from the clipboard — upstream `viewModel.pasteSource`.
    private func pasteSource() {
        guard let text = UIPasteboardShim.paste() else {
            message = "剪贴板为空"
            return
        }
        guard let value = try? JSONValue.parse(text),
              let pasted = RssSourceJSONBridge.decode(value) else {
            message = "剪贴板的内容不是一个订阅源"
            return
        }
        draft = pasted
        isChanged = true
        message = "已粘贴订阅源：\(pasted.sourceName)"
    }

    /// Saves the variables of the source — upstream `setSourceVariable`.
    private func saveVariables(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            message = "变量不能为空"
            return
        }
        guard let value = try? JSONValue.parse(trimmed),
              let object = value.objectValue else {
            message = "变量不是一个合法的JSON对象"
            return
        }
        // The upstream stores the variables in the cache manager under
        // `v_<key>_<name>` — the port keeps them in one dictionary.
        var variables: [String: String] = [:]
        for (name, item) in object {
            guard let text = item.stringValue else { continue }
            variables[name] = text
        }
        BookSourceVariables.setVariables(variables, for: draft.key)
        message = "已保存源变量"
    }
}

// MARK: - The item of the list

/// An RSS source that is presented in a sheet.
struct RssSourceItem: Identifiable {
    let source: RssSource

    var id: String { source.sourceUrl }
}
