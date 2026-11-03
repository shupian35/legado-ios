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
        isWorking = true
        defer { isWorking = false }
        do {
            let request = try DeepLink.parse(url)
            let summary = try await DeepLink.importData(
                from: request,
                httpClient: model.environment.httpClient,
                store: model.environment.store,
                userAgent: model.environment.settings.userAgent
            )
            lastKind = summary.kind
            message = message(for: summary)
            model.reloadAll()
        } catch {
            lastKind = nil
            message = Self.describe(error)
        }
    }

    /// The text shown after a successful import.
    public func message(for summary: ImportSummary) -> String {
        let what = summary.name?.isEmpty == false ? summary.name! : summary.kind.rawValue
        return "已导入 \(summary.count) 个\(what)"
    }

    /// The text shown after a failed import.
    public static func describe(_ error: Error) -> String {
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
                message = "暂不支持直接打开压缩包"
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
            if isWelcomePresented {
                WelcomeView {
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
    }
}
