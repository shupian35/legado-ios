//
//  ManageSources.swift
//  LegadoUI
//
//  The management of the book sources and the RSS sources.
//
//  Upstream `ui/book/source/manage/BookSourceActivity.kt` lists the sources
//  with their groups, lets the user sort them, filter them, edit them in bulk
//  (the enable / delete / move to a group / export) and open the group manager
//  (`GroupManageDialog.kt`). The RSS sources have their own screen
//  (`ui/rss/source/manage/RssSourceActivity.kt`).
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

// MARK: - The source groups

/// The manager of the source groups — upstream `GroupManageDialog`.
///
/// The upstream adds a group (`addGroup`, L72-88), renames it
/// (`editGroup`, L90-103) and deletes it (`delGroup`).
public struct SourceGroupView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var groups: [String] = []
    @State private var newGroup: String = ""
    @State private var isRenamePresented = false
    @State private var editingGroup: String = ""
    @State private var editName: String = ""

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
                            editingGroup = group
                            editName = group
                            isRenamePresented = true
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
        .sheet(isPresented: $isRenamePresented) {
            TextPromptView(title: "重命名分组", placeholder: "分组名称", initial: editName) { name in
                model.renameSourceGroup(editingGroup, to: name)
                reload()
            }
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        groups = model.sourceGroups()
    }

    /// Adds a group — upstream `BookSourceViewModel.addGroup` (L251-259):
    /// every source **without** a group gets the new group.
    private func add() {
        let name = newGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        model.addSourceGroup(name)
        newGroup = ""
        reload()
    }

    /// Deletes a group — upstream `BookSourceViewModel.delGroup` (L276-286).
    private func delete(_ group: String) {
        model.removeSourceGroup(group)
        reload()
    }
}

// MARK: - The RSS sources

/// The RSS sources — upstream `ui/rss/source/manage/RssSourceActivity`.
///
/// The upstream imports the sources from a file, from an url or from a QR code
/// (`menu_import_local`, `menu_import_onLine`, `menu_import_qr`).
public struct RssSourceManagerView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var sources: [RssSource] = []
    @State private var editing: RssSource?
    @State private var searchText: String = ""
    @State private var isImportPresented = false
    @State private var importText: String = ""
    @State private var isFileImporterPresented = false
    @State private var isQRScannerPresented = false
    @State private var qrResult: String?
    @State private var isHelpPresented = false
    @State private var message: String?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            ForEach(filteredSources, id: \.sourceUrl) { source in
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.sourceName)
                    Text(source.sourceUrl)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    editing = source
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
        .navigationTitle("订阅源")
        .searchable(text: $searchText, prompt: "搜索订阅源")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("添加") {
                    editing = RssSource(sourceUrl: "", sourceName: "")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                // Upstream `RssSourceViewModel.restoreDefault`.
                Button("恢复默认") {
                    try? DefaultData.importDefaultRssSources(store: model.environment.store)
                    reload()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
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
                    ForEach(BookSourceSearch.filters, id: \.self) { filter in
                        Button(filter) {
                            searchText = filter
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
                // Upstream `menu_help` shows the `SourceMRssHelp` document.
                Button("帮助") {
                    isHelpPresented = true
                }
            }
        }
        .sheet(item: $editing) { source in
            RssSourceEditView(
                model: model,
                source: source,
                onSave: { saved in
                    model.saveRssSource(saved)
                    reload()
                },
                onClose: {
                    editing = nil
                }
            )
        }
        .sheet(isPresented: $isImportPresented) {
            ImportDocumentView(model: model, kind: .rssSource, text: $importText)
        }
        .sheet(isPresented: $isQRScannerPresented) {
            NavigationStack {
                QRScannerView(result: $qrResult)
            }
        }
        .sheet(isPresented: $isHelpPresented) {
            NavigationStack {
                RssSourceHelpView()
            }
        }
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: RssSourceManagerView.contentTypes,
            onCompletion: { result in
                importFile(result)
            }
        )
        .onChange(of: qrResult) { _, value in
            guard let value, !value.isEmpty else { return }
            qrResult = nil
            Task {
                message = await RssSourceImporter.importText(value, model: model)
                reload()
            }
        }
        .onAppear {
            reload()
        }
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

    /// The sources of the list — upstream the filters of the search box.
    private var filteredSources: [RssSource] {
        let key = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return sources }
        if key == BookSourceSearch.enabled { return sources.filter { $0.enabled } }
        if key == BookSourceSearch.disabled { return sources.filter { !$0.enabled } }
        if key == BookSourceSearch.noGroup {
            return sources.filter { ($0.sourceGroup ?? "").isEmpty }
        }
        return sources.filter {
            $0.sourceName.contains(key) || $0.sourceUrl.contains(key)
        }
    }

    private func reload() {
        sources = (try? model.environment.store.allRssSources()) ?? []
    }

    /// Imports a local file — upstream `menu_import_local`.
    private func importFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        Task {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                message = RssSourceImporter.failureMessage
                return
            }
            message = await RssSourceImporter.importText(text, model: model)
            reload()
        }
    }
}

/// The help of the RSS sources — upstream the `SourceMRssHelp` document.
public struct RssSourceHelpView: View {

    public init() {}

    public var body: some View {
        ScrollView {
            Text(RssSourceHelp.text)
                .font(.system(size: 14))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        .navigationTitle("帮助")
    }
}

/// The text of the help of the RSS sources.
public enum RssSourceHelp {
    /// The upstream `SourceMRssHelp.md`.
    public static let text = """
    # 订阅源管理界面帮助

    * 订阅源可以通过规则订阅一些网络内容
    * 右上角有分组菜单,可以按分组筛选订阅源
    * 右上角更多菜单里包含
      * 新建订阅源
      * 本地导入
      * 网络导入
      * 二维码导入
      * 分享选中源
    * 选择源的更多操作在右下角的菜单里面,操作都是针对选择的订阅源
      * 启用所选
      * 禁用所选
      * 置顶所选
      * 置底所选
      * 导出所选
    """
}

// MARK: - The source sorting

/// The sorting of the book sources — upstream `BookSourceSortDialog`.
///
/// Upstream `ui/book/source/manage/BookSourceSort.kt` (L3-4) has the cases
/// `Default`, `Name`, `Url`, `Weight`, `Update`, `Enable` and `Respond`; the
/// port keeps its own `Group` case as well.
public enum BookSourceSort: String, CaseIterable, Identifiable {
    /// The manual order (`customOrder`) — upstream `Default`.
    case custom = "手动排序"
    /// The name — upstream `Name`.
    case name = "名称"
    /// The group (an extra of the port).
    case group = "分组"
    /// The url of the source — upstream `Url`.
    case url = "链接"
    /// The response time — upstream `Respond`.
    case respondTime = "响应时间"
    /// The last update time — upstream `Update`.
    case updateTime = "更新时间"
    /// The weight — upstream `Weight`.
    case weight = "权重"
    /// Whether the source is enabled — upstream `Enable`.
    case enable = "是否启用"

    public var id: String { rawValue }

    public var title: String { rawValue }
}

/// Sorts the book sources the way the upstream dialog does.
///
/// Upstream `BookSourceViewModel.getBookSources` (L167-249) sorts the
/// ascending and the descending way; the descending variant of `Default`
/// reverses the list.
public enum BookSourceSorter {
    /// Sorts the sources by the given criterion.
    public static func sort(_ sources: [BookSource], by sort: BookSourceSort) -> [BookSource] {
        BookSourceSorter.sort(sources, by: sort, ascending: true)
    }

    /// Sorts the sources by the given criterion — upstream
    /// `BookSourceViewModel.getBookSources` (L167-249).
    public static func sort(
        _ sources: [BookSource],
        by sort: BookSourceSort,
        ascending: Bool
    ) -> [BookSource] {
        switch sort {
        case .custom:
            // The upstream keeps the order of the database (by `customOrder`)
            // and reverses it for the descending way.
            let ordered = sources.sorted { lhs, rhs in
                if lhs.customOrder != rhs.customOrder { return lhs.customOrder < rhs.customOrder }
                return lhs.bookSourceName < rhs.bookSourceName
            }
            return ascending ? ordered : ordered.reversed()
        case .name:
            let ordered = sources.sorted { lhs, rhs in
                if lhs.bookSourceName != rhs.bookSourceName {
                    return lhs.bookSourceName.compare(rhs.bookSourceName) == .orderedAscending
                }
                return lhs.bookSourceUrl < rhs.bookSourceUrl
            }
            return ascending ? ordered : ordered.reversed()
        case .group:
            let ordered = sources.sorted { lhs, rhs in
                let left = lhs.bookSourceGroup ?? ""
                let right = rhs.bookSourceGroup ?? ""
                if left != right { return left.compare(right) == .orderedAscending }
                return lhs.bookSourceName < rhs.bookSourceName
            }
            return ascending ? ordered : ordered.reversed()
        case .url:
            let ordered = sources.sorted { $0.bookSourceUrl < $1.bookSourceUrl }
            return ascending ? ordered : ordered.reversed()
        case .respondTime:
            let ordered = sources.sorted { lhs, rhs in
                if lhs.respondTime != rhs.respondTime { return lhs.respondTime < rhs.respondTime }
                return lhs.bookSourceName < rhs.bookSourceName
            }
            return ascending ? ordered : ordered.reversed()
        case .updateTime:
            // The upstream sorts the last update time descending.
            let ordered = sources.sorted { lhs, rhs in
                if lhs.lastUpdateTime != rhs.lastUpdateTime {
                    return lhs.lastUpdateTime > rhs.lastUpdateTime
                }
                return lhs.bookSourceName < rhs.bookSourceName
            }
            return ascending ? ordered : ordered.reversed()
        case .weight:
            let ordered = sources.sorted { lhs, rhs in
                if lhs.weight != rhs.weight { return lhs.weight > rhs.weight }
                return lhs.bookSourceName < rhs.bookSourceName
            }
            return ascending ? ordered : ordered.reversed()
        case .enable:
            // The upstream sorts the disabled sources first.
            let ordered = sources.sorted { lhs, rhs in
                if lhs.enabled != rhs.enabled { return !lhs.enabled }
                return lhs.bookSourceName < rhs.bookSourceName
            }
            return ascending ? ordered : ordered.reversed()
        }
    }
}
