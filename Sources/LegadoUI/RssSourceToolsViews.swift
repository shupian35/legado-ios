//
//  RssSourceToolsViews.swift
//  LegadoUI
//
//  The tools of the RSS sources: the preview of the import, the debugger of
//  the sources and the editor of a favourite.
//
//  Upstream:
//  - `ui/association/ImportRssSourceDialog.kt` — the preview of the import,
//  - `ui/association/ImportRssSourceViewModel.kt` — the options of the
//    import,
//  - `ui/rss/source/debug/RssSourceDebugActivity.kt` — the debugger,
//  - `ui/rss/favorites/RssFavoritesDialog.kt` — the editor of a favourite.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

// MARK: - The preview of the import of the RSS sources

/// The preview of the import of the RSS sources — upstream
/// `ui/association/ImportRssSourceDialog.kt`.
///
/// The upstream lists every imported source with a check box, its name and
/// its state ("新增", "更新" or "已有"), the footer has 全选/反选 with the
/// number of the selected sources, 取消 and 确定, and the menu holds the
/// options of the import (保留名称 / 保留分组 / 保留启用 / 新建分组).
public struct RssSourceImportPreviewView: View {

    @ObservedObject var model: LegadoAppModel

    /// The imported sources.
    let sources: [RssSource]

    /// The action of the import — the prepared sources are handed over.
    let onImport: ([RssSource]) -> Void

    /// The preview — upstream `comparisonSource`.
    @State private var items: [RssSourceImport.Item] = []

    /// The options of the import — upstream `importSelect`.
    @State private var options = RssSourceImport.Options()

    /// The group of the import — upstream `menu_new_group`.
    @State private var groupName: String = ""

    /// Whether the group prompt is shown.
    @State private var isGroupPromptPresented = false

    /// The source whose JSON is shown — upstream `CodeDialog`.
    @State private var codeItem: RssSourceImport.Item?

    public init(
        model: LegadoAppModel,
        sources: [RssSource],
        onImport: @escaping ([RssSource]) -> Void
    ) {
        self.model = model
        self.sources = sources
        self.onImport = onImport
    }

    public var body: some View {
        List {
            Section {
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Button(item.selected ? "☑" : "☐") {
                            toggle(item.id)
                        }
                        .buttonStyle(PlainButtonStyle())
                        Button {
                            codeItem = item
                        } label: {
                            Text(item.source.sourceName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                        Text(item.state.rawValue)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            Section {
                HStack {
                    Button(selectedAll ? "反选" : "全选") {
                        selectAll()
                    }
                    Spacer()
                    Text("已选 \(selectedCount) 个")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                Button("确定") {
                    confirm()
                }
            }
        }
        .navigationTitle("导入订阅源")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                // The upstream `res/menu/import_source.xml`.
                Menu("选项") {
                    Toggle("保留原名称", isOn: $options.keepName)
                    Toggle("保留原分组", isOn: $options.keepGroup)
                    Toggle("保留原启用状态", isOn: $options.keepEnable)
                    Button("新建分组") {
                        isGroupPromptPresented = true
                    }
                }
            }
        }
        .alert("新建分组", isPresented: $isGroupPromptPresented) {
            Button("取消", role: .cancel) {}
            Button("确定") {
                options.groupName = groupName
            }
        } message: {
            Text("导入的订阅源将放入该分组")
        }
        .alert("订阅源", isPresented: Binding(
            get: { codeItem != nil },
            set: { if !$0 { codeItem = nil } }
        )) {
            Button("关闭", role: .cancel) {}
        } message: {
            Text(codeItem.map { RssSourceJSONBridge.encode($0.source).jsonString } ?? "")
        }
        .onAppear {
            reload()
        }
    }

    // MARK: - The helpers

    /// The number of the selected sources.
    private var selectedCount: Int {
        items.filter { $0.selected }.count
    }

    /// Whether every source is selected.
    private var selectedAll: Bool {
        !items.isEmpty && selectedCount == items.count
    }

    /// Builds the preview — upstream `comparisonSource`.
    private func reload() {
        items = (try? model.environment.rssImportPreview(sources)) ?? []
    }

    /// Selects or deselects a source.
    private func toggle(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].selected.toggle()
    }

    /// Selects every source, or deselects them all — upstream `selectAll`.
    private func selectAll() {
        let all = selectedAll
        for index in items.indices {
            items[index].selected = !all
        }
    }

    /// The import — upstream `importSelect`.
    private func confirm() {
        let local = (try? model.environment.store.allRssSources()) ?? []
        let prepared = RssSourceImport.prepare(items, local: local, options: options)
        onImport(prepared)
    }
}

// MARK: - The debugger of the RSS sources

/// The debugger of the RSS sources — upstream
/// `ui/rss/source/debug/RssSourceDebugActivity`.
///
/// The upstream shows the log lines of the debug run and the menu holds the
/// raw HTML of the list page and of the article page.
public struct RssSourceDebugView: View {

    @ObservedObject var model: LegadoAppModel

    /// The source to debug — the upstream is opened with the key of the
    /// source that is being edited.
    let sourceUrl: String?

    /// The source that is being debugged.
    @State private var selectedUrl: String = ""

    /// The log lines.
    @State private var logs: [DebugLogEntry] = []

    /// Whether a debug run is in progress.
    @State private var isRunning = false

    /// The raw HTML of the list page — upstream `listSrc`.
    @State private var listHtml: String = ""

    /// The raw HTML of the article page — upstream `contentSrc`.
    @State private var contentHtml: String = ""

    /// The page whose raw HTML is shown.
    @State private var htmlPage: RssDebugHtmlPage?

    public init(model: LegadoAppModel, sourceUrl: String? = nil) {
        self.model = model
        self.sourceUrl = sourceUrl
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker("订阅源", selection: $selectedUrl) {
                    ForEach(model.rssSources, id: \.sourceUrl) { source in
                        Text(source.sourceName).tag(source.sourceUrl)
                    }
                }
                HStack {
                    Button("开始调试") {
                        run()
                    }
                    .disabled(isRunning || selectedUrl.isEmpty)
                    if isRunning {
                        ProgressView()
                    }
                }
            }
            .padding(12)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(logs) { entry in
                        Text(entry.message)
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(12)
            }
        }
        .navigationTitle("订阅源调试")
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                // The upstream `res/menu/rss_source_debug.xml`.
                Menu("调试") {
                    Button("列表页源码") {
                        htmlPage = .list
                    }
                    Button("内容页源码") {
                        htmlPage = .content
                    }
                }
            }
        }
        .onAppear {
            if let sourceUrl {
                selectedUrl = sourceUrl
            } else if selectedUrl.isEmpty, let first = model.rssSources.first {
                selectedUrl = first.sourceUrl
            }
        }
        .sheet(item: $htmlPage) { page in
            NavigationStack {
                DebugHtmlView(title: page.title, html: page == .list ? listHtml : contentHtml)
                    .navigationTitle(page.title)
            }
        }
    }

    /// Runs the debugger and collects the log.
    private func run() {
        guard let source = model.rssSources.first(where: { $0.sourceUrl == selectedUrl }) else { return }
        logs = []
        isRunning = true
        listHtml = ""
        contentHtml = ""
        let debugger = SourceDebugger()
        let collector = DebugLogCollector()
        debugger.sink = collector
        Task {
            await debugger.debugRssSource(
                source,
                dependencies: model.environment.dependencies(),
                scriptEngine: model.environment.scriptEngine
            )
            await MainActor.run {
                logs = collector.entries
                // The state 10 is the HTML of the list page and the state 20
                // the HTML of the article page.
                listHtml = collector.searchHtml
                contentHtml = collector.bookHtml
                isRunning = false
            }
        }
    }
}

/// The raw HTML pages of the RSS debug — upstream
/// `res/menu/rss_source_debug.xml`.
public enum RssDebugHtmlPage: String, Identifiable {
    /// The list page — upstream `menu_list_src`.
    case list
    /// The article page — upstream `menu_content_src`.
    case content

    public var id: String { rawValue }

    /// The title of the dialog.
    public var title: String {
        switch self {
        case .list: return "列表页源码"
        case .content: return "内容页源码"
        }
    }
}

// MARK: - The editor of a favourite

/// The editor of a favourite — upstream `ui/rss/favorites/RssFavoritesDialog`.
///
/// The upstream edits the title and the group of the favourite; the button
/// of the footer deletes it.
public struct RssFavoriteEditView: View {

    /// The edited favourite.
    @State private var draft: RssStar

    /// The groups of the favourites — upstream `RssFavoritesFragment`.
    let groups: [String]

    /// The action of the save.
    let onSave: (RssStar) -> Void

    /// The action of the delete.
    let onDelete: () -> Void

    public init(
        star: RssStar,
        groups: [String],
        onSave: @escaping (RssStar) -> Void,
        onDelete: @escaping () -> Void
    ) {
        _draft = State(initialValue: star)
        self.groups = groups
        self.onSave = onSave
        self.onDelete = onDelete
    }

    public var body: some View {
        Form {
            Section("收藏") {
                TextField("标题", text: $draft.title)
                Picker("分组", selection: $draft.group) {
                    ForEach(groupNames, id: \.self) { group in
                        Text(group).tag(group)
                    }
                }
            }
        }
        .navigationTitle("编辑收藏")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("确定") {
                    onSave(draft)
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("删除", role: .destructive) {
                    onDelete()
                }
            }
        }
    }

    /// The groups of the picker — the groups of the favourites and the group
    /// of the favourite itself.
    private var groupNames: [String] {
        var names = groups
        if !draft.group.isEmpty, !names.contains(draft.group) {
            names.append(draft.group)
        }
        return names
    }
}
