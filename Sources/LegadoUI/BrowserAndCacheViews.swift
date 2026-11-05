//
//  BrowserAndCacheViews.swift
//  LegadoUI
//
//  The in-app browser and the cache management.
//
//  Upstream `ui/browser/WebViewActivity.kt` opens a web page inside the app
//  with the app cookies and a search field; upstream
//  `ui/book/manage/ManageCacheActivity.kt` (and `CleanCacheActivity`) lists
//  the cached books and the cache kinds.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

#if canImport(FoundationNetworking)
// `URLRequest` lives in FoundationNetworking on Linux.
import FoundationNetworking
#endif

#if canImport(WebKit)
import WebKit
#endif

// MARK: - The in-app browser

/// The in-app browser — upstream `WebViewActivity`.
public struct InAppBrowserView: View {

    let url: String
    /// The model — the browser offers the download of a file to the download
    /// service of the app (upstream `WebViewActivity`'s download listener).
    let model: LegadoAppModel?
    @State private var address: String = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    /// The file the page offers to download — upstream the snackbar of
    /// `WebViewActivity`.
    @State private var pendingDownload: PendingDownload?

    public init(url: String, model: LegadoAppModel? = nil) {
        self.url = url
        self.model = model
        _address = State(initialValue: url)
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("地址", text: $address)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("打开") {
                    open()
                }
            }
            .padding(8)
            BrowserContent(url: address, onDownload: { url, fileName in
                pendingDownload = PendingDownload(
                    url: url,
                    fileName: fileName ?? DownloadRequest.fileName(for: url)
                )
            })
            HStack {
                Button("后退") { }
                    .disabled(!canGoBack)
                Button("前进") { }
                    .disabled(!canGoForward)
                Spacer()
                Link("在浏览器中打开", destination: URL(string: address) ?? URL(string: "about:blank")!)
            }
            .padding(8)
        }
        .navigationTitle("网页")
        // Upstream `WebViewActivity`'s download listener — the user is asked
        // whether the file should be downloaded.
        .alert("下载文件", isPresented: Binding(
            get: { pendingDownload != nil },
            set: { if !$0 { pendingDownload = nil } }
        )) {
            Button("下载") {
                if let pendingDownload {
                    model?.startDownload(url: pendingDownload.url, fileName: pendingDownload.fileName)
                }
                pendingDownload = nil
            }
            Button("取消") { pendingDownload = nil }
        } message: {
            Text(pendingDownload?.fileName ?? "")
        }
    }

    private func open() {
        var normalized = address.trimmingCharacters(in: .whitespaces)
        if !normalized.contains("://") {
            normalized = "https://\(normalized)"
        }
        address = normalized
    }
}

/// A file the page offers to download — upstream the download listener of
/// `WebViewActivity`.
struct PendingDownload: Identifiable {
    let id = UUID()
    let url: String
    let fileName: String
}

/// The web view itself — the real `WKWebView` on Apple platforms, a text
/// placeholder elsewhere (the Linux build only type-checks the code).
struct BrowserContent: View {

    let url: String
    /// The action of a file the page offers to download — upstream the
    /// download listener of `WebViewActivity`.
    var onDownload: ((String, String?) -> Void)?

    #if canImport(WebKit)
    @State private var webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    #endif

    var body: some View {
        #if canImport(WebKit)
        WebViewRepresentable(webView: webView, url: url, onDownload: onDownload)
            .ignoresSafeArea()
        #else
            VStack {
                Text(url)
                    .font(.system(size: 12))
                Text("网页视图仅在 iOS / macOS 上可用")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        #endif
    }
}

#if canImport(WebKit)
/// The `WKWebView` wrapper.
///
/// The wrapper loads an url or an HTML document. The HTML is used by the
/// reader of the RSS articles — upstream `ReadRssActivity` loads the
/// article with `loadDataWithBaseURL`.
struct WebViewRepresentable: UIViewRepresentable {

    let webView: WKWebView
    let url: String
    /// The HTML of the page — when it is set the HTML is loaded instead of
    /// the url (upstream `ReadRssActivity.loadDataWithBaseURL`).
    var html: String? = nil
    /// The base url of the HTML — upstream `rssSource.loadWithBaseUrl`.
    var baseURL: String? = nil
    /// The JavaScript that runs when the page is loaded — upstream
    /// `rssSource.injectJs`.
    var injectJs: String? = nil
    /// The JavaScript that decides whether a link is opened — upstream
    /// `rssSource.shouldOverrideUrlLoading`.
    var overrideJs: String? = nil
    /// Whether a request of the page is allowed — upstream the white list
    /// and the black list of the source.
    var isAllowed: ((String) -> Bool)? = nil
    /// The action of a link that may not be opened in the page.
    var onOpenLink: ((String) -> Void)? = nil
    /// The action of a file the page offers to download — upstream the
    /// download listener of `WebViewActivity`.
    var onDownload: ((String, String?) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator(webView: webView) }

    func makeUIView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.injectJs = injectJs
        coordinator.overrideJs = overrideJs
        coordinator.isAllowed = isAllowed
        coordinator.onOpenLink = onOpenLink
        coordinator.onDownload = onDownload
        if let html {
            guard coordinator.lastHTML != html else { return }
            coordinator.lastHTML = html
            coordinator.lastURL = url
            let base = baseURL.flatMap { URL(string: $0) }
            uiView.loadHTMLString(html, baseURL: base)
            return
        }
        guard coordinator.lastURL != url else { return }
        coordinator.lastURL = url
        coordinator.lastHTML = nil
        if let target = URL(string: url) {
            uiView.load(URLRequest(url: target))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        var lastURL: String?
        var lastHTML: String?
        var injectJs: String?
        var overrideJs: String?
        var isAllowed: ((String) -> Bool)?
        var onOpenLink: ((String) -> Void)?
        var onDownload: ((String, String?) -> Void)?

        init(webView: WKWebView) {
            self.webView = webView
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            lastURL = webView.url?.absoluteString
            // Upstream `ReadRssActivity.onPageFinished` evaluates the
            // `injectJs` of the source.
            if let injectJs, !injectJs.isEmpty {
                webView.evaluateJavaScript(injectJs, completionHandler: nil)
            }
        }

        /// The decision of a link — upstream
        /// `ReadRssActivity.CustomWebViewClient.shouldOverrideUrlLoading`.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let absolute = url.absoluteString
            // The white list and the black list of the source.
            if let isAllowed, !isAllowed(absolute) {
                decisionHandler(.cancel)
                return
            }
            if let overrideJs, !overrideJs.isEmpty {
                // The script of the source decides — upstream
                // `source.evalJS(js) { put("url", url.toString()) }`.
                let script = "try { (\(overrideJs)) } catch (e) { '' }"
                webView.evaluateJavaScript(script) { result, _ in
                    let handled = (result as? String)?.isEmpty == false
                    if handled {
                        decisionHandler(.cancel)
                    } else {
                        decisionHandler(.allow)
                    }
                }
                return
            }
            switch url.scheme?.lowercased() {
            case "http", "https", "jsbridge", nil:
                decisionHandler(.allow)
            case "legado", "yuedu":
                decisionHandler(.cancel)
                onOpenLink?(absolute)
            default:
                decisionHandler(.cancel)
                onOpenLink?(absolute)
            }
        }

        /// The decision of a response — upstream the download listener of
        /// `WebViewActivity` (`setDownloadListener`).
        ///
        /// A file the web view cannot show (an attachment, an archive, an
        /// application) is offered to the download service of the app.
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
        ) {
            let response = navigationResponse.response
            guard let url = response.url, url.scheme?.lowercased() == "http" || url.scheme?.lowercased() == "https" else {
                decisionHandler(.allow)
                return
            }
            let attachment = (response as? HTTPURLResponse)
                .map { ($0.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased().contains("attachment") }
                ?? false
            guard attachment || !navigationResponse.canShowMIMEType else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            let fileName = (response.suggestedFilename?.isEmpty == false
                ? response.suggestedFilename
                : DownloadRequest.fileName(for: url.absoluteString))
            onDownload?(url.absoluteString, fileName)
        }
    }
}
#endif

// MARK: - The cache management

/// The cache management — upstream `ManageCacheActivity` / `CleanCacheActivity`.
public struct CacheManageView: View {

    @ObservedObject var model: LegadoAppModel
    @State private var rows: [CacheRow] = []
    @State private var message: String?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section("缓存") {
                ForEach(rows, id: \.bookUrl) { row in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.name)
                            Text(row.sizeText)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("清除") {
                            clear(row)
                        }
                    }
                }
            }
            Section {
                Button("清除全部缓存") {
                    clearAll()
                }
            }
            Section("下载") {
                // Upstream `ui/book/cache/CacheActivity.kt` — the download
                // queue of the offline cache.
                NavigationLink("下载管理") {
                    DownloadManageView(model: model)
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
        .navigationTitle("缓存管理")
        .onAppear {
            reload()
        }
    }

    private func reload() {
        guard let storage = model.environment.cacheStorage else {
            rows = []
            return
        }
        let books = (try? model.environment.store.allBooks()) ?? []
        rows = books.compactMap { book in
            let folder = storage.layout.folder(for: book)
            guard let entries = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey]
            ), !entries.isEmpty else { return nil }
            let size = entries.reduce(Int64(0)) { total, url in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                return total + Int64(values?.fileSize ?? 0)
            }
            return CacheRow(bookUrl: book.bookUrl, name: book.name, size: size)
        }
    }

    private func clear(_ row: CacheRow) {
        guard let storage = model.environment.cacheStorage,
              let book = model.books.first(where: { $0.bookUrl == row.bookUrl }) else { return }
        storage.clearCache(book: book)
        reload()
        message = "已清除 \(row.name)"
    }

    private func clearAll() {
        for row in rows {
            guard let storage = model.environment.cacheStorage,
                  let book = model.books.first(where: { $0.bookUrl == row.bookUrl }) else { continue }
            storage.clearCache(book: book)
        }
        reload()
        message = "已清除全部缓存"
    }
}

/// A row of the cache list.
struct CacheRow: Identifiable {
    let bookUrl: String
    let name: String
    let size: Int64

    var id: String { bookUrl }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}
