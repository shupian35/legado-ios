//
//  DeepLinkHandler.swift
//  LegadoUI
//
//  The port of
//  app/src/main/java/io/legado/app/ui/association/OnLineImportActivity.kt
//  and BaseAssociationViewModel.kt.
//
//  Upstream the Android app answers the `legado://` scheme, so a book source
//  (or an RSS source, a replace rule, an HTTP-TTS rule, a dictionary rule or a
//  TXT TOC rule) can be imported from a browser, a message or a file.
//
//  The parsing and the import itself live in `LegadoCore/App/DeepLink.swift`;
//  this file only wires them into the shell.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// Handles the `legado://` links.
public final class DeepLinkHandler: ObservableObject {

    /// The shared handler — the iOS app uses it from `onOpenURL`.
    public static let shared = DeepLinkHandler()

    /// Whether an import is in flight.
    @Published public var isWorking = false
    /// The message of the last import (shown as an alert).
    @Published public var message: String?
    /// The kind of the last import.
    @Published public var lastKind: ImportKind?
    /// The theme that waits for the confirmation of the user — upstream
    /// `ImportThemeDialog`.
    @Published public var pendingTheme: AppTheme?
    /// The book that waits for the confirmation of the user — upstream
    /// `AddToBookshelfDialog` opens the book information.
    @Published public var pendingBook: Book?

    private init() {}

    /// Handles a link: parses it, downloads the data and imports it.
    public func handle(_ url: URL, model: LegadoAppModel) {
        Task { @MainActor in
            await handleAsync(url, model: model)
        }
    }

    /// Handles a link asynchronously.
    @MainActor
    public func handleAsync(_ url: URL, model: LegadoAppModel) async {
        // The shortcuts of the home screen open the app with a link of the
        // form `legado://shortcut/{name}` — upstream `api/ShortCuts.kt`.
        if let shortcut = DeepLink.shortcut(from: url) {
            await perform(shortcut, model: model)
            return
        }
        // The search of a shared text — upstream
        // `SharedReceiverActivity.dispose(text)` opens `SearchActivity` when
        // the text is not an address.
        if let keyword = DeepLinkSearch.keyword(from: url) {
            model.search(keyword)
            return
        }
        isWorking = true
        defer { isWorking = false }
        do {
            let request = try DeepLink.parse(url)
            let action = DeepLinkService.action(forPath: request.path, host: request.host)
            switch action {
            case .importJSON(let kind):
                let summary = try await DeepLink.importData(
                    from: request,
                    httpClient: model.environment.httpClient,
                    store: model.environment.store,
                    userAgent: model.environment.settings.userAgent
                )
                lastKind = summary.kind
                message = message(for: summary)
                model.reloadAll()
            case .importTheme:
                let theme = try await DeepLinkService.importTheme(
                    from: request,
                    httpClient: model.environment.httpClient,
                    userAgent: model.environment.settings.userAgent
                )
                pendingTheme = theme
            case .importReadConfig:
                let payload = try await DeepLinkService.importReadConfig(
                    from: request,
                    httpClient: model.environment.httpClient,
                    userAgent: model.environment.settings.userAgent
                )
                try model.applyReaderStyleArchive(payload)
                message = "导入排版成功"
            case .addToBookshelf:
                let result = try await DeepLinkService.addToBookshelf(
                    bookUrl: request.source,
                    store: model.environment.store,
                    sources: try model.environment.store.allSources(),
                    dependencies: model.environment.dependencies()
                )
                // Upstream `saveSearchBook` — the book is written to the search
                // books and the book information is opened.
                try model.environment.store.insert([result.book.toSearchBook()])
                pendingBook = result.book
            case nil:
                // Upstream `OnLineImportViewModel.determineType` — the content
                // type decides: an archive is the reader style, everything
                // else is a JSON document whose kind comes from its keys.
                let data = try await DeepLinkService.download(
                    from: request,
                    httpClient: model.environment.httpClient,
                    userAgent: model.environment.settings.userAgent
                )
                if data.starts(with: [0x50, 0x4B]) {
                    let payload = try ReaderConfigArchive.read(data)
                    try model.applyReaderStyleArchive(payload)
                    message = "导入排版成功"
                } else {
                    let text = String(decoding: data, as: UTF8.self)
                    let kind = try DeepLink.detectKind(json: text)
                    let summary = try DeepLink.importJSON(text, kind: kind, store: model.environment.store)
                    lastKind = summary.kind
                    message = message(for: summary)
                    model.reloadAll()
                }
            }
        } catch {
            lastKind = nil
            message = Self.describe(error)
        }
    }

    /// Performs a shortcut of the home screen — upstream `api/ShortCuts.kt`.
    @MainActor
    public func perform(_ shortcut: ShortcutAction, model: LegadoAppModel) async {
        switch shortcut {
        case .bookshelf:
            model.selectTab(.bookshelf)
        case .lastRead:
            await model.openLastRead()
        case .readAloud:
            await model.startLastReadAloud()
        }
    }

    /// Adds the theme that waits for the confirmation — upstream
    /// `ImportThemeDialog`.
    public func confirmTheme(model: LegadoAppModel) {
        guard let theme = pendingTheme else { return }
        pendingTheme = nil
        model.addTheme(theme)
        message = "已导入主题 \(theme.themeName)"
    }

    /// Cancels the theme import.
    public func cancelTheme() {
        pendingTheme = nil
    }

    /// The text shown after a successful import.
    public func message(for summary: ImportSummary) -> String {
        let what = summary.name?.isEmpty == false ? summary.name! : summary.kind.rawValue
        return "已导入 \(summary.count) 个\(what)"
    }

    /// The text shown after a failed import.
    public static func describe(_ error: Error) -> String {
        if let error = error as? DeepLinkActionError {
            switch error {
            case .alreadyOnShelf(let name):
                return "\(name) 已在书架"
            case .malformedBookUrl:
                return "书籍地址格式不对"
            case .noMatchingSource:
                return "未找到匹配书源"
            case .invalidTheme:
                return "主题数据无效"
            case .invalidReadConfig:
                return "排版数据无效"
            }
        }
        guard let error = error as? DeepLinkError else {
            return error.localizedDescription
        }
        switch error {
        case .wrongScheme:
            return "不是合法的 legado 链接"
        case .missingSource:
            return "链接缺少 src 参数"
        case .unsupportedPath(let path):
            return "不支持的路径 \(path)"
        case .unknownFormat:
            return "格式不对"
        case .downloadFailed(let reason):
            return "下载失败：\(reason)"
        case .unsupportedKind(let kind):
            return "暂不支持导入 \(kind.rawValue)"
        case .invalidData(let kind):
            return "\(kind.rawValue) 数据无效"
        }
    }

    // MARK: - The file association

    /// Handles a file that is opened with the app ("Open with" / a share).
    ///
    /// Upstream `FileAssociationViewModel.dispatchIntent`: a JSON document is
    /// imported by its kind, a book file becomes a local book, an archive is
    /// unpacked and anything else is reported as unsupported.
    @MainActor
    public func handleFile(_ url: URL, model: LegadoAppModel) async {
        isWorking = true
        defer { isWorking = false }
        #if canImport(Foundation) && os(iOS) || os(macOS)
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        #endif
        do {
            let data = try Data(contentsOf: url)
            let kind = FileAssociation.kind(fileName: url.lastPathComponent, content: data)
            switch kind {
            case .json:
                guard let text = String(data: data, encoding: .utf8),
                      let importKind = FileAssociation.importKind(ofJSON: text) else {
                    message = "格式不对"
                    return
                }
                let summary = try DeepLink.importJSON(text, kind: importKind, store: model.environment.store)
                lastKind = summary.kind
                message = message(for: summary)
                model.reloadAll()
            case .book:
                try model.importLocalBook(from: url)
                message = "已导入本地书"
                model.reloadAll()
            case .archive:
                // Upstream `FileAssociationViewModel.dispatchIntent` unpacks
                // the archive and imports every book in it.
                let imported = await model.importLocalBooks([url])
                message = imported > 0 ? "已导入 \(imported) 本本地书" : "压缩包里没有找到书籍"
                model.reloadAll()
            case .unsupported:
                message = "不支持的文件"
            }
        } catch {
            message = "无法打开文件\n\(error.localizedDescription)"
        }
    }
}

/// The root scene of the app.
///
/// It is shared by the iOS entry point (`Sources/LegadoAppUI/LegadoAppIOS.swift`)
/// and by the Linux/macOS executable (`Sources/LegadoApp/LegadoAppMain.swift`),
/// so the deep-link handling is compiled — and therefore verified — on every
/// platform.
public struct LegadoRootScene: View {

    /// The state of the shell.
    @ObservedObject var model: LegadoAppModel
    /// The deep-link handler.
    @ObservedObject var handler: DeepLinkHandler
    /// Whether the welcome splash is still shown.
    @State private var isWelcomePresented = true

    public init(model: LegadoAppModel, handler: DeepLinkHandler = .shared) {
        self.model = model
        self.handler = handler
    }

    public var body: some View {
        ZStack {
            RootView(model: model)
                .onOpenURL { url in
                    // A file URL is an "Open with" / a share; the `legado://` links
                    // are the online imports.
                    if url.isFileURL {
                        Task { await handler.handleFile(url, model: model) }
                    } else {
                        handler.handle(url, model: model)
                    }
                }
                // The startup sequence — upstream `MainActivity.onPostCreate()`.
                .task {
                    await model.runStartup()
                }
                // The help of the app on the first run, the changelog after an
                // update — upstream `MainActivity.upVersion()`.
                .sheet(
                    isPresented: Binding(
                        get: {
                            if case .document = model.startupPhase { return true }
                            return false
                        },
                        set: { if !$0 { model.dismissStartupDocument() } }
                    )
                ) {
                    if case .document(let document) = model.startupPhase {
                        StartupDocumentSheet(document: document) {
                            model.dismissStartupDocument()
                        }
                    }
                }
                // The crash of the reader — upstream
                // `MainActivity.notifyAppCrash()`.
                .alert(
                    "提示",
                    isPresented: Binding(
                        get: { model.startupPhase == .crashPrompt },
                        set: { if !$0 { model.answerCrashPrompt(showLogs: false) } }
                    )
                ) {
                    Button("否") {
                        model.answerCrashPrompt(showLogs: false)
                    }
                    Button("是") {
                        model.answerCrashPrompt(showLogs: true)
                    }
                } message: {
                    Text("检测到阅读发生了崩溃，是否打开崩溃日志以便报告问题？")
                }
            if isWelcomePresented {
                WelcomeView(settings: model.environment.settings) {
                    isWelcomePresented = false
                    // The upstream opens the last-read book directly after the
                    // splash when the preference `defaultToRead` is on.
                    Task { await model.openDefaultRead() }
                    // … and asks for the local password when the user has
                    // never set one (`MainActivity.setLocalPassword`).
                    model.presentLocalPasswordIfNeeded()
                }
            }
            // The local password — the key of the encrypted backup entries.
            if model.isLocalPasswordPresented {
                LocalPasswordView(model: model, allowsCancel: true)
            }
            // The startup sequence — upstream `MainActivity.onPostCreate()`:
            // the privacy policy has to be accepted before the app is used.
            if model.startupPhase == .privacyPolicy {
                PrivacyPolicyGateView(
                    onAccept: { model.acceptPrivacyPolicy() },
                    onRefuse: { model.refusePrivacyPolicy() }
                )
            }
            // The crash log of the reader.
            if model.isCrashLogPresented {
                NavigationStack {
                    CrashLogView(model: model)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭") {
                                    model.isCrashLogPresented = false
                                }
                            }
                        }
                }
            }
            // The jump a rule script asked for — upstream
            // `OpenUrlConfirmDialog`.
            if let request = model.pendingOpenURL {
                OpenUrlConfirmView(model: model, request: request)
            }
            // The source verification — the captcha dialog or the
            // anti-scraping page (upstream `VerificationCodeActivity`).
            if let request = model.pendingVerification {
                Group {
                    switch request.kind {
                    case .captcha:
                        VerificationCodeSheet(
                            request: request,
                            onSubmit: { model.completeVerification(answer: $0) },
                            onCancel: { model.cancelVerification() }
                        )
                    case .browser:
                        VerificationBrowserSheet(
                            request: request,
                            onSubmit: { model.completeVerification(answer: $0) },
                            onCancel: { model.cancelVerification() }
                        )
                    }
                }
            }
        }
        // The result of a deep link — the message of the import or the
        // confirmation of the theme (upstream `ImportThemeDialog`).
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { handler.message != nil || handler.pendingTheme != nil },
                set: { if !$0 { handler.cancelTheme(); handler.message = nil } }
            )
        ) {
            if handler.pendingTheme != nil {
                Button("取消") {
                    handler.cancelTheme()
                }
                Button("导入") {
                    handler.confirmTheme(model: model)
                }
            } else {
                Button("好") {
                    handler.message = nil
                }
            }
        } message: {
            Text(alertMessage)
        }
        // The book of the "add to the bookshelf" link — upstream
        // `AddToBookshelfDialog` opens the book information.
        .sheet(item: $handler.pendingBook) { book in
            NavigationStack {
                BookDetailView(model: model, book: book)
            }
        }
    }

    private var alertTitle: String {
        if handler.pendingTheme != nil { return "导入主题" }
        return "提示"
    }

    private var alertMessage: String {
        if let theme = handler.pendingTheme {
            return "是否导入主题「\(theme.themeName)」？"
        }
        return handler.message ?? ""
    }
}
