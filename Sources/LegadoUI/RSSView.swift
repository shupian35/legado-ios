//
//  RSSView.swift
//  LegadoUI
//
//  The RSS tab — upstream `ui/rss/`.
//
//  It lists the RSS sources and the articles of the selected source.
//
//  Upstream:
//  - `ui/rss/article/RssArticlesFragment.kt` — the articles of a source and
//    the "load more" button (`LoadMoreView`) that asks the view model for the
//    next page,
//  - `ui/rss/article/RssArticlesViewModel.kt` — the page number and the URL
//    of the next page,
//  - `ui/rss/read/ReadRssActivity.kt` — the reader of an article,
//  - `ui/rss/favorites/RssFavoritesActivity.kt` — the favourites.
//
//  See `AppModel.swift` for the state.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import LegadoCore

/// The RSS tab.
public struct RSSView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var selectedSource: RssSource?
    @State private var articles: [RssArticle] = []
    @State private var isLoading = false
    /// Whether the next page is loaded — upstream
    /// `RssArticlesViewModel.loadMore`.
    @State private var isLoadingMore = false
    /// The URL of the next page — upstream `RssArticlesViewModel.nextPageUrl`.
    ///
    /// Upstream `Rss.getArticlesAwait` returns the articles **and** the URL of
    /// the next page; the port keeps both in `RssArticlePage`.
    @State private var nextURL: String?
    /// The number of the page that is shown — upstream
    /// `RssArticlesViewModel.page`.
    @State private var page: Int = 1
    /// The opened article — upstream `ReadRssActivity`.
    @State private var openedArticle: RssArticleItem?
    @State private var selectedGroup: String?
    @State private var isFavoritesPresented = false
    @State private var isSourceManagerPresented = false
    /// The rule subscriptions — upstream `ui/rss/subscription/RuleSubActivity`.
    @State private var isRuleSubPresented = false
    /// The sorts of the selected source — upstream `ui/rss/article/RssSortActivity`.
    @State private var sorts: [RssSort] = []
    /// The index of the selected sort.
    @State private var selectedSortIndex: Int = 0

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sourceList
                articleList
            }
            .navigationTitle("订阅")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新") {
                        load()
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("收藏夹") {
                        isFavoritesPresented = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button("订阅源") {
                        isSourceManagerPresented = true
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    // Upstream `RssFragment` → `RuleSubActivity`.
                    Button("规则订阅") {
                        isRuleSubPresented = true
                    }
                }
            }
            .sheet(isPresented: $isRuleSubPresented) {
                NavigationStack {
                    RuleSubView(model: model)
                }
            }
            .sheet(isPresented: $isSourceManagerPresented) {
                NavigationStack {
                    RssSourceManageView(model: model)
                }
            }
            .sheet(isPresented: $isFavoritesPresented) {
                NavigationStack {
                    RssFavoritesView(model: model)
                }
            }
            .sheet(item: $openedArticle) { item in
                RssArticleReaderView(
                    model: model,
                    article: item.article,
                    source: source(of: item.article)
                )
            }
            .onAppear {
                model.reloadRSS()
                if selectedSource == nil {
                    selectedSource = model.rssSources.first
                }
                if let source = selectedSource {
                    loadSorts(source)
                }
                load()
            }
        }
    }

    // MARK: - Parts

    private var sourceList: some View {
        VStack(spacing: 0) {
            if !groups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(groups, id: \.name) { group in
                            Button {
                                selectedGroup = group.name
                                selectedSource = nil
                                load()
                            } label: {
                                Text("\(group.name) (\(group.count))")
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        selectedGroup == group.name
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.gray.opacity(0.12)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filteredSources, id: \.sourceUrl) { source in
                        Button {
                            selectedSource = source
                            articles = []
                            loadSorts(source)
                            load()
                        } label: {
                            Text(source.sourceName)
                                .font(.system(size: 14))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    selectedSource?.sourceUrl == source.sourceUrl
                                        ? Color.accentColor.opacity(0.2)
                                        : Color.gray.opacity(0.12)
                                )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            // The sorts of the source — one tab per sort.
            if sorts.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(sorts.indices, id: \.self) { index in
                            Button {
                                selectedSortIndex = index
                                load()
                            } label: {
                                Text(sorts[index].name.isEmpty ? "默认" : sorts[index].name)
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        selectedSortIndex == index
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.gray.opacity(0.12)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                }
            }
        }
    }

    /// The groups of the RSS sources — upstream `RssSourceViewModel`.
    private var groups: [RssLibrary.Group] {
        RssLibrary.sourceGroups(model.rssSources)
    }

    /// The sources of the selected group.
    private var filteredSources: [RssSource] {
        guard let selectedGroup else { return model.rssSources }
        return model.rssSources.filter { RssLibrary.splitGroups($0.sourceGroup).contains(selectedGroup) }
    }

    @ViewBuilder
    private var articleList: some View {
        if isLoading {
            ProgressView("加载中")
        } else if articles.isEmpty {
            EmptyState(text: "没有文章")
        } else {
            List {
                ForEach(articles, id: \.link) { article in
                    HStack(alignment: .top, spacing: 8) {
                        Button {
                            open(article)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(article.title)
                                    .font(.system(size: 16))
                                    .lineLimit(2)
                                if let description = article.description, !description.isEmpty {
                                    Text(description)
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                }
                                if let pubDate = article.pubDate, !pubDate.isEmpty {
                                    Text(pubDate)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(PlainButtonStyle())
                        Button(model.isStarred(article) ? "★" : "☆") {
                            model.toggleStar(article)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .font(.system(size: 18))
                    }
                }
                // The "load more" button — upstream `RssArticlesFragment` puts a
                // `LoadMoreView` below the articles.
                if nextURL != nil {
                    Section {
                        Button {
                            loadMore()
                        } label: {
                            HStack {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView("加载中")
                                } else {
                                    Text("加载更多")
                                }
                                Spacer()
                            }
                        }
                        .disabled(isLoadingMore)
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
    }

    // MARK: - Actions

    /// Loads the first page of the articles — upstream
    /// `RssArticlesViewModel.loadArticles`.
    private func load() {
        guard let source = selectedSource else { return }
        isLoading = true
        page = 1
        Task {
            do {
                let result = try await loadPage(source: source, page: 1, url: nil)
                articles = result.articles
                nextURL = result.nextUrl
                page = 1
            } catch {
                model.errorMessage = error.localizedDescription
                articles = []
                nextURL = nil
            }
            isLoading = false
        }
    }

    /// Loads the next page of the articles — upstream
    /// `RssArticlesViewModel.loadMore`.
    ///
    /// The upstream asks the source for the page with the URL the previous
    /// page returned.
    private func loadMore() {
        guard let source = selectedSource, let url = nextURL else { return }
        isLoadingMore = true
        let next = page + 1
        Task {
            do {
                let result = try await loadPage(source: source, page: next, url: url)
                for article in result.articles where !articles.contains(where: { $0.link == article.link }) {
                    articles.append(article)
                }
                nextURL = result.nextUrl
                page = next
            } catch {
                model.errorMessage = error.localizedDescription
            }
            isLoadingMore = false
        }
    }

    /// Loads one page of the articles.
    private func loadPage(source: RssSource, page: Int, url: String?) async throws -> RssArticlePage {
        if sorts.isEmpty {
            return try await model.environment.rssArticles(source: source, sort: nil, page: page, url: url)
        }
        let sort = sorts[min(selectedSortIndex, sorts.count - 1)]
        return try await model.environment.rssArticles(source: source, sort: sort, page: page, url: url)
    }

    /// Reads the sorts of the source — upstream `RssSource.sortUrls()`.
    private func loadSorts(_ source: RssSource) {
        sorts = RssSortUrls.parse(
            sortUrl: source.sortUrl,
            sourceUrl: source.sourceUrl,
            scriptEngine: model.environment.scriptEngine
        )
        selectedSortIndex = 0
    }

    /// Opens the reader of an article — upstream `ReadRssActivity`.
    private func open(_ article: RssArticle) {
        model.markRead(article)
        openedArticle = RssArticleItem(article: article)
    }

    /// The source of an article — the `origin` of an article is the URL of
    /// its source.
    private func source(of article: RssArticle) -> RssSource {
        model.rssSources.first { $0.sourceUrl == article.origin }
            ?? RssSource(sourceUrl: article.origin, sourceName: article.origin)
    }
}

// MARK: - The article

/// An article that is presented in a sheet.
///
/// The upstream opens the reader with an intent (`ReadRssActivity`); the port
/// presents the article in a sheet, so it needs an identity — the link of the
/// article is its key.
struct RssArticleItem: Identifiable {
    let article: RssArticle

    var id: String { article.link }
}

// MARK: - The favourites
/// The favourites of the RSS articles — upstream
/// `ui/rss/favorites/RssFavoritesActivity`.
///
/// The upstream shows one tab per group of the favourites, the articles can
/// be read and deleted and the groups (or all of them) can be deleted.
public struct RssFavoritesView: View {

    @ObservedObject var model: LegadoAppModel

    /// The groups of the favourites — upstream `rssStarDao.flowGroups()`.
    @State private var groups: [RssLibrary.Group] = []
    /// The selected group — upstream `RssFavoritesFragment(group)`.
    @State private var selectedGroup: String = RssLibrary.defaultGroup
    /// The article that is read.
    @State private var openedArticle: RssArticleItem?
    /// The favourite that is deleted — upstream `RssFavoritesFragment.delStar`.
    @State private var deletedStar: RssStar?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            if !groups.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(groups, id: \.name) { group in
                            Button {
                                selectedGroup = group.name
                            } label: {
                                Text("\(group.name) (\(group.count))")
                                    .font(.system(size: 12))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        selectedGroup == group.name
                                            ? Color.accentColor.opacity(0.2)
                                            : Color.gray.opacity(0.12)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
            }
            if stars.isEmpty {
                EmptyState(text: "没有收藏")
            } else {
                List(stars, id: \.link) { star in
                    Button {
                        openedArticle = RssArticleItem(article: star.toRssArticle())
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(star.title)
                                .font(.system(size: 16))
                            if let pubDate = star.pubDate, !pubDate.isEmpty {
                                Text(pubDate)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PlainButtonStyle())
                    // Upstream `RssFavoritesFragment.delStar`.
                    .onLongPressGesture {
                        deletedStar = star
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("收藏夹")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Upstream `menu_del_group`.
                Button("删除本组") {
                    deleteGroup()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                // Upstream `menu_del_all`.
                Button("全部删除") {
                    deleteAll()
                }
            }
        }
        .sheet(item: $openedArticle) { item in
            RssArticleReaderView(
                model: model,
                article: item.article,
                source: source(of: item.article)
            )
        }
        .alert("删除收藏", isPresented: Binding(get: { deletedStar != nil }, set: { if !$0 { deletedStar = nil } })) {
            Button("取消", role: .cancel) {
                deletedStar = nil
            }
            Button("删除", role: .destructive) {
                if let star = deletedStar {
                    model.toggleStar(star.toRssArticle())
                }
                deletedStar = nil
                reload()
            }
        } message: {
            Text("确定删除该收藏吗？")
        }
        .onAppear {
            reload()
        }
    }

    /// The favourites of the selected group — upstream
    /// `rssStarDao.flowByGroup(group)`.
    private var stars: [RssStar] {
        model.rssStars.filter {
            ($0.group.isEmpty ? RssLibrary.defaultGroup : $0.group) == selectedGroup
        }
    }

    private func reload() {
        groups = RssLibrary.starGroups(model.rssStars)
        if !groups.contains(where: { $0.name == selectedGroup }), let first = groups.first {
            selectedGroup = first.name
        }
    }

    /// Deletes the favourites of the group — upstream
    /// `rssStarDao.deleteByGroup(group)`.
    private func deleteGroup() {
        for star in stars {
            model.toggleStar(star.toRssArticle())
        }
        reload()
    }

    /// Deletes every favourite — upstream `rssStarDao.deleteAll()`.
    private func deleteAll() {
        for star in model.rssStars {
            model.toggleStar(star.toRssArticle())
        }
        reload()
    }

    /// The source of an article.
    private func source(of article: RssArticle) -> RssSource {
        model.rssSources.first { $0.sourceUrl == article.origin }
            ?? RssSource(sourceUrl: article.origin, sourceName: article.origin)
    }
}
