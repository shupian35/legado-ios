//
//  SearchView.swift
//  LegadoUI
//
//  The search screen — upstream `ui/book/search/SearchActivity.kt`.
//
//  It searches every source of the scope at the same time (the upstream
//  `SearchModel`), it remembers the keywords, it shows the scope of the
//  search and it opens the detail page of a result.
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

/// The search screen — upstream `SearchActivity`.
public struct SearchView: View {

    @ObservedObject var model: LegadoAppModel

    /// The keyword of the search.
    @State var keyword: String
    /// The scope of the search — upstream `SearchViewModel.searchScope`.
    @State private var scope: SearchScope
    /// The results of the search.
    @State private var results: [SearchBook] = []
    /// Whether a search is running.
    @State private var isLoading = false
    /// The scope dialog.
    @State private var isScopePresented = false
    /// The source manager — upstream `SearchActivity.menu_source_manage`.
    @State private var isSourceManagerPresented = false
    /// The keywords of the history.
    @State private var history: [SearchKeyword] = []
    /// The keys of the books on the shelf — upstream
    /// `SearchViewModel.bookshelf`.
    @State private var shelfKeys: Set<String> = []
    /// The page of the search — upstream `SearchModel.searchPage`.
    @State private var page = 1
    /// Whether the sources have more pages — upstream `SearchModel.hasMore`.
    @State private var hasMore = false
    /// The precise search — upstream `PreferKey.precisionSearch`.
    @State private var isPrecision: Bool
    /// The running search — upstream `SearchModel.searchJob`.
    @State private var searchTask: Task<Void, Never>?
    /// The dialog that offers to turn the precise search off or to widen the
    /// scope — upstream `SearchActivity.searchFinishLiveData`.
    @State private var isEmptyHintPresented = false
    /// The log — upstream `SearchActivity.menu_log`.
    @State private var isLogPresented = false
    /// The books of the shelf that match the keyword — upstream
    /// `SearchActivity.upHistory` (`rvBookshelfSearch`).
    @State private var shelfMatches: [Book] = []

    public init(model: LegadoAppModel, keyword: String = "", source: BookSource? = nil) {
        self.model = model
        self._keyword = State(initialValue: keyword)
        // Upstream `SearchViewModel` — the scope of the search is kept in the
        // preferences; a source that is passed in wins over it.
        let initial = source.map { SearchScope(source: $0) } ?? model.environment.settings.searchScope
        self._scope = State(initialValue: initial)
        self._isPrecision = State(
            initialValue: model.environment.settings.bool(.precisionSearch, default: false)
        )
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                if keyword.isEmpty {
                    historyBar
                } else {
                    // Upstream `SearchActivity.upHistory` — the books of the
                    // shelf that match the keyword.
                    shelfBar
                }
                resultList
            }
            .navigationTitle(scope.display)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if isLoading {
                        Button("停止") {
                            stop()
                        }
                    } else {
                        Button("搜索") {
                            startSearch()
                        }
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        // Upstream `SearchActivity.menu_search_scope` — the
                        // scope of the search.
                        Button("搜索范围") {
                            isScopePresented = true
                        }
                        // Upstream `SearchActivity.menu_precision_search` —
                        // the toggle re-submits the query.
                        Toggle("精准搜索", isOn: Binding(
                            get: { isPrecision },
                            set: { newValue in
                                isPrecision = newValue
                                model.environment.settings.set(newValue, for: .precisionSearch)
                                if !keyword.isEmpty {
                                    startSearch()
                                }
                            }
                        ))
                        // Upstream `SearchActivity.menu_source_manage`.
                        Button("书源管理") {
                            isSourceManagerPresented = true
                        }
                        // Upstream `SearchActivity.menu_log`.
                        Button("日志") {
                            isLogPresented = true
                        }
                        // Upstream `SearchActivity.onMenuOpened` — the scope
                        // of the search is a menu of its own that is rebuilt
                        // every time it is opened: the scope that is in use is
                        // checked and the groups of the enabled sources can
                        // be picked.
                        Section("搜索范围") {
                            // Upstream `menu_1` — every source.
                            Button {
                                applyScope(.all)
                            } label: {
                                if scope.isAll {
                                    Label("全部书源", systemImage: "checkmark")
                                } else {
                                    Text("全部书源")
                                }
                            }
                            ForEach(enabledGroups, id: \.self) { group in
                                if scope.groupNames.contains(group) {
                                    // Upstream `menu_group_1` — the group is
                                    // in the scope, picking it removes it.
                                    Button {
                                        applyScope(scope.removing(group))
                                    } label: {
                                        Label(group, systemImage: "checkmark")
                                    }
                                } else {
                                    // Upstream `menu_group_2` — the group is
                                    // not in the scope, picking it replaces
                                    // the scope.
                                    Button {
                                        applyScope(SearchScope(scope: group))
                                    } label: {
                                        Text(group)
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isScopePresented) {
                SearchScopeSheet(
                    model: model,
                    scope: scope,
                    onSelect: { newScope in
                        applyScope(newScope)
                    }
                )
            }
            .sheet(isPresented: $isSourceManagerPresented) {
                SourceManagerView(model: model)
            }
            .sheet(isPresented: $isLogPresented) {
                NavigationStack {
                    AppLogView()
                }
            }
            // Upstream `SearchActivity.searchFinishLiveData` — the dialog has
            // two branches: the precise search is turned off, or the scope is
            // widened to every group.
            .alert("搜索结果为空", isPresented: $isEmptyHintPresented) {
                if isPrecision {
                    Button("关闭精准搜索并重新搜索") {
                        isPrecision = false
                        model.environment.settings.set(false, for: .precisionSearch)
                        startSearch()
                    }
                } else {
                    Button("切换到全部分组") {
                        applyScope(.all)
                    }
                }
                Button("取消", role: .cancel) {}
            } message: {
                if isPrecision {
                    Text("\(scope.display)分组搜索结果为空，是否关闭精准搜索？")
                } else {
                    Text("\(scope.display)分组搜索结果为空，是否切换到全部分组？")
                }
            }
            .onAppear {
                reloadHistory()
                reloadShelfKeys()
                reloadShelfMatches()
                if !keyword.isEmpty {
                    startSearch()
                }
            }
            // Upstream `SearchActivity.onQueryTextChange` — the books of the
            // shelf that match the keyword are shown while the keyword is
            // typed.
            .onChange(of: keyword) { _, _ in
                reloadShelfMatches()
            }
            .onDisappear {
                stop()
            }
        }
    }

    // MARK: - Parts

    private var searchBar: some View {
        HStack(spacing: 8) {
            TextField("书名或作者", text: $keyword)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .onSubmit {
                    startSearch()
                }
            Button("搜索") {
                startSearch()
            }
        }
        .padding(12)
    }

    /// The keywords of the history — upstream `SearchActivity` (the history
    /// row of the search view).
    @ViewBuilder
    private var historyBar: some View {
        if !history.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("搜索历史")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                    // Upstream `SearchActivity` — the history can be cleared.
                    Button("清空") {
                        SearchHistory.clear(store: model.environment.store, settings: model.environment.settings)
                        reloadHistory()
                    }
                    .font(.system(size: 13))
                    .buttonStyle(PlainButtonStyle())
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(history, id: \.word) { item in
                            Button(item.word) {
                                keyword = item.word
                                startSearch()
                            }
                            .font(.system(size: 13))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.gray.opacity(0.12))
                            .buttonStyle(PlainButtonStyle())
                            .contextMenu {
                                Button("删除") {
                                    SearchHistory.delete(item.word, settings: model.environment.settings)
                                    reloadHistory()
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    /// The books of the shelf that match the keyword — upstream
    /// `SearchActivity.upHistory` (`rvBookshelfSearch` + `tvBookShow`).
    ///
    /// The books are shown as chips; tapping one opens the detail page.
    @ViewBuilder
    private var shelfBar: some View {
        if !shelfMatches.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("书架中的书")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelfMatches, id: \.bookUrl) { book in
                            NavigationLink {
                                BookDetailView(model: model, book: book)
                            } label: {
                                Text(book.name)
                                    .font(.system(size: 13))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.12))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if isLoading && results.isEmpty {
            ProgressView("搜索中")
        } else if results.isEmpty {
            EmptyState(text: "没有结果")
        } else {
            List {
                ForEach(results, id: \.bookUrl) { book in
                    NavigationLink {
                        BookDetailView(model: model, book: book.toBook())
                    } label: {
                        resultRow(book)
                    }
                }
                // Upstream `SearchActivity.scrollToBottom` — the next page is
                // loaded when the list reaches its end.
                if hasMore {
                    loadMoreRow
                }
            }
            .listStyle(PlainListStyle())
        }
    }

    /// The row that loads the next page of the results.
    ///
    /// Upstream `SearchActivity.scrollToBottom` loads the next page when the
    /// list reaches its end; the port offers the same as a button — like
    /// `DiscoverView` does.
    private var loadMoreRow: some View {
        HStack {
            Spacer(minLength: 0)
            if isLoading {
                ProgressView()
                    .padding(.trailing, 6)
                Text("加载中")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                Button("加载更多") {
                    loadMore()
                }
                .font(.system(size: 13))
                .buttonStyle(PlainButtonStyle())
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    /// A result of the search — upstream `SearchAdapter`.
    private func resultRow(_ book: SearchBook) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Upstream `SearchAdapter.ivCover`.
            BookCoverView(book: book.toBook(), width: 48, height: 66)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(book.name)
                        .font(.system(size: 16))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    // Upstream `SearchAdapter.isInBookShelf` — the marker of the
                    // books that are already on the shelf.
                    if isInShelf(book) {
                        Text("已在书架")
                            .font(.system(size: 11))
                            .foregroundColor(.accentColor)
                    }
                    // Upstream `SearchAdapter.bvOriginCount` — the number of
                    // the sources that found the book.
                    if book.origins.count > 1 {
                        Text("\(book.origins.count)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(8)
                    }
                }
                Text("作者：\(book.author)")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                // Upstream `SearchAdapter.upLasted` — the latest chapter.
                if let last = book.latestChapterTitle, !last.isEmpty {
                    Text("最新：\(last)")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if let intro = book.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                // Upstream `SearchAdapter.upKind` — the kinds of the book.
                if !book.kindList.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(book.kindList, id: \.self) { kind in
                            Text(kind)
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.gray.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }
                }
                if !book.originName.isEmpty {
                    Text(book.originName)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - The actions

    /// Starts the search — upstream `SearchViewModel.search`.
    private func startSearch() {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        stop()
        // Upstream `SearchActivity.onQueryTextSubmit` — the keyword is saved in
        // the history before the search starts.
        SearchHistory.save(key, store: model.environment.store, settings: model.environment.settings)
        reloadHistory()
        reloadShelfKeys()
        model.environment.settings.set(isPrecision, for: .precisionSearch)
        page = 1
        results = []
        isLoading = true
        let sources = scope.sources(from: model.sources)
        let precision = isPrecision
        searchTask = Task {
            let found = await model.environment.search(
                sources: sources,
                keyword: key,
                precision: precision,
                page: page
            )
            guard !Task.isCancelled else { return }
            results = found
            hasMore = !found.isEmpty
            isLoading = false
            // Upstream `SearchActivity.searchFinishLiveData` — the dialog is
            // shown when the results are empty and the scope is not every
            // source.
            if found.isEmpty && !scope.isAll {
                isEmptyHintPresented = true
            }
        }
    }

    /// Searches the next page — upstream `SearchModel.search` with the same
    /// key (the page is incremented).
    private func loadMore() {
        guard hasMore, !isLoading else { return }
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        page += 1
        isLoading = true
        let sources = scope.sources(from: model.sources)
        let precision = isPrecision
        searchTask = Task {
            let found = await model.environment.search(
                sources: sources,
                keyword: key,
                precision: precision,
                page: page
            )
            guard !Task.isCancelled else { return }
            results.append(contentsOf: found)
            hasMore = !found.isEmpty
            isLoading = false
        }
    }

    /// Stops the search — upstream `SearchViewModel.stop`.
    private func stop() {
        searchTask?.cancel()
        searchTask = nil
        isLoading = false
    }

    /// Whether the book is on the shelf — upstream
    /// `SearchViewModel.isInBookShelf`.
    private func isInShelf(_ book: SearchBook) -> Bool {
        let key = book.author.isEmpty ? book.name : "\(book.name)-\(book.author)"
        return shelfKeys.contains(key) || shelfKeys.contains(book.bookUrl)
    }

    private func reloadHistory() {
        history = SearchHistory.keywords(
            store: model.environment.store,
            settings: model.environment.settings
        )
    }

    /// Applies a new scope — upstream `SearchActivity.onCompatOptionsItemSelected`
    /// and `SearchActivity.initData`: the scope is saved and the query is
    /// re-submitted.
    private func applyScope(_ newScope: SearchScope) {
        scope = newScope
        model.environment.settings.setSearchScope(newScope)
        if !keyword.isEmpty {
            startSearch()
        }
    }

    /// The groups of the enabled sources — upstream
    /// `BookSourceDao.flowEnabledGroups`.
    private var enabledGroups: [String] {
        var names: [String] = []
        for source in model.sources where source.enabled {
            for group in source.groups where !names.contains(group) {
                names.append(group)
            }
        }
        return names
    }

    /// The books of the shelf that match the keyword — upstream
    /// `SearchActivity.upHistory` (`BookDao.flowSearch`).
    private func reloadShelfMatches() {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            shelfMatches = []
            return
        }
        shelfMatches = ((try? model.environment.bookshelf().search(key)) ?? []).prefix(20).map { $0 }
    }

    private func reloadShelfKeys() {
        shelfKeys = model.shelfBookKeys()
    }
}

/// The scope of the search — upstream `ui/book/search/SearchScopeDialog.kt`.
///
/// The groups of the sources can be chosen (several at a time) or a single
/// source; "全部书源" searches every enabled source.
public struct SearchScopeSheet: View {

    @ObservedObject var model: LegadoAppModel
    /// The current scope.
    @State private var scope: SearchScope
    /// The chosen groups — upstream `SearchScopeDialog.selectGroups`.
    @State private var selectedGroups: Set<String> = []
    /// The chosen source — upstream `SearchScopeDialog.selectSource`.
    @State private var selectedSource: BookSource?
    /// Whether the sources are listed (upstream `rbSource`).
    @State private var isSourceMode = false
    /// The filter of the sources.
    @State private var filter: String = ""
    /// The callback of the upstream `SearchScopeDialog.Callback`.
    let onSelect: (SearchScope) -> Void

    @Environment(\.dismiss) private var dismiss

    public init(model: LegadoAppModel, scope: SearchScope, onSelect: @escaping (SearchScope) -> Void) {
        self.model = model
        self._scope = State(initialValue: scope)
        self.onSelect = onSelect
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("范围", selection: $isSourceMode) {
                    Text("按分组").tag(false)
                    Text("指定书源").tag(true)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(12)
                if isSourceMode {
                    TextField("搜索书源", text: $filter)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal, 12)
                    List(filteredSources, id: \.bookSourceUrl) { source in
                        Button {
                            selectedSource = source
                        } label: {
                            Text(source.bookSourceName)
                                .foregroundColor(
                                    selectedSource?.bookSourceUrl == source.bookSourceUrl
                                        ? .accentColor
                                        : .primary
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .listStyle(PlainListStyle())
                } else {
                    List(groups, id: \.self) { group in
                        Button {
                            if selectedGroups.contains(group) {
                                selectedGroups.remove(group)
                            } else {
                                selectedGroups.insert(group)
                            }
                        } label: {
                            Text(group)
                                .foregroundColor(
                                    selectedGroups.contains(group) ? .accentColor : .primary
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .listStyle(PlainListStyle())
                }
                HStack {
                    // Upstream `SearchScopeDialog.tvAllSource`.
                    Button("全部书源") {
                        onSelect(.all)
                        dismiss()
                    }
                    Spacer(minLength: 0)
                    // Upstream `SearchScopeDialog.tvCancel`.
                    Button("取消") {
                        dismiss()
                    }
                    Spacer(minLength: 0)
                    // Upstream `SearchScopeDialog.tvOk`.
                    Button("确定") {
                        onSelect(selectedScope)
                        dismiss()
                    }
                }
                .padding(12)
            }
            .navigationTitle("搜索范围")
            .onAppear {
                selectedGroups = Set(scope.groupNames)
            }
        }
    }

    /// The scope that the dialog would return.
    private var selectedScope: SearchScope {
        if isSourceMode, let selectedSource {
            return SearchScope(source: selectedSource)
        }
        if selectedGroups.isEmpty {
            return .all
        }
        return SearchScope(scope: selectedGroups.sorted().joined(separator: ","))
    }

    /// The groups of the enabled sources — upstream
    /// `BookSourceDao.allEnabledGroups`.
    private var groups: [String] {
        var names: [String] = []
        for source in model.sources where source.enabled {
            for group in source.groups where !names.contains(group) {
                names.append(group)
            }
        }
        return names.sorted()
    }

    /// The sources of the dialog — upstream `SearchScopeDialog.upBookSource`.
    private var filteredSources: [BookSource] {
        let key = filter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = model.sources.sorted { $0.customOrder < $1.customOrder }
        guard !key.isEmpty else { return all }
        return all.filter { source in
            source.bookSourceName.lowercased().contains(key)
                || source.bookSourceUrl.lowercased().contains(key)
        }
    }
}
