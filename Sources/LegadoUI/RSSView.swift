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
import Foundation

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
    /// The read records — upstream `ui/rss/article/ReadRecordDialog`.
    @State private var isReadRecordPresented = false
    /// The editor of the source — upstream `RssSourceEditActivity`.
    @State private var isSourceEditorPresented = false
    /// The variables of the source — upstream `ui/widget/dialog/VariableDialog`.
    @State private var isVariablePresented = false

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
                // The menu of the article screen — upstream
                // `ui/rss/article/RssSortActivity` (`res/menu/rss_articles`).
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        if let source = selectedSource {
                            if let loginUrl = source.loginUrl, !loginUrl.isEmpty {
                                Button("登录") {
                                    model.presentLogin(for: source)
                                }
                            }
                            Button("刷新排序") {
                                refreshSorts()
                            }
                            Button("源变量") {
                                isVariablePresented = true
                            }
                            Button("编辑源") {
                                isSourceEditorPresented = true
                            }
                            Button("切换布局") {
                                switchLayout()
                            }
                            Button("阅读记录") {
                                isReadRecordPresented = true
                            }
                            Button("清除") {
                                model.clearRssArticles(source: source)
                                articles = []
                            }
                        }
                    } label: {
                        Text("更多")
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
            .sheet(isPresented: $isReadRecordPresented) {
                NavigationStack {
                    RssReadRecordView(model: model)
                }
            }
            .sheet(isPresented: $isSourceEditorPresented) {
                NavigationStack {
                    if let source = selectedSource {
                        RssSourceEditView(
                            model: model,
                            source: source,
                            onSave: { updated in
                                model.saveRssSource(updated)
                                loadSorts(updated)
                            },
                            onClose: {
                                isSourceEditorPresented = false
                            }
                        )
                    }
                }
            }
            .sheet(isPresented: $isVariablePresented) {
                NavigationStack {
                    if let source = selectedSource {
                        VariableEditorView(
                            title: "源变量",
                            comment: "源变量可在js中通过source.getVariable()获取",
                            value: BookSourceVariables.sourceVariables(source.key) ?? "{}"
                        ) { value in
                            saveVariables(value, for: source)
                        }
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
        RssLibrary.sourceGroups(model.rssSources.filter(\.enabled))
    }

    /// The sources of the selected group.
    ///
    /// Upstream `RssSourceDao.flowAll` — the sources whose subscription is
    /// enabled (`RssSource.enabled`).
    private var filteredSources: [RssSource] {
        let enabled = model.rssSources.filter(\.enabled)
        guard let selectedGroup else { return enabled }
        return enabled.filter { RssLibrary.splitGroups($0.sourceGroup).contains(selectedGroup) }
    }

    /// The layout of the articles — upstream `RssSource.articleStyle`
    /// (0 = the list, 1 = the compact row, 2 = the grid).
    private var articleStyle: Int {
        Int(selectedSource?.articleStyle ?? 0)
    }

    @ViewBuilder
    private var articleList: some View {
        if isLoading {
            ProgressView("加载中")
        } else if articles.isEmpty {
            EmptyState(text: "没有文章")
        } else {
            switch articleStyle {
            case 1:
                compactArticleList
            case 2:
                gridArticleList
            default:
                defaultArticleList
            }
        }
    }

    /// The default list — upstream `RssArticlesAdapter`
    /// (`item_rss_article.xml`: the title, the description and the date).
    private var defaultArticleList: some View {
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
                                .foregroundColor(isRead(article) ? .secondary : .primary)
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
            loadMoreSection
        }
        .listStyle(PlainListStyle())
    }

    /// The compact list — upstream `RssArticlesAdapter1`
    /// (`item_rss_article_1.xml`: the image on the left, the title and the
    /// date on the right).
    private var compactArticleList: some View {
        List {
            ForEach(articles, id: \.link) { article in
                HStack(alignment: .top, spacing: 8) {
                    Button {
                        open(article)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            articleImage(article, width: 110, height: 150)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(article.title)
                                    .font(.system(size: 16))
                                    .lineLimit(3)
                                    .foregroundColor(isRead(article) ? .secondary : .primary)
                                if let pubDate = article.pubDate, !pubDate.isEmpty {
                                    Text(pubDate)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                    Button(model.isStarred(article) ? "★" : "☆") {
                        model.toggleStar(article)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .font(.system(size: 18))
                }
            }
            loadMoreSection
        }
        .listStyle(PlainListStyle())
    }

    /// The grid — upstream `RssArticlesAdapter2` (the image on the top, the
    /// title and the date below, two columns).
    private var gridArticleList: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(articles, id: \.link) { article in
                    Button {
                        open(article)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            articleImage(article, width: 0, height: 160)
                            Text(article.title)
                                .font(.system(size: 14))
                                .lineLimit(3)
                                .foregroundColor(isRead(article) ? .secondary : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if let pubDate = article.pubDate, !pubDate.isEmpty {
                                Text(pubDate)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(8)
            loadMoreButton
        }
    }

    /// The image of an article — upstream `ImageLoader.load(context, item.image)`
    /// (the URL is relative to the address of the source).
    @ViewBuilder
    private func articleImage(_ article: RssArticle, width: Double, height: Double) -> some View {
        if let image = article.image, !image.isEmpty,
           let url = URL(string: NetworkUtils.absoluteURL(base: article.origin, image)) {
            AsyncImage(url: url) { phase in
                if case let .success(value) = phase {
                    return AnyView(value.resizable().aspectRatio(contentMode: .fill))
                }
                return AnyView(Color.gray.opacity(0.15))
            }
            .frame(width: width > 0 ? width : nil, height: height)
            .cornerRadius(4)
            .clipped()
        } else {
            Color.gray.opacity(0.15)
                .frame(width: width > 0 ? width : nil, height: height)
                .cornerRadius(4)
        }
    }

    /// Whether an article was read — upstream `RssArticle.read`.
    private func isRead(_ article: RssArticle) -> Bool {
        model.rssReadRecords.contains { $0.record == article.link }
    }

    /// The "load more" row — upstream `RssArticlesFragment` puts a
    /// `LoadMoreView` below the articles.
    private var loadMoreSection: some View {
        Section {
            loadMoreButton
        }
    }

    @ViewBuilder
    private var loadMoreButton: some View {
        if nextURL != nil {
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

    /// Re-reads the sorts of the source — upstream
    /// `RssSortViewModel.clearSortCache` (the upstream caches the sorts of a
    /// JS `sortUrl`, the port evaluates it on demand).
    private func refreshSorts() {
        guard let source = selectedSource else { return }
        loadSorts(source)
        load()
    }

    /// Switches the layout of the articles — upstream
    /// `RssSortViewModel.switchLayout` (0 → 1 → 2 → 0).
    private func switchLayout() {
        guard let source = selectedSource else { return }
        var updated = source
        updated.articleStyle = source.articleStyle < 2 ? source.articleStyle + 1 : 0
        model.saveRssSource(updated)
        selectedSource = updated
    }

    /// Saves the variables of the source — upstream
    /// `RssSortActivity.setVariable`.
    private func saveVariables(_ text: String, for source: RssSource) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let value = try? JSONValue.parse(trimmed),
              let members = value.objectValue else {
            BookSourceVariables.clearSourceVariables(source.key)
            return
        }
        var variables: [String: String] = [:]
        for (name, member) in members {
            variables[name] = member.textValue
        }
        BookSourceVariables.setVariables(variables, for: source.key)
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

// MARK: - The read records

/// The read records of the RSS articles — upstream
/// `ui/rss/article/ReadRecordDialog`.
///
/// The upstream lists the title and the link of every article that was read
/// and offers a "clear" button that asks for a confirmation.
public struct RssReadRecordView: View {

    @ObservedObject var model: LegadoAppModel

    /// Whether the confirmation of the clear is shown.
    @State private var showsClearConfirmation = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.rssReadRecords.isEmpty {
                EmptyState(text: "没有阅读记录")
            } else {
                List(model.rssReadRecords, id: \.record) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title ?? record.record)
                            .font(.system(size: 16))
                        Text(record.record)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("阅读记录")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Upstream `menu_clear`.
                Button("清除") {
                    showsClearConfirmation = true
                }
                .disabled(model.rssReadRecords.isEmpty)
            }
        }
        .alert("清除", isPresented: $showsClearConfirmation) {
            Button("取消", role: .cancel) {}
            Button("确定", role: .destructive) {
                model.deleteAllRssReadRecords()
            }
        } message: {
            Text("确定要删除\n\(model.rssReadRecords.count) 条阅读记录吗？")
        }
    }
}
