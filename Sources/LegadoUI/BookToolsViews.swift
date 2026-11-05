//
//  BookToolsViews.swift
//  LegadoUI
//
//  The book tools of the upstream app:
//
//  * 换源 (change source) — upstream `ui/book/changesource/`;
//  * 搜索正文 (search inside the book) — upstream `ui/book/searchContent/`;
//  * 校验 (verify a book source) — upstream `ui/config/CheckSourceConfig`.
//
//  The logic lives in `LegadoCore` (`Pipeline/ChangeSource.swift`,
//  `Pipeline/ContentSearch.swift`, `Pipeline/SourceCheck.swift`), the views
//  only drive it.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

// MARK: - 换源

/// The change-source sheet: it searches the other book sources for the same
/// book and lets the reader move the book over to another source.
public struct ChangeSourceView: View {

    @ObservedObject var model: LegadoAppModel
    let book: Book

    @State private var candidates: [ChangeSourceCandidate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var didSearch = false
    /// The user score of the candidates — upstream `SourceConfig`.
    @State private var scores: [String: Int] = [:]
    /// The source that is being edited — upstream `menu_edit_source`.
    @State private var editingSource: BookSource?
    /// The source that is about to be deleted — upstream `menu_delete_source`.
    @State private var deletingSource: BookSource?
    /// The group the search is scoped to — upstream `AppConfig.searchGroup`
    /// (the menu `res/menu/change_source.xml` → `menu_group`).
    @State private var group: String = ""
    /// The running search — upstream `ChangeBookSourceViewModel.task`.
    @State private var searchTask: Task<Void, Never>?
    /// The source manager — upstream `menu_source_manage`.
    @State private var isSourceManagerPresented = false
    /// Called when the sheet is closed — upstream `menu_close`.
    private let onClose: (() -> Void)?

    public init(model: LegadoAppModel, book: Book, onClose: (() -> Void)? = nil) {
        self.model = model
        self.book = book
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Upstream `ChangeBookSourceDialog` — the four switches of the
            // menu `res/menu/change_source.xml`; they are stored in the
            // preferences (`AppConfig.changeSource*`).
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Toggle("校验作者", isOn: settingBinding(.changeSourceCheckAuthor))
                    Toggle("加载详情", isOn: settingBinding(.changeSourceLoadInfo))
                }
                HStack {
                    Toggle("加载目录", isOn: settingBinding(.changeSourceLoadToc))
                    Toggle("加载字数", isOn: settingBinding(.changeSourceLoadWordCount))
                    Button("搜索") {
                        search()
                    }
                }
            }
            if isLoading {
                ProgressView("正在搜索…")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            if candidates.isEmpty && !isLoading && didSearch {
                EmptyState(text: "没有找到其他来源")
            }
            List(candidates, id: \.scoreKey) { candidate in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(candidate.sourceName)
                            .font(.system(size: 15, weight: .medium))
                        Text(candidate.book.name)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                        HStack {
                            Text(candidate.book.author)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            if let wordCount = candidate.chapterWordCountText {
                                Text(wordCount)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    Spacer()
                    // Upstream `ChangeBookSourceAdapter` — the 好评 / 差评
                    // buttons of the row.
                    scoreButtons(candidate)
                }
                .onTapGesture {
                    switchSource(candidate)
                }
                .contextMenu {
                    // Upstream `ChangeBookSourceAdapter.showMenu` — the menu
                    // `res/menu/change_source_item.xml`.
                    Button("置顶") { moveSource(candidate, toTop: true) }
                    Button("置底") { moveSource(candidate, toTop: false) }
                    Button("编辑") { editingSource = source(of: candidate) }
                    Button("禁用") { disableSource(candidate) }
                    Button("删除", role: .destructive) { deletingSource = source(of: candidate) }
                }
            }
            .listStyle(PlainListStyle())
        }
        .padding(16)
        .navigationTitle("换源")
        .onAppear {
            // Upstream `ChangeBookSourceDialog` reads the group of the
            // search scope when it opens.
            if group.isEmpty {
                group = model.environment.settings.searchGroup
            }
        }
        .toolbar {
            // Upstream `res/menu/change_source.xml` — the group submenu
            // (`menu_group`), the start/stop button (`menu_start_stop`) and
            // the overflow items (`menu_source_manage`, `menu_refresh_list`,
            // `menu_close`).
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Section("分组") {
                        Button("全部书源") { selectGroup("") }
                        ForEach(sourceGroups, id: \.self) { name in
                            Button(name) { selectGroup(name) }
                        }
                    }
                } label: {
                    Text(group.isEmpty ? "分组" : "分组(\(group))")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(isLoading ? "停止" : "开始") {
                    if isLoading {
                        stopSearch()
                    } else {
                        search()
                    }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("书源管理") { isSourceManagerPresented = true }
                    Button("刷新列表") { refreshList() }
                    Button("关闭") { onClose?() }
                } label: {
                    Text("更多")
                }
            }
        }
        .sheet(isPresented: $isSourceManagerPresented) {
            NavigationStack {
                SourceManagerView(model: model)
            }
        }
        .sheet(item: $editingSource) { source in
            NavigationStack {
                SourceEditorView(model: model, source: source, onClose: { editingSource = nil })
            }
        }
        .alert("删除", isPresented: deleteAlertBinding) {
            Button("取消", role: .cancel) { deletingSource = nil }
            Button("确定", role: .destructive) {
                if let deletingSource {
                    model.deleteSource(deletingSource)
                    candidates.removeAll { $0.sourceUrl == deletingSource.bookSourceUrl }
                }
                deletingSource = nil
            }
        } message: {
            Text("确定要删除\n\(deletingSource?.bookSourceName ?? "")")
        }
    }

    // MARK: - The score (upstream `SourceConfig`)

    /// The 好评 / 差评 buttons of a row — upstream
    /// `ChangeBookSourceAdapter.registerListener`.
    private func scoreButtons(_ candidate: ChangeSourceCandidate) -> some View {
        let score = scores[candidate.scoreKey] ?? 0
        return HStack(spacing: 6) {
            Button {
                toggleScore(candidate, good: true)
            } label: {
                Image(systemName: "hand.thumbsup")
                    .foregroundColor(score > 0 ? .red : .secondary)
            }
            Button {
                toggleScore(candidate, good: false)
            } label: {
                Image(systemName: "hand.thumbsdown")
                    .foregroundColor(score < 0 ? .blue : .secondary)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Toggles the score of a book — upstream
    /// `ChangeBookSourceAdapter`: the 好评 sets the score to 1 when the book
    /// is not rated yet (or rated badly) and resets it to 0 otherwise; the
    /// 差评 is symmetric.
    private func toggleScore(_ candidate: ChangeSourceCandidate, good: Bool) {
        let current = scores[candidate.scoreKey] ?? 0
        let new: Int
        if good {
            new = current <= 0 ? 1 : 0
        } else {
            new = current >= 0 ? -1 : 0
        }
        model.setBookScore(
            origin: candidate.sourceUrl,
            name: candidate.book.name,
            author: candidate.book.author,
            score: new
        )
        scores[candidate.scoreKey] = new
    }

    // MARK: - The source of a candidate

    /// The source a candidate came from.
    private func source(of candidate: ChangeSourceCandidate) -> BookSource? {
        (try? model.environment.sources())?.first { $0.bookSourceUrl == candidate.sourceUrl }
    }

    /// Moves the source of a candidate to the top or to the bottom — upstream
    /// `ChangeBookSourceViewModel.topSource` / `bottomSource`.
    private func moveSource(_ candidate: ChangeSourceCandidate, toTop: Bool) {
        guard let source = source(of: candidate) else { return }
        model.moveSource(source, toTop: toTop)
    }

    /// Disables the source of a candidate — upstream
    /// `ChangeBookSourceViewModel.disableSource`.
    private func disableSource(_ candidate: ChangeSourceCandidate) {
        guard let source = source(of: candidate) else { return }
        model.setSource(source, enabled: false)
        candidates.removeAll { $0.sourceUrl == candidate.sourceUrl }
    }

    /// The binding of the delete confirmation.
    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deletingSource != nil },
            set: { if !$0 { deletingSource = nil } }
        )
    }

    private func search() {
        isLoading = true
        errorMessage = nil
        didSearch = true
        let settings = model.environment.settings
        // Upstream `SourceConfig` — the scores the user gave to the books.
        let config = SourceConfig.load(store: model.environment.store)
        // The group of the search — upstream `AppConfig.searchGroup`.
        let group = self.group
        searchTask?.cancel()
        searchTask = Task {
            do {
                let all = try model.environment.sources(enabledOnly: true)
                // Upstream `ChangeBookSourceViewModel.getEnabledPartByGroup`.
                let sources = ChangeSourceService.sources(all, group: group.isEmpty ? nil : group)
                let options = ChangeSourceOptions(
                    checkAuthor: settings.bool(.changeSourceCheckAuthor, default: false),
                    loadInfo: settings.bool(.changeSourceLoadInfo, default: false),
                    loadToc: settings.bool(.changeSourceLoadToc, default: false),
                    loadWordCount: settings.bool(.changeSourceLoadWordCount, default: false),
                    group: group.isEmpty ? nil : group,
                    bookScores: config.bookScores,
                    sourceScores: config.sourceScores
                )
                let found = await ChangeSourceService.search(
                    book: book,
                    sources: sources,
                    options: options,
                    dependencies: model.environment.dependencies()
                )
                guard !Task.isCancelled else { return }
                candidates = found
                scores = Dictionary(
                    uniqueKeysWithValues: found.map { ($0.scoreKey, config.bookScore(key: $0.scoreKey)) }
                )
                if found.isEmpty && !group.isEmpty {
                    // Upstream `ChangeBookSourceDialog.searchFinishCallback` —
                    // the empty result of a group asks whether the search
                    // should run over every group.
                    errorMessage = "\(group)分组搜索结果为空，是否切换到全部分组？"
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }

    /// Stops the running search — upstream
    /// `ChangeBookSourceViewModel.stopSearch`.
    private func stopSearch() {
        searchTask?.cancel()
        searchTask = nil
        isLoading = false
    }

    /// Refreshes the list of the candidates — upstream
    /// `ChangeBookSourceViewModel.startRefreshList` (the found books are
    /// searched again so their information is up to date).
    private func refreshList() {
        search()
    }

    /// The groups of the enabled sources — upstream
    /// `BookSourceDao.flowEnabledGroups`.
    private var sourceGroups: [String] {
        let sources = (try? model.environment.sources(enabledOnly: true)) ?? []
        var groups: [String] = []
        for source in sources {
            for name in (source.bookSourceGroup ?? "").split(separator: ",") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !groups.contains(trimmed) {
                    groups.append(trimmed)
                }
            }
        }
        return groups
    }

    /// Selects the group of the search — upstream `ChangeBookSourceDialog`
    /// (`AppConfig.searchGroup = item.title`).
    private func selectGroup(_ name: String) {
        group = name
        model.environment.settings.searchGroup = name
        search()
    }

    /// A binding for one of the switches of the upstream — the value is
    /// stored in the preferences.
    private func settingBinding(_ key: SettingsKey) -> Binding<Bool> {
        Binding(
            get: { model.environment.settings.bool(key, default: false) },
            set: { model.environment.settings.set($0, for: key) }
        )
    }

    private func switchSource(_ candidate: ChangeSourceCandidate) {
        do {
            let switched = ChangeSourceService.switchSource(
                oldBook: book,
                newBook: candidate.book,
                toc: candidate.toc
            )
            try model.environment.store.update(switched)
            model.reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 章节换源

/// The per-chapter source change — upstream
/// `ui/book/changesource/ChangeChapterSourceDialog.kt`.
///
/// The sheet searches the other sources for the book, shows the table of
/// contents of the source the user picked (the chapter that matches the one
/// being read is marked) and fetches the content of the chapter the user
/// picks. The content is handed to the reader, which replaces the content of
/// the chapter it is showing (upstream
/// `ReadBookViewModel.saveContent`).
public struct ChangeChapterSourceView: View {

    @ObservedObject var model: LegadoAppModel
    let book: Book
    /// The index of the chapter the reader is on.
    let chapterIndex: Int
    /// The title of the chapter the reader is on.
    let chapterTitle: String
    /// The number of chapters of the current book.
    let chapterCount: Int
    /// Called with the content of the chapter of the other source.
    let onContent: (String) -> Void

    @State private var candidates: [ChangeSourceCandidate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var checkAuthor = true
    @State private var didSearch = false
    /// The chapter list of the other source.
    @State private var match: ChapterSourceMatch?
    @State private var isLoadingToc = false
    /// The message of the last action.
    @State private var message: String?
    /// The group the search is scoped to — upstream `AppConfig.searchGroup`.
    @State private var group: String = ""
    /// The running search — upstream `ChangeChapterSourceViewModel.task`.
    @State private var searchTask: Task<Void, Never>?

    public init(
        model: LegadoAppModel,
        book: Book,
        chapterIndex: Int,
        chapterTitle: String,
        chapterCount: Int,
        onContent: @escaping (String) -> Void
    ) {
        self.model = model
        self.book = book
        self.chapterIndex = chapterIndex
        self.chapterTitle = chapterTitle
        self.chapterCount = chapterCount
        self.onContent = onContent
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let match {
                chapterList(match)
            } else {
                searchList
            }
        }
        .padding(16)
        .navigationTitle(chapterTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if group.isEmpty {
                group = model.environment.settings.searchGroup
            }
        }
        .toolbar {
            // Upstream `ChangeChapterSourceDialog` uses the same menu
            // `res/menu/change_source.xml`.
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Section("分组") {
                        Button("全部书源") { selectGroup("") }
                        ForEach(sourceGroups, id: \.self) { name in
                            Button(name) { selectGroup(name) }
                        }
                    }
                } label: {
                    Text(group.isEmpty ? "分组" : "分组(\(group))")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button(isLoading ? "停止" : "开始") {
                    if isLoading {
                        stopSearch()
                    } else {
                        search()
                    }
                }
            }
        }
    }

    // MARK: - The search

    @ViewBuilder
    private var searchList: some View {
        HStack {
            Toggle("校验作者", isOn: $checkAuthor)
            Button("搜索") {
                search()
            }
        }
        if isLoading {
            ProgressView("正在搜索…")
        }
        if let errorMessage {
            Text(errorMessage)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        if candidates.isEmpty && !isLoading && didSearch {
            EmptyState(text: "没有找到其他来源")
        }
        List(candidates, id: \.scoreKey) { candidate in
            VStack(alignment: .leading, spacing: 4) {
                Text(candidate.sourceName)
                    .font(.system(size: 15, weight: .medium))
                Text(candidate.book.name)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Text(candidate.book.author)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .onTapGesture {
                loadToc(candidate)
            }
        }
        .listStyle(PlainListStyle())
    }

    // MARK: - The chapter list of the other source

    @ViewBuilder
    private func chapterList(_ match: ChapterSourceMatch) -> some View {
        HStack {
            Button("返回") {
                self.match = nil
            }
            Text(match.sourceName)
                .font(.system(size: 14, weight: .medium))
            if isLoadingToc {
                ProgressView()
            }
        }
        if let message {
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        if match.toc.isEmpty {
            EmptyState(text: "没有目录")
        } else {
            List(match.toc, id: \.url) { chapter in
                let index = match.toc.firstIndex(where: { $0.url == chapter.url }) ?? 0
                HStack {
                    Text(chapter.title)
                        .font(.system(size: 14))
                    if index == match.durChapterIndex {
                        Text("当前")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .onTapGesture {
                    loadContent(match, chapter: chapter, index: index)
                }
            }
            .listStyle(PlainListStyle())
        }
    }

    // MARK: - The work

    private func search() {
        isLoading = true
        errorMessage = nil
        didSearch = true
        let group = self.group
        searchTask?.cancel()
        searchTask = Task {
            do {
                let all = try model.environment.sources(enabledOnly: true)
                // Upstream `ChangeChapterSourceViewModel.getEnabledPartByGroup`.
                let sources = ChangeSourceService.sources(all, group: group.isEmpty ? nil : group)
                let options = ChangeSourceOptions(checkAuthor: checkAuthor, group: group.isEmpty ? nil : group)
                let found = await ChangeSourceService.search(
                    book: book,
                    sources: sources,
                    options: options,
                    dependencies: model.environment.dependencies()
                )
                guard !Task.isCancelled else { return }
                candidates = found
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                }
            }
            isLoading = false
        }
    }

    /// Stops the running search — upstream
    /// `ChangeChapterSourceViewModel.stopSearch`.
    private func stopSearch() {
        searchTask?.cancel()
        searchTask = nil
        isLoading = false
    }

    /// The groups of the enabled sources — upstream
    /// `BookSourceDao.flowEnabledGroups`.
    private var sourceGroups: [String] {
        let sources = (try? model.environment.sources(enabledOnly: true)) ?? []
        var groups: [String] = []
        for source in sources {
            for name in (source.bookSourceGroup ?? "").split(separator: ",") {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && !groups.contains(trimmed) {
                    groups.append(trimmed)
                }
            }
        }
        return groups
    }

    /// Selects the group of the search — upstream
    /// `ChangeChapterSourceDialog` (`AppConfig.searchGroup`).
    private func selectGroup(_ name: String) {
        group = name
        model.environment.settings.searchGroup = name
        search()
    }

    /// Upstream `ChangeChapterSourceDialog.openToc(searchBook)`.
    private func loadToc(_ candidate: ChangeSourceCandidate) {
        isLoadingToc = true
        message = nil
        Task {
            do {
                guard let source = try model.environment.store.source(url: candidate.sourceUrl) else {
                    errorMessage = "书源不存在"
                    isLoadingToc = false
                    return
                }
                let loaded = try await ChangeChapterSourceService.loadMatch(
                    candidate: candidate,
                    source: source,
                    chapterIndex: chapterIndex,
                    chapterTitle: chapterTitle,
                    oldChapterCount: chapterCount,
                    dependencies: model.environment.dependencies()
                )
                match = loaded
            } catch {
                errorMessage = "单章换源获取目录出错\n\(error.localizedDescription)"
            }
            isLoadingToc = false
        }
    }

    /// Upstream `ChangeChapterSourceDialog.clickChapter(bookChapter,
    /// nextChapterUrl)`.
    private func loadContent(_ match: ChapterSourceMatch, chapter: BookChapter, index: Int) {
        isLoadingToc = true
        message = nil
        Task {
            do {
                guard let source = try model.environment.store.source(url: match.sourceUrl) else {
                    errorMessage = "书源不存在"
                    isLoadingToc = false
                    return
                }
                let next = ChangeChapterSourceService.nextChapterUrl(in: match.toc, after: index)
                let content = try await ChangeChapterSourceService.content(
                    match: match,
                    source: source,
                    chapter: chapter,
                    nextChapterUrl: next,
                    dependencies: model.environment.dependencies()
                )
                onContent(content)
            } catch {
                errorMessage = "获取正文出错\n\(error.localizedDescription)"
            }
            isLoadingToc = false
        }
    }
}

// MARK: - 搜索正文

/// The content search sheet: it searches the downloaded chapters of a book.
public struct ContentSearchView: View {

    @ObservedObject var model: LegadoAppModel
    let book: Book

    @State private var query: String = ""
    @State private var results: [ContentSearchResult] = []
    @State private var isLoading = false
    @State private var didSearch = false
    /// Upstream `SearchContentViewModel.replaceEnabled` — the menu toggle
    /// `menu_enable_replace`.
    @State private var useReplaceRule = false
    /// The task of the running search — the stop button cancels it.
    @State private var searchTask: Task<Void, Never>?
    /// The index of the result the user jumped to.
    @State private var currentIndex: Int?

    public init(model: LegadoAppModel, book: Book, initialQuery: String = "") {
        self.model = model
        self.book = book
        _query = State(wrappedValue: initialQuery)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("输入关键词", text: $query)
                Button("搜索") {
                    search()
                }
                if isLoading {
                    // Upstream `binding.fbStop` — it cancels the search job.
                    Button("停止") {
                        stop()
                    }
                }
            }
            // Upstream `binding.tvCurrentSearchInfo` — "搜索结果: N".
            HStack {
                Text("搜索结果: \(results.count)")
                    .font(.system(size: 13))
                Spacer()
                // Upstream `ivSearchContentTop` / `ivSearchContentBottom`.
                Button("顶部") {
                    currentIndex = results.isEmpty ? nil : 0
                }
                Button("底部") {
                    currentIndex = results.isEmpty ? nil : results.count - 1
                }
                // Upstream `menu_enable_replace` — the purification toggle.
                Toggle("净化", isOn: $useReplaceRule)
            }
            if isLoading {
                ProgressView("正在搜索…")
            }
            if results.isEmpty && didSearch && !isLoading {
                // The upstream shows the same hint when the purification or the
                // Chinese conversion hides the query.
                EmptyState(text: "搜索内容为空，请检查净化或简繁设置")
            }
            List(results, id: \.resultCount) { result in
                Button {
                    open(result)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.chapterTitle)
                            .font(.system(size: 13, weight: .medium))
                        Text(result.resultText)
                            .font(.system(size: 13))
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .listStyle(PlainListStyle())
        }
        .padding(16)
        .navigationTitle("搜索正文")
        .onAppear {
            // Upstream `SearchContentActivity` starts the search with the
            // word it was launched with (`intent.getStringExtra("searchWord")`).
            if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                search()
            }
        }
    }

    /// Opens the chapter of the result — upstream
    /// `SearchContentActivity.openSearchResult`.
    private func open(_ result: ContentSearchResult) {
        Task {
            await model.openReader(for: book, chapterIndex: result.chapterIndex, chapterPos: result.queryIndexInChapter)
        }
    }

    /// Stops the running search — upstream `binding.fbStop`.
    private func stop() {
        searchTask?.cancel()
        searchTask = nil
        isLoading = false
    }

    private func search() {
        stop()
        isLoading = true
        didSearch = true
        let query = self.query.trimmingCharacters(in: .whitespacesAndNewlines)
        let useReplace = useReplaceRule
        searchTask = Task {
            do {
                guard let storage = model.environment.cacheStorage else {
                    results = []
                    isLoading = false
                    return
                }
                let chapters = try model.environment.chapters(of: book)
                let titleRules = try model.environment.store.replaceRulesForTitle(
                    name: book.name,
                    origin: book.origin
                )
                let contentRules = try model.environment.store.replaceRulesForContent(
                    name: book.name,
                    origin: book.origin
                )
                let options = ContentSearchOptions(
                    useReplaceRule: useReplace,
                    chineseConversionMode: ChineseConversionMode(
                        rawValue: model.environment.settings.chineseConverterType
                    ) ?? .off
                )
                let found = ContentSearcher.search(
                    book: book,
                    chapters: chapters,
                    query: query,
                    storage: storage,
                    titleRules: titleRules,
                    contentRules: contentRules,
                    options: options,
                    scriptEngine: model.environment.scriptEngine
                )
                if Task.isCancelled { return }
                results = found
            } catch {
                results = []
            }
            isLoading = false
        }
    }
}

// The verification of the book sources moved to `SourceCheckView.swift` — it
// now takes the selection of the user, the keyword of the search, the timeout
// of the check and it can be cancelled.
