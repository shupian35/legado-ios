//
//  DiscoverView.swift
//  LegadoUI
//
//  The discovery tab — upstream `ui/main/explore/`.
//
//  It lists the book sources that have an exploration rule, their explore
//  categories and the books of the selected category. A long press on a
//  source opens the menu of the upstream `res/menu/explore_item.xml`
//  (编辑 / 置顶 / 登录 / 搜索 / 刷新 / 删除).
//
//  See `AppModel.swift` for the state.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import LegadoCore

/// The discovery tab — upstream `ui/main/explore/ExploreFragment`.
public struct DiscoverView: View {

    @ObservedObject var model: LegadoAppModel

    /// The source whose categories are shown.
    @State private var selectedSource: BookSource?
    /// The categories of the selected source — upstream `ExploreKind`.
    @State private var categories: [ExploreCategory] = []
    /// The selected category — upstream `ExploreShowViewModel.exploreUrl`.
    @State private var selectedCategory: ExploreCategory?
    /// The books of the selected category.
    @State private var results: [SearchBook] = []
    @State private var isLoading = false
    /// The search screen — upstream `ui/book/search/SearchActivity`.
    @State private var isSearchPresented = false
    /// The keyword of the search.
    @State private var keyword: String = ""
    /// The filter of the sources — upstream `ExploreFragment` has no filter,
    /// but the sources can be many; the port adds one.
    @State private var sourceFilter: String = ""
    /// The group of the sources — upstream `ExploreFragment` groups the
    /// sources by their `bookSourceGroup`.
    @State private var groupFilter: String = ""
    /// The page of the explore — upstream `ExploreShowViewModel.page`.
    @State private var page = 1
    /// Whether the explore has more pages.
    @State private var hasMore = false
    /// The keys of the books on the shelf — upstream
    /// `ExploreShowViewModel.isInBookShelf`.
    @State private var shelfKeys: Set<String> = []
    /// The source editor — upstream `menu_edit`.
    @State private var editingSource: BookSource?
    /// Whether the source editor is shown.
    @State private var isEditorPresented = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sourceFilterBar
                sourceList
                categoryList
                resultList
            }
            .navigationTitle("发现")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("搜索") {
                        isSearchPresented = true
                    }
                }
            }
            .sheet(isPresented: $isSearchPresented) {
                SearchView(model: model, keyword: keyword, source: selectedSource)
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
            .onAppear {
                model.reloadSources()
                reloadShelfKeys()
                if selectedSource == nil {
                    selectedSource = filteredSources.first
                    loadCategories()
                }
            }
            // A search that a link asked for — upstream
            // `SharedReceiverActivity.dispose(text)` opens the search screen.
            .onChange(of: model.pendingSearchKeyword) { pending in
                guard let pending, !pending.isEmpty else { return }
                keyword = pending
                model.pendingSearchKeyword = nil
                isSearchPresented = true
            }
        }
    }

    // MARK: - Parts

    /// The filter of the sources and the groups.
    private var sourceFilterBar: some View {
        VStack(spacing: 6) {
            TextField("搜索书源", text: $sourceFilter)
                .textFieldStyle(RoundedBorderTextFieldStyle())
            if !allGroups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        groupChip(name: "", title: "全部")
                        ForEach(allGroups, id: \.self) { group in
                            groupChip(name: group, title: group)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func groupChip(name: String, title: String) -> some View {
        Button {
            groupFilter = name
        } label: {
            Text(title)
                .font(.system(size: 13))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    groupFilter == name
                        ? Color.accentColor.opacity(0.2)
                        : Color.gray.opacity(0.12)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// The sources — upstream `ExploreFragment` shows the sources that have
    /// an exploration rule.
    private var sourceList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filteredSources, id: \.bookSourceUrl) { source in
                    Button {
                        selectedSource = source
                        loadCategories()
                        results = []
                        page = 1
                        hasMore = false
                    } label: {
                        Text(source.bookSourceName)
                            .font(.system(size: 14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedSource?.bookSourceUrl == source.bookSourceUrl
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.gray.opacity(0.12)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    // Upstream `res/menu/explore_item.xml` — the menu of a
                    // source.
                    .contextMenu {
                        Button("编辑") {
                            editingSource = source
                            isEditorPresented = true
                        }
                        Button("置顶") {
                            model.topSources([source])
                        }
                        if !(source.loginUrl ?? "").isEmpty {
                            Button("登录") {
                                model.presentLogin(for: source)
                            }
                        }
                        Button("搜索") {
                            keyword = ""
                            isSearchPresented = true
                        }
                        Button("刷新") {
                            // Upstream `menu_refresh` — the categories are
                            // read again.
                            loadCategories()
                        }
                        Button("删除") {
                            model.deleteSource(source)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var categoryList: some View {
        if !categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { category in
                        Button {
                            load(category: category)
                        } label: {
                            Text(category.name)
                                .font(.system(size: 13))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.12))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if isLoading && results.isEmpty {
            ProgressView("加载中")
        } else if results.isEmpty {
            EmptyState(text: "没有内容")
        } else {
            ScrollViewReader { proxy in
                List {
                    ForEach(results, id: \.bookUrl) { book in
                        NavigationLink {
                            // Upstream `ExploreShowActivity` opens the detail page of
                            // the book.
                            BookDetailView(model: model, book: book.toBook())
                        } label: {
                            resultRow(book)
                        }
                        .id(book.bookUrl)
                    }
                    if hasMore {
                        HStack {
                            Spacer(minLength: 0)
                            Button("加载更多") {
                                loadMore()
                            }
                            .buttonStyle(PlainButtonStyle())
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 8)
                    }
                }
                .listStyle(PlainListStyle())
                // The second tap on the discovery tab collapses the expanded
                // source of upstream `ExploreFragment.compressExplore()`; the
                // port has no expanded source, so the list of the results is
                // scrolled to its top (the upstream does the same when no
                // source is expanded).
                .onChange(of: model.collapseExploreToken) { _ in
                    guard let first = results.first else { return }
                    proxy.scrollTo(first.bookUrl, anchor: .top)
                }
            }
        }
    }

    /// A result of the explore — upstream `ExploreShowAdapter`.
    private func resultRow(_ book: SearchBook) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(book.name)
                    .font(.system(size: 16))
                    .lineLimit(1)
                Spacer(minLength: 0)
                // Upstream `ExploreShowViewModel.isInBookShelf`.
                if isInShelf(book) {
                    Text("已在书架")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                }
            }
            Text(book.author)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
            if let intro = book.intro, !intro.isEmpty {
                Text(intro)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
    }

    // MARK: - The data

    /// The sources of the list — the enabled ones that have an exploration
    /// rule, filtered by the search text and the group.
    ///
    /// Upstream `BookSourceDao.flowExplore` — the sources with
    /// `enabledExplore = 1` and an exploration rule; the search matches the
    /// name AND the group.
    private var filteredSources: [BookSource] {
        let key = sourceFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let all = model.sources
            .filter { $0.enabledExplore && !($0.exploreUrl ?? "").isEmpty }
            .sorted { $0.customOrder < $1.customOrder }
        let grouped = groupFilter.isEmpty
            ? all
            : all.filter { $0.groups.contains(groupFilter) }
        guard !key.isEmpty else { return grouped }
        return grouped.filter { source in
            source.bookSourceName.lowercased().contains(key)
                || source.bookSourceUrl.lowercased().contains(key)
                || source.groups.contains { $0.lowercased().contains(key) }
        }
    }

    /// The groups of the sources — upstream
    /// `BookSourceDao.flowExploreGroupsUnProcessed`: the groups of the
    /// sources whose exploration is allowed and that have an exploration
    /// rule.
    private var allGroups: [String] {
        var names: [String] = []
        for source in model.sources where source.enabledExplore && !(source.exploreUrl ?? "").isEmpty {
            for group in source.groups where !group.isEmpty && !names.contains(group) {
                names.append(group)
            }
        }
        return names.sorted()
    }

    /// Whether the book is on the shelf — upstream
    /// `ExploreShowViewModel.isInBookShelf`.
    private func isInShelf(_ book: SearchBook) -> Bool {
        let key = book.author.isEmpty ? book.name : "\(book.name)-\(book.author)"
        return shelfKeys.contains(key) || shelfKeys.contains(book.bookUrl)
    }

    private func reloadShelfKeys() {
        shelfKeys = model.shelfBookKeys()
    }

    // MARK: - Actions

    private func loadCategories() {
        categories = selectedSource.map { model.environment.exploreCategories(source: $0) } ?? []
    }

    /// Loads a category — upstream `ExploreShowViewModel.explore`.
    private func load(category: ExploreCategory) {
        guard let source = selectedSource else { return }
        isLoading = true
        page = 1
        selectedCategory = category
        Task {
            do {
                results = try await model.environment.explore(source: source, url: category.url)
                page = 2
                hasMore = !results.isEmpty
            } catch {
                model.errorMessage = error.localizedDescription
                results = []
                hasMore = false
            }
            isLoading = false
        }
    }

    /// Loads the next page — upstream `ExploreShowViewModel.explore` (the page
    /// is incremented after every page).
    private func loadMore() {
        guard !isLoading, hasMore, let source = selectedSource, let category = selectedCategory else { return }
        isLoading = true
        let current = page
        Task {
            do {
                let found = try await model.environment.explore(
                    source: source,
                    url: category.url,
                    page: current
                )
                results.append(contentsOf: found)
                page = current + 1
                hasMore = !found.isEmpty
            } catch {
                model.errorMessage = error.localizedDescription
                hasMore = false
            }
            isLoading = false
        }
    }
}
