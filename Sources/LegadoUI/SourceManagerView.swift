//
//  SourceManagerView.swift
//  LegadoUI
//
//  The book source manager — upstream
//  `ui/book/source/manage/BookSourceActivity.kt`.
//
//  It lists the sources with their groups, searches them, sorts them, filters
//  them, imports or exports them as JSON and edits them in bulk (the enable /
//  delete / move to a group / export / check).
//
//  See `AppModel.swift` for the state.
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

/// The source manager.
public struct SourceManagerView: View {

    @ObservedObject var model: LegadoAppModel

    // The search and the sorting — upstream `BookSourceActivity`.
    @State private var searchText: String = ""
    @State private var sort: BookSourceSort = .custom
    @State private var isSortAscending = true
    @State private var isGroupedByDomain = false

    // The selection — upstream `BookSourceAdapter.selected`.
    @State private var isManaging = false
    @State private var selection: Set<String> = []

    // The sheets.
    @State private var isImportPresented = false
    @State private var importText: String = ""
    /// The sources the import dialog handed over — the preview is opened once
    /// that dialog has closed. Opening the second sheet while the first one is
    /// still on screen built the preview from the view state of the previous
    /// body, so the list came up empty and 确定 submitted nothing.
    @State private var pendingImportSources: [BookSource] = []
    /// The sources of the import — upstream `ImportBookSourceDialog` shows
    /// the preview before the sources are inserted.
    @State private var importPreview: ImportPreview?
    @State private var isFileImporterPresented = false
    @State private var isQRScannerPresented = false
    @State private var qrResult: String?
    /// The scanned document, imported once the scanner has closed.
    @State private var pendingQRPayload: String?
    @State private var isCheckPresented = false
    @State private var checkTargets: [BookSource] = []
    @State private var isCheckConfigPresented = false
    @State private var loginSource: BookSource?
    @State private var isLoginPresented = false
    @State private var isSharePresented = false
    /// The file that was written for the export — upstream
    /// `menu_export_selection` → `saveToFile`.
    @State private var exportedFileURL: URL?
    @State private var isQRCodePresented = false
    @State private var editingSource: BookSource?
    @State private var isEditorPresented = false
    @State private var isGroupPresented = false
    @State private var isDebugPresented = false
    @State private var isHelpPresented = false
    @State private var isGroupPromptPresented = false
    @State private var groupPromptTitle: String = ""
    @State private var groupPromptAction: GroupPromptAction = .add
    /// The source the search is scoped to — upstream
    /// `BookSourceActivity.searchBook`.
    @State private var searchSource: BookSource?
    @State private var isSearchPresented = false
    @State private var message: String?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            List {
                sourceSections
                if isManaging {
                    Section("已选 \(selection.count) 个") {
                        Menu {
                            Button("启用所选") {
                                model.setSources(selectedSources, enabled: true)
                            }
                            Button("禁用所选") {
                                model.setSources(selectedSources, enabled: false)
                            }
                            Button("允许发现") {
                                model.setSourcesExplore(selectedSources, enabled: true)
                            }
                            Button("禁用发现") {
                                model.setSourcesExplore(selectedSources, enabled: false)
                            }
                            Button("置顶所选") {
                                model.topSources(selectedSources)
                            }
                            Button("置底所选") {
                                model.bottomSources(selectedSources)
                            }
                            Button("加入分组") {
                                promptGroup(.add)
                            }
                            Button("移出分组") {
                                promptGroup(.remove)
                            }
                            Button("导出所选") {
                                exportSelection()
                            }
                            Button("校验所选") {
                                checkTargets = selectedSources
                                isCheckPresented = true
                            }
                            // Upstream `BookSourceAdapter.checkSelectedInterval`
                            // — every source between the first and the last
                            // selected one is selected.
                            Button("检查所选区间") {
                                selection = SourceSelection.interval(
                                    selected: selection,
                                    in: visibleSources
                                )
                            }
                            Button("删除所选", role: .destructive) {
                                model.deleteSources(selectedSources)
                                selection.removeAll()
                            }
                        } label: {
                            Text("批量操作")
                        }
                        HStack {
                            Button("全选") {
                                selection = Set(model.sources.map(\.bookSourceUrl))
                            }
                            Button("取消选择") {
                                selection.removeAll()
                            }
                        }
                        .font(.system(size: 13))
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
            .navigationTitle("书源")
            .searchable(text: $searchText, prompt: "搜索书源")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Upstream `menu_add_book_source`.
                    Button("新建") {
                        editingSource = newSource()
                        isEditorPresented = true
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        // Upstream `menu_import_local`.
                        Button("本地导入") {
                            isFileImporterPresented = true
                        }
                        // Upstream `menu_import_onLine`.
                        Button("网络导入") {
                            importText = ""
                            isImportPresented = true
                        }
                        // Upstream `menu_import_qr`.
                        Button("二维码导入") {
                            isQRScannerPresented = true
                        }
                    } label: {
                        Text("导入")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        // Upstream `menu_check_source`.
                        Button("校验全部") {
                            checkTargets = []
                            isCheckPresented = true
                        }
                        Button("校验所选") {
                            checkTargets = selectedSources
                            isCheckPresented = true
                        }
                        // Upstream `R.string.check_source_config`.
                        Button("校验设置") {
                            isCheckConfigPresented = true
                        }
                    } label: {
                        Text("校验")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        ForEach(BookSourceSort.allCases) { item in
                            Button(item.title) {
                                sort = item
                            }
                        }
                        Divider()
                        // Upstream `menu_sort_desc` toggles the direction.
                        Button(isSortAscending ? "降序排列" : "升序排列") {
                            isSortAscending.toggle()
                        }
                    } label: {
                        Text("排序")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        // Upstream `menu_enabled_group` and its friends.
                        ForEach(BookSourceSearch.filters, id: \.self) { filter in
                            Button(filter) {
                                searchText = filter
                            }
                        }
                        Divider()
                        // Upstream `menu_group_sources_by_domain`.
                        Button(isGroupedByDomain ? "取消按域名分组" : "按域名分组") {
                            isGroupedByDomain.toggle()
                        }
                        Button("清除筛选") {
                            searchText = ""
                        }
                    } label: {
                        Text("筛选")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        // Upstream `upGroupMenu` (L579-584).
                        ForEach(model.sourceGroups(), id: \.self) { group in
                            Button(group) {
                                searchText = BookSourceSearch.groupKey(group)
                            }
                        }
                        Divider()
                        // Upstream `menu_group_manage`.
                        Button("分组管理") {
                            isGroupPresented = true
                        }
                    } label: {
                        Text("分组")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        // Upstream `menu_share_source`.
                        Button("分享") {
                            isSharePresented = true
                        }
                        Button("二维码") {
                            isQRCodePresented = true
                        }
                        Button("调试") {
                            isDebugPresented = true
                        }
                        // Upstream `menu_help`.
                        Button("书源帮助") {
                            isHelpPresented = true
                        }
                    } label: {
                        Text("更多")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(isManaging ? "完成" : "管理") {
                        isManaging.toggle()
                        if !isManaging { selection.removeAll() }
                    }
                }
                #if os(iOS)
                ToolbarItem(placement: .secondaryAction) {
                    // Upstream `BookSourceActivity` — the sources are dragged
                    // to reorder them (`ItemTouchHelper`). `EditButton` is
                    // iOS-only; macOS has no such control.
                    EditButton()
                }
                #endif
            }
            .sheet(isPresented: $isDebugPresented) {
                SourceDebugView(model: model)
            }
            .sheet(isPresented: $isGroupPresented) {
                NavigationStack {
                    SourceGroupView(model: model)
                }
            }
            .sheet(isPresented: $isImportPresented, onDismiss: presentPendingImport) {
                ImportDocumentView(
                    model: model,
                    kind: .bookSource,
                    text: $importText,
                    onSources: { sources in
                        pendingImportSources = sources
                    }
                )
            }
            .sheet(item: $importPreview) { preview in
                NavigationStack {
                    BookSourceImportPreviewView(model: model, sources: preview.sources) { prepared in
                        let count = model.importBookSources(prepared)
                        message = "导入 \(count) 个书源"
                        importPreview = nil
                    }
                }
            }
            .sheet(isPresented: $isCheckPresented) {
                NavigationStack {
                    SourceCheckView(model: model, sources: checkTargets) { hasInvalid in
                        // Upstream `BookSourceActivity.kt:637-642` — the
                        // invalid sources are filtered out of the list.
                        guard hasInvalid, searchText.isEmpty else { return }
                        searchText = "失效"
                        message = "发现有失效书源，已为您自动筛选！"
                    }
                }
            }
            .sheet(isPresented: $isCheckConfigPresented) {
                SourceCheckConfigView(model: model)
            }
            .sheet(isPresented: $isLoginPresented) {
                if let loginSource {
                    NavigationStack {
                        SourceLoginView(source: loginSource, model: model)
                    }
                }
            }
            .sheet(isPresented: $isSharePresented) {
                ShareSheet(items: shareItems)
            }
            .sheet(isPresented: $isSearchPresented) {
                if let searchSource {
                    NavigationStack {
                        SearchView(model: model, source: searchSource)
                    }
                }
            }
            .sheet(isPresented: $isQRCodePresented) {
                NavigationStack {
                    QRCodeView(text: sharedText)
                }
            }
            .sheet(isPresented: $isQRScannerPresented, onDismiss: importPendingQRPayload) {
                NavigationStack {
                    QRScannerView(result: $qrResult)
                }
            }
            .sheet(isPresented: $isEditorPresented) {
                if let editingSource {
                    NavigationStack {
                        SourceEditorView(model: model, source: editingSource) {
                            isEditorPresented = false
                        }
                    }
                }
            }
            .sheet(isPresented: $isHelpPresented) {
                NavigationStack {
                    SourceHelpView()
                }
            }
            .sheet(isPresented: $isGroupPromptPresented) {
                TextPromptView(title: groupPromptTitle, placeholder: "分组名称") { name in
                    applyGroupPrompt(name)
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: SourceManagerView.contentTypes,
                onCompletion: { result in
                    importFile(result)
                }
            )
            .onChange(of: qrResult) { _, value in
                guard let value, !value.isEmpty else { return }
                qrResult = nil
                // The scanner has to go before the preview is opened, or the
                // two sheets compete for the presentation.
                pendingQRPayload = value
                isQRScannerPresented = false
            }
            .onAppear {
                model.reloadSources()
            }
        }
    }

    // MARK: - The list

    /// The sections of the list — upstream `BookSourceAdapter.showSourceHost`
    /// shows a header with the domain of the sources.
    @ViewBuilder
    private var sourceSections: some View {
        if isGroupedByDomain {
            ForEach(sections) { section in
                Section(section.title) {
                    rows(section.sources)
                }
            }
        } else {
            Section {
                rows(visibleSources)
            }
        }
    }

    /// The rows of a section.
    @ViewBuilder
    private func rows(_ sources: [BookSource]) -> some View {
        ForEach(sources, id: \.bookSourceUrl) { source in
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
                },
                onTop: {
                    model.topSources([source])
                },
                onBottom: {
                    model.bottomSources([source])
                },
                onToggleExplore: {
                    model.setSourcesExplore([source], enabled: !source.enabledExplore)
                },
                onDebug: {
                    isDebugPresented = true
                },
                onSearch: {
                    // Upstream `BookSourceActivity.searchBook` — the search is
                    // scoped to that source.
                    searchSource = source
                    isSearchPresented = true
                }
            )
        }
        .onMove { offsets, destination in
            moveSources(in: sources, from: offsets, to: destination)
        }
    }

    /// Moves a row — upstream `BookSourceAdapter.swap` + `onClearView`.
    ///
    /// The visible rows are renumbered by their position (the upstream's
    /// `upOrder` branch).
    private func moveSources(in sources: [BookSource], from offsets: IndexSet, to destination: Int) {
        // The upstream reorders the sources of the whole list; the grouped
        // list cannot be dragged (the domains would mix).
        guard !isGroupedByDomain, sort == .custom else { return }
        guard let first = offsets.first, first < sources.count else { return }
        var list = sources
        let moved = list.remove(at: first)
        list.insert(moved, at: min(destination, list.count))
        model.applySourceOrder(list)
    }

    /// The sources of the list — upstream `BookSourceActivity.upBookSource`
    /// (L293-393): the search key, the sort and the grouping by domain.
    private var visibleSources: [BookSource] {
        let filtered = BookSourceSearch.filter(model.sources, key: searchText)
        guard !isGroupedByDomain else {
            // The upstream groups the sources by their domain and sorts them
            // by the time of the last update.
            return filtered.sorted { lhs, rhs in
                let left = SourceHost.domain(of: lhs.bookSourceUrl)
                let right = SourceHost.domain(of: rhs.bookSourceUrl)
                if left != right {
                    if left == "#" { return false }
                    if right == "#" { return true }
                    return left < right
                }
                return lhs.lastUpdateTime > rhs.lastUpdateTime
            }
        }
        return BookSourceSorter.sort(filtered, by: sort, ascending: isSortAscending)
    }

    /// The sections of the list — the sources of a domain.
    private var sections: [SourceSection] {
        let sources = visibleSources
        guard isGroupedByDomain else {
            return [SourceSection(id: 0, title: "", sources: sources)]
        }
        var result: [SourceSection] = []
        for source in sources {
            let host = SourceHost.domain(of: source.bookSourceUrl)
            if var last = result.last, last.title == host {
                result.removeLast()
                last.sources.append(source)
                result.append(last)
            } else {
                result.append(SourceSection(id: result.count, title: host, sources: [source]))
            }
        }
        return result
    }

    /// The sources of the multi-selection.
    private var selectedSources: [BookSource] {
        model.sources.filter { selection.contains($0.bookSourceUrl) }
    }

    /// The shared document — upstream `BookSourceViewModel.saveToFile`
    /// (L126-165) shares the selection when it is small enough.
    private var sharedText: String {
        if selection.isEmpty {
            return model.exportedSources(model.sources)
        }
        return model.exportedSources(selectedSources)
    }

    /// What the share sheet offers — the exported file when one was written
    /// (upstream `menu_export_selection`), the JSON text otherwise
    /// (upstream `menu_share_source`).
    private var shareItems: [Any] {
        if let exportedFileURL {
            return [exportedFileURL]
        }
        return [sharedText]
    }

    // MARK: - The actions

    /// The sources of an import preview.
    ///
    /// The preview is presented with `sheet(item:)` so that it is built with
    /// the sources in hand instead of reading them from the view state while
    /// the import dialog is still being dismissed.
    struct ImportPreview: Identifiable {
        let id = UUID()
        let sources: [BookSource]
    }

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

    /// A new source — upstream `menu_add_book_source` opens the editor of a
    /// new source.
    private func newSource() -> BookSource {
        var source = BookSource(bookSourceUrl: "")
        source.bookSourceName = "新建书源"
        return source
    }

    /// Imports a local file — upstream `menu_import_local`.
    @MainActor
    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                message = DocumentImporter.failureMessage
                return
            }
            await importPayload(text)
        }
    }

    /// Shows the preview of the sources the import dialog handed over.
    ///
    /// The dialog has closed by the time this runs (`onDismiss`), so the
    /// preview no longer competes with it for the presentation and the
    /// sources are no longer read from a half-updated view state.
    private func presentPendingImport() {
        let sources = pendingImportSources
        pendingImportSources = []
        guard !sources.isEmpty else { return }
        importPreview = ImportPreview(sources: sources)
    }

    /// Imports the scanned document once the scanner has closed.
    @MainActor
    private func importPendingQRPayload() {
        guard let payload = pendingQRPayload else { return }
        pendingQRPayload = nil
        Task {
            await importPayload(payload)
        }
    }

    /// Parses an imported document and shows the preview of the import —
    /// upstream `ImportBookSourceDialog`.
    ///
    /// The document is either a JSON document with the sources, a document
    /// with a list of `sourceUrls`, or the url of such a document.
    ///
    /// The state of the view is only written on the main actor: the parsing
    /// runs in a task, and a `@State` write from a background task reaches the
    /// next sheet too late (or not at all).
    @MainActor
    private func importPayload(_ text: String) async {
        let payload = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return }
        do {
            let sources: [BookSource]
            if BookSourceImport.isAbsoluteURL(payload) {
                _ = ImportUrlHistory.add(payload, .bookSource, store: model.environment.store)
                sources = try await model.environment.bookSourcesOfImport(url: payload)
            } else {
                sources = try await model.environment.bookSourcesOfImport(json: payload)
            }
            guard !sources.isEmpty else {
                message = DocumentImporter.failureMessage
                return
            }
            importPreview = ImportPreview(sources: sources)
        } catch {
            message = DocumentImporter.failureMessage
        }
    }

    /// Exports the selection — upstream `menu_export_selection` (the file)
    /// and `menu_share_source` (the share sheet).
    private func exportSelection() {
        let json = model.exportedSources(selectedSources)
        guard let data = json.data(using: .utf8) else {
            message = "导出失败"
            return
        }
        do {
            // Upstream `menu_export_selection` → `saveToFile` → the file
            // picker; the share sheet offers "Save to Files" on iOS.
            exportedFileURL = try DocumentExporter.write(data, fileName: "bookSource.json")
            isSharePresented = true
            message = "已导出 \(selectedSources.count) 个书源"
        } catch {
            message = "导出失败：\(error.localizedDescription)"
        }
    }

    /// Asks for the name of a group — upstream
    /// `BookSourceActivity.selectionAddToGroups` (L539-577).
    private func promptGroup(_ action: GroupPromptAction) {
        groupPromptAction = action
        groupPromptTitle = action == .add ? "加入分组" : "移出分组"
        isGroupPromptPresented = true
    }

    /// Applies the group of the prompt.
    private func applyGroupPrompt(_ name: String) {
        switch groupPromptAction {
        case .add:
            model.addSourcesToGroup(selectedSources, group: name)
        case .remove:
            model.removeSourcesFromGroup(selectedSources, group: name)
        }
    }
}

/// The action of the prompt of a group.
enum GroupPromptAction {
    case add
    case remove
}

/// A section of the list of the sources — upstream
/// `BookSourceAdapter.getHeaderText` (L295-305).
struct SourceSection: Identifiable {
    let id: Int
    let title: String
    var sources: [BookSource]
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
    var onTop: (() -> Void)?
    var onBottom: (() -> Void)?
    var onToggleExplore: (() -> Void)?
    var onDebug: (() -> Void)?
    /// Upstream `BookSourceAdapter.showMenu` — `menu_search`.
    var onSearch: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    // Upstream `BookSourceAdapter.upShowExplore` (L208-226):
                    // a green dot when the discovery is on, a red one when the
                    // source has a discovery but it is off.
                    if source.exploreUrl != nil || source.ruleExplore != nil {
                        Text(source.enabledExplore ? "●" : "●")
                            .font(.system(size: 10))
                            .foregroundColor(source.enabledExplore ? .green : .red)
                    }
                    Text(source.bookSourceName)
                        .font(.system(size: 16))
                }
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
            if let onEdit {
                Button("编辑", action: onEdit)
                    .font(.system(size: 12))
            }
            Toggle("启用", isOn: Binding(get: { source.enabled }, set: onToggle))
                .labelsHidden()
            // Upstream `BookSourceAdapter.showMenu` (L164-206).
            Menu {
                if let onTop {
                    Button("置顶", action: onTop)
                }
                if let onBottom {
                    Button("置底", action: onBottom)
                }
                if let onToggleExplore {
                    Button(source.enabledExplore ? "禁用发现" : "允许发现", action: onToggleExplore)
                }
                if let onLogin, source.loginUrl != nil || source.loginUi != nil {
                    Button("登录", action: onLogin)
                }
                if let onDebug {
                    Button("调试", action: onDebug)
                }
                if let onSearch {
                    Button("搜索该源", action: onSearch)
                }
                Button("删除", role: .destructive, action: onDelete)
            } label: {
                Text("更多")
                    .font(.system(size: 12))
            }
        }
        .padding(.vertical, 4)
    }
}
