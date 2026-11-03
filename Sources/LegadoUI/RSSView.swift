//
//  RSSView.swift
//  LegadoUI
//
//  The RSS tab — upstream `ui/rss/`.
//
//  It lists the RSS sources and the articles of the selected source.
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
    @State private var content: String?
    @State private var contentTitle: String = ""
    /// The address of the opened article — upstream `ReadRssActivity` shows
    /// the original page in a web view.
    @State private var contentURL: String = ""
    @State private var isBrowserPresented = false
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
                    RssSourceManagerView(model: model)
                }
            }
            .sheet(isPresented: $isFavoritesPresented) {
                NavigationStack {
                    List(model.rssStars, id: \.link) { star in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(star.title)
                                .font(.system(size: 16))
                            Text(star.group.isEmpty ? RssLibrary.defaultGroup : star.group)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                    .listStyle(PlainListStyle())
                    .navigationTitle("收藏夹")
                }
            }
            .sheet(isPresented: Binding(get: { content != nil }, set: { if !$0 { content = nil } })) {
                if let content {
                    ScrollView {
                        Text(contentTitle)
                            .font(.system(size: 18))
                            .padding(.bottom, 8)
                        Text(content)
                            .font(.system(size: 15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    .navigationTitle("文章")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("原文") {
                                isBrowserPresented = true
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $isBrowserPresented) {
                NavigationStack {
                    InAppBrowserView(url: contentURL)
                }
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
            List(articles, id: \.link) { article in
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
            .listStyle(PlainListStyle())
        }
    }

    // MARK: - Actions

    private func load() {
        guard let source = selectedSource else { return }
        isLoading = true
        Task {
            do {
                if sorts.isEmpty {
                    articles = try await model.environment.rssArticles(source: source)
                } else {
                    let sort = sorts[min(selectedSortIndex, sorts.count - 1)]
                    articles = try await model.environment.rssArticles(source: source, sort: sort)
                }
            } catch {
                model.errorMessage = error.localizedDescription
                articles = []
            }
            isLoading = false
        }
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

    private func open(_ article: RssArticle) {
        guard let source = selectedSource else { return }
        contentTitle = article.title
        contentURL = article.link
        model.markRead(article)
        Task {
            do {
                content = try await model.environment.rssContent(article: article, source: source)
            } catch {
                model.errorMessage = error.localizedDescription
                content = article.description ?? ""
            }
        }
    }
}
