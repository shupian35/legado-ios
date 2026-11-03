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
                    // Upstream `menu_star`.
                    Button(model.isStarred(article) ? "★" : "☆") {
                        model.toggleStar(article)
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    // Upstream `menu_browser_open`.
                    Button("原文") {
                        isBrowserPresented = true
                    }
                }
            }
            .sheet(isPresented: $isBrowserPresented) {
                NavigationStack {
                    InAppBrowserView(url: article.link)
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
