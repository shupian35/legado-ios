//
//  RssArticleReaderView.swift
//  LegadoUI
//
//  The reader of an RSS article.
//
//  Upstream `ui/rss/read/ReadRssActivity.kt` renders the article in a
//  web view: the content of the article is wrapped in a style, the
//  JavaScript of the source may run, the requests of the page are filtered
//  with the white list and the black list of the source and the script of
//  the source may intercept the links.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

#if canImport(WebKit)
import WebKit
#endif

#if canImport(AVFoundation)
import AVFoundation
#endif

import Foundation
import LegadoCore

// MARK: - The reader

/// The reader of an RSS article — upstream `ReadRssActivity`.
public struct RssArticleReaderView: View {

    /// The article.
    public let article: RssArticle
    /// The source of the article.
    public let source: RssSource

    /// The model — the star of the article is toggled with it.
    @ObservedObject var model: LegadoAppModel

    /// The content of the article — upstream `contentLiveData`.
    @State private var content: String?
    /// Whether the content is loaded.
    @State private var isLoading = false
    /// Whether the original page is shown in the browser — upstream
    /// `menu_browser_open`.
    @State private var isBrowserPresented = false
    /// Whether the editor of the favourite is shown — upstream
    /// `ui/rss/favorites/RssFavoritesDialog.kt`.
    @State private var isFavoritePresented = false
    /// Whether the share sheet is shown — upstream `menu_share_it`.
    @State private var isSharePresented = false
    /// Whether the article is being read aloud — upstream `menu_aloud`.
    @State private var isAloud = false

    /// The read aloud of the article — upstream `viewModel.tts`.
    ///
    /// The upstream reads the visible text of the web view; the port reads
    /// the text of the article.
    private let aloud: ReadAloudController = {
        #if canImport(AVFoundation)
        return ReadAloudController(synthesizer: AVSpeechSynthesizerEngine())
        #else
        return ReadAloudController()
        #endif
    }()

    public init(model: LegadoAppModel, article: RssArticle, source: RssSource) {
        self.model = model
        self.article = article
        self.source = source
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("加载中")
                }
                RssArticleWebView(
                    article: article,
                    source: source,
                    content: content,
                    onOpenLink: { link in openLink(link) }
                )
            }
            .navigationTitle(article.title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    // Upstream `menu_rss_star` — the article becomes a
                    // favourite and its title and group are edited.
                    Button(model.isStarred(article) ? "★" : "☆") {
                        addFavorite()
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    // Upstream `res/menu/rss_read.xml`.
                    Menu("更多") {
                        Button("刷新") {
                            Task { await refresh() }
                        }
                        Button("分享") {
                            isSharePresented = true
                        }
                        Button(isAloud ? "停止朗读" : "朗读") {
                            toggleAloud()
                        }
                        if let loginUrl = source.loginUrl, !loginUrl.isEmpty {
                            Button("登录") {
                                model.presentLogin(for: source)
                            }
                        }
                        Button("原文") {
                            isBrowserPresented = true
                        }
                    }
                }
            }
            .sheet(isPresented: $isBrowserPresented) {
                NavigationStack {
                    InAppBrowserView(url: article.link)
                }
            }
            .sheet(isPresented: $isSharePresented) {
                ShareSheet(items: [article.link])
            }
            .sheet(isPresented: $isFavoritePresented) {
                NavigationStack {
                    if let star = model.rssStars.first(where: { $0.link == article.link }) {
                        RssFavoriteEditView(
                            star: star,
                            groups: RssLibrary.starGroups(model.rssStars).map(\.name),
                            onSave: { updated in
                                model.updateStar(updated)
                            },
                            onDelete: {
                                if let current = model.rssStars.first(where: { $0.link == article.link }) {
                                    model.deleteStar(current)
                                }
                            }
                        )
                    }
                }
            }
            .task {
                await load()
            }
        }
    }

    /// Loads the content of the article — upstream
    /// `ReadRssViewModel.initData`.
    ///
    /// The description of the article is used when it is not empty, else the
    /// content is fetched with the `ruleContent` rule of the source and —
    /// when the source has no such rule — the address of the article is
    /// shown in the web view.
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        if let description = article.description, !description.isEmpty {
            content = description
            return
        }
        guard let rule = source.ruleContent, !rule.isEmpty else {
            content = nil
            return
        }
        do {
            content = try await model.environment.rssContent(article: article, source: source)
        } catch {
            model.errorMessage = error.localizedDescription
            content = article.description ?? ""
        }
    }

    /// Refreshes the content of the article — upstream `viewModel.refresh`.
    private func refresh() async {
        await load()
    }

    /// Reads the article aloud — upstream `readAloud()`.
    ///
    /// The upstream reads the visible text of the web view; the port reads
    /// the text of the article.
    private func toggleAloud() {
        if isAloud {
            aloud.stop()
            isAloud = false
            return
        }
        let text = TextFormat.format(content ?? article.description ?? "")
        let paragraphs = ReadAloudSplitter.paragraphs(in: text)
        guard !paragraphs.isEmpty else {
            model.errorMessage = "没有可朗读的内容"
            return
        }
        aloud.onStateChange { state in
            DispatchQueue.main.async {
                isAloud = state == .playing
            }
        }
        aloud.play(paragraphs: paragraphs)
        isAloud = true
    }

    /// Adds the article to the favourites and opens the editor of the
    /// favourite — upstream `menu_rss_star` (`viewModel.addFavorite()` and
    /// then `showDialogFragment(RssFavoritesDialog(it))`).
    private func addFavorite() {
        if !model.isStarred(article) {
            model.addStar(article)
        }
        isFavoritePresented = true
    }

    /// Opens a link of the article — upstream
    /// `ReadRssActivity.shouldOverrideUrlLoading`.
    private func openLink(_ link: String) {
        guard let url = URL(string: link) else { return }
        switch url.scheme?.lowercased() {
        case "legado", "yuedu":
            // Upstream starts the online import.
            if let request = try? DeepLink.parse(url) {
                Task {
                    _ = try? await DeepLink.importData(
                        from: request,
                        httpClient: model.environment.httpClient,
                        store: model.environment.store
                    )
                    model.reloadSources()
                    model.reloadRSS()
                }
            }
        default:
            // Upstream opens the url in another application.
            isBrowserPresented = true
        }
    }
}

// MARK: - The web view of the article

/// The web view of an article — upstream
/// `ReadRssActivity.CustomWebViewClient`.
struct RssArticleWebView: View {

    let article: RssArticle
    let source: RssSource
    /// The content of the article — `nil` loads the address of the article
    /// (upstream `ReadRssViewModel.loadUrl`).
    let content: String?
    /// The action of a link that may not be opened in the page.
    var onOpenLink: (String) -> Void = { _ in }

    #if canImport(WebKit)
    /// The web view — upstream `ReadRssActivity.webView`.
    ///
    /// The JavaScript of the source may run — upstream
    /// `ReadRssActivity.upJavaScriptEnable`.
    @State private var webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        // The JavaScript of the source may run — upstream
        // `ReadRssActivity.upJavaScriptEnable` (`WKPreferences.javaScriptEnabled`).
        configuration.preferences.javaScriptEnabled = true
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    #endif

    var body: some View {
        #if canImport(WebKit)
        if let content {
            WebViewRepresentable(
                webView: webView,
                url: article.link,
                html: html,
                baseURL: baseURL,
                injectJs: source.injectJs,
                overrideJs: source.shouldOverrideUrlLoading,
                isAllowed: { url in RssArticleHtml.isAllowed(url: url, source: source) },
                onOpenLink: onOpenLink
            )
            .ignoresSafeArea()
        } else {
            WebViewRepresentable(
                webView: webView,
                url: article.link,
                isAllowed: { url in RssArticleHtml.isAllowed(url: url, source: source) },
                onOpenLink: onOpenLink
            )
            .ignoresSafeArea()
        }
        #else
        ScrollView {
            Text(content ?? article.description ?? "")
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
        #endif
    }

    /// The HTML of the article — upstream `ReadRssViewModel.clHtml`.
    private var html: String {
        RssArticleHtml.document(
            content: content ?? "",
            source: source,
            baseURL: baseURL
        )
    }

    /// The base url of the article — upstream `rssSource.loadWithBaseUrl`.
    ///
    /// The upstream loads the HTML with the address of the article as its
    /// base url, otherwise the relative links of the content do not resolve.
    private var baseURL: String? {
        guard source.loadWithBaseUrl else { return nil }
        return article.link.isEmpty ? nil : article.link
    }
}
