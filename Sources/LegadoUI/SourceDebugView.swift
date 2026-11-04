//
//  SourceDebugView.swift
//  LegadoUI
//
//  The book source debugger — upstream `ui/book/source/debug/*`.
//
//  The upstream lets the user type a keyword (or a URL with one of the
//  prefixes) and streams the log of the rule evaluation:
//
//    * a plain URL   → the detail page (`DebugActivity`)
//    * `分类::网址`   → the explore page
//    * `++网址`      → the chapter list page
//    * `--网址`      → the chapter content page
//    * anything else → the search page
//
//  The port uses the platform-independent `SourceDebugger` of `LegadoCore`
//  (the same code the WebSocket debug endpoint uses).
//
//  The toolbar mirrors the upstream's `res/menu/book_source_debug.xml`:
//
//    * 扫码           — scan a book source URL
//    * 搜索页/详情页/目录页/正文页 — the raw HTML of every step
//    * 刷新发现       — reload the categories of the explore page
//    * 帮助           — the upstream's `debugHelp.md`
//
//  The quick actions above the log mirror the upstream's help panel
//  (`activity_source_debug.xml`): the keyword of the source, a system
//  keyword, the first explore category and the URL prefixes.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// One line of the debug log.
public struct DebugLogEntry: Identifiable, Equatable, Sendable {
    public let id = UUID()
    /// The upstream state (the `DebugLogState`).
    public let state: Int
    /// The message.
    public let message: String
    /// The elapsed time.
    public let elapsed: String

    public init(state: Int, message: String, elapsed: String) {
        self.state = state
        self.message = message
        self.elapsed = elapsed
    }
}

/// The raw HTML page that is shown in the "原始HTML" sheet.
public enum DebugHtmlPage: String, Identifiable, CaseIterable, Sendable {
    /// The search page — upstream `menu_search_src`.
    case search
    /// The detail page — upstream `menu_book_src`.
    case book
    /// The table of contents — upstream `menu_toc_src`.
    case toc
    /// The chapter content — upstream `menu_content_src`.
    case content

    public var id: String { rawValue }

    /// The title of the sheet.
    public var title: String {
        switch self {
        case .search: return "搜索页"
        case .book: return "详情页"
        case .toc: return "目录页"
        case .content: return "正文页"
        }
    }
}

/// The source debugger screen.
public struct SourceDebugView: View {

    @ObservedObject var model: LegadoAppModel

    /// The source to debug — the upstream `BookSourceDebugActivity` is opened
    /// with the key of the source that is being edited.
    let sourceUrl: String?

    /// The sources the user can debug.
    @State private var selectedUrl: String = ""
    /// The keyword or the URL.
    @State private var keyword: String = ""
    /// The log lines.
    @State private var logs: [DebugLogEntry] = []
    /// Whether a debug run is in progress.
    @State private var isRunning = false

    // MARK: The raw HTML of the four steps
    //
    // Upstream `BookSourceDebugModel.searchSrc / bookSrc / tocSrc / contentSrc`.

    /// The raw HTML of the search page.
    @State private var searchHtml: String = ""
    /// The raw HTML of the detail page.
    @State private var bookHtml: String = ""
    /// The raw HTML of the table of contents.
    @State private var tocHtml: String = ""
    /// The raw HTML of the chapter content.
    @State private var contentHtml: String = ""

    // MARK: The sheets

    /// The QR scanner.
    @State private var isScannerPresented = false
    /// The scanned text.
    @State private var qrResult: String?
    /// The page whose raw HTML is shown.
    @State private var htmlPage: DebugHtmlPage?
    /// The help.
    @State private var isHelpPresented = false
    /// The explore categories — upstream `initExploreKinds`.
    @State private var exploreKinds: [ExploreKind] = []
    /// Whether the explore category picker is shown.
    @State private var isExplorePickerPresented = false

    public init(model: LegadoAppModel, sourceUrl: String? = nil) {
        self.model = model
        self.sourceUrl = sourceUrl
    }

    /// The source that is being debugged.
    private var source: BookSource? {
        model.sources.first(where: { $0.bookSourceUrl == selectedUrl })
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Picker("书源", selection: $selectedUrl) {
                        ForEach(model.sources, id: \.bookSourceUrl) { source in
                            Text(source.bookSourceName).tag(source.bookSourceUrl)
                        }
                    }
                    TextField("关键字 / 网址", text: $keyword)
                        .textFieldStyle(.roundedBorder)
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

                // The quick actions — upstream `activity_source_debug.xml`.
                quickActions

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
            .navigationTitle("调试")
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Menu("调试") {
                        Button("扫码") {
                            isScannerPresented = true
                        }
                        Button("搜索页") {
                            htmlPage = .search
                        }
                        Button("详情页") {
                            htmlPage = .book
                        }
                        Button("目录页") {
                            htmlPage = .toc
                        }
                        Button("正文页") {
                            htmlPage = .content
                        }
                        Button("刷新发现") {
                            loadExploreKinds()
                        }
                        Button("帮助") {
                            isHelpPresented = true
                        }
                    }
                }
            }
            .onAppear {
                if let sourceUrl {
                    selectedUrl = sourceUrl
                } else if selectedUrl.isEmpty, let first = model.sources.first {
                    selectedUrl = first.bookSourceUrl
                }
                loadExploreKinds()
            }
            .sheet(isPresented: $isScannerPresented) {
                QRScannerView(result: $qrResult)
                    .ignoresSafeArea()
            }
            .onChange(of: qrResult) { _, value in
                guard let value, !value.isEmpty else { return }
                qrResult = nil
                isScannerPresented = false
                // Upstream `qrCodeResult` — the code holds the URL of the
                // source that is debugged.
                selectedUrl = value
            }
            .sheet(item: $htmlPage) { page in
                NavigationStack {
                    DebugHtmlView(title: page.title, html: html(for: page))
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") {
                                    htmlPage = nil
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $isHelpPresented) {
                NavigationStack {
                    DebugHelpView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") {
                                    isHelpPresented = false
                                }
                            }
                        }
                }
            }
            .sheet(isPresented: $isExplorePickerPresented) {
                NavigationStack {
                    List(exploreKinds, id: \.url) { kind in
                        Button("\(kind.title)::\(kind.url ?? "")") {
                            keyword = "\(kind.title)::\(kind.url ?? "")"
                            isExplorePickerPresented = false
                        }
                    }
                    .navigationTitle("选择发现")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("取消") {
                                isExplorePickerPresented = false
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - The quick actions

    /// The upstream's help panel with the quick actions.
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("调试搜索>>输入关键字，如：")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                // The keyword of the source — upstream `ruleSearch.checkKeyWord`.
                Button(checkKeyword.isEmpty ? "我的" : checkKeyword) {
                    keyword = checkKeyword
                }
                .buttonStyle(.bordered)
                // The system keyword — upstream `text_xt`.
                Button("系统") {
                    keyword = "系统"
                }
                .buttonStyle(.bordered)
            }
            Text("调试发现>>输入发现URL，如：")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button(exploreHint) {
                keyword = exploreHint
            }
            .buttonStyle(.bordered)
            .onLongPressGesture {
                isExplorePickerPresented = true
            }
            Text("调试详情页>>输入详情页URL，如：")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button("https://m.qidian.com/book/1015609210") {
                keyword = "https://m.qidian.com/book/1015609210"
            }
            .buttonStyle(.bordered)
            Text("调试目录页>>输入目录页URL，如：")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button("++目录页网址") {
                keyword = prefixKeyword("++")
            }
            .buttonStyle(.bordered)
            Text("调试正文页>>输入正文页URL，如：")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Button("--正文页网址") {
                keyword = prefixKeyword("--")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    /// The keyword of the source — upstream `ruleSearch.checkKeyWord`.
    private var checkKeyword: String {
        source?.searchRule?.checkKeyWord ?? ""
    }

    /// The first explore category — upstream `initExploreKinds`.
    private var exploreHint: String {
        guard let first = exploreKinds.first, let url = first.url else {
            return "系统::http://xxx"
        }
        return "\(first.title)::\(url)"
    }

    /// Adds the prefix to the current keyword — upstream `prefixAutoComplete`.
    private func prefixKeyword(_ prefix: String) -> String {
        if keyword.isEmpty || keyword.count <= 2 {
            return prefix
        }
        if keyword.hasPrefix(prefix) {
            return keyword
        }
        return prefix + keyword
    }

    /// Loads the categories of the explore page — upstream `initExploreKinds`.
    private func loadExploreKinds() {
        guard let source else {
            exploreKinds = []
            return
        }
        exploreKinds = ExploreKinds.parse(source.exploreUrl).filter { !($0.url ?? "").isEmpty }
    }

    // MARK: - The debug run

    /// Runs the debugger and collects the log.
    private func run() {
        guard let source else { return }
        logs = []
        isRunning = true
        searchHtml = ""
        bookHtml = ""
        tocHtml = ""
        contentHtml = ""
        let debugger = SourceDebugger()
        let collector = DebugLogCollector()
        debugger.sink = collector
        Task {
            await debugger.debugBookSource(
                source,
                key: keyword,
                dependencies: model.environment.dependencies()
            )
            await MainActor.run {
                logs = collector.entries
                searchHtml = collector.searchHtml
                bookHtml = collector.bookHtml
                tocHtml = collector.tocHtml
                contentHtml = collector.contentHtml
                isRunning = false
            }
        }
    }

    /// The raw HTML of one step.
    private func html(for page: DebugHtmlPage) -> String {
        switch page {
        case .search: return searchHtml
        case .book: return bookHtml
        case .toc: return tocHtml
        case .content: return contentHtml
        }
    }
}

/// Collects the log lines of a debug run.
final class DebugLogCollector: DebugLogSink, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [DebugLogEntry] = []
    /// The raw HTML of the search page — upstream `searchSrc`.
    private var searchSrc: String = ""
    /// The raw HTML of the detail page — upstream `bookSrc`.
    private var bookSrc: String = ""
    /// The raw HTML of the table of contents — upstream `tocSrc`.
    private var tocSrc: String = ""
    /// The raw HTML of the chapter content — upstream `contentSrc`.
    private var contentSrc: String = ""

    /// The collected lines.
    var entries: [DebugLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    /// The raw HTML of the search page.
    var searchHtml: String {
        lock.lock()
        defer { lock.unlock() }
        return searchSrc
    }

    /// The raw HTML of the detail page.
    var bookHtml: String {
        lock.lock()
        defer { lock.unlock() }
        return bookSrc
    }

    /// The raw HTML of the table of contents.
    var tocHtml: String {
        lock.lock()
        defer { lock.unlock() }
        return tocSrc
    }

    /// The raw HTML of the chapter content.
    var contentHtml: String {
        lock.lock()
        defer { lock.unlock() }
        return contentSrc
    }

    func printLog(state: Int, message: String) {
        lock.lock()
        // The upstream's `BookSourceDebugModel.printLog` intercepts the four
        // raw HTML states instead of adding them to the list.
        switch state {
        case 10:
            searchSrc = message
        case 20:
            bookSrc = message
        case 30:
            tocSrc = message
        case 40:
            contentSrc = message
        default:
            storage.append(DebugLogEntry(state: state, message: message, elapsed: ""))
        }
        lock.unlock()
    }
}

/// The raw HTML of one step of the debug run — upstream `TextDialog("html", …)`.
public struct DebugHtmlView: View {

    private let title: String
    private let html: String

    public init(title: String, html: String) {
        self.title = title
        self.html = html
    }

    public var body: some View {
        ScrollView {
            Text(html.isEmpty ? "没有内容" : html)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
        .navigationTitle(title)
    }
}

/// The debug help — upstream `showHelp("debugHelp")`.
public struct DebugHelpView: View {

    public init() {}

    public var body: some View {
        ScrollView {
            Text(DebugHelp.text)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("书源调试帮助")
    }
}

/// The debug help text — upstream `debugHelp.md`.
public enum DebugHelp {

    public static let text = """
    书源调试

    * 调试搜索>>输入关键字，如：
    ```
    系统
    ```
    * 调试发现>>输入发现URL，如：
    ```
    月票榜::https://www.qidian.com/rank/yuepiao?page={{page}}
    ```
    * 调试详情页>>输入详情页URL，如：
    ```
    https://m.qidian.com/book/1015609210
    ```
    * 调试目录页>>输入目录页URL，如：
    ```
    ++https://www.zhaishuyuan.com/read/30394
    ```
    * 调试正文页>>输入正文页URL，如：
    ```
    --https://www.zhaishuyuan.com/chapter/30394/20940996
    ```
    """
}
