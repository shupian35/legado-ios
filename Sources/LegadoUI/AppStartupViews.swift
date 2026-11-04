//
//  AppStartupViews.swift
//  LegadoUI
//
//  The screens of the startup sequence — upstream
//  `app/src/main/java/io/legado/app/ui/main/MainActivity.kt`.
//
//  * the privacy policy has to be accepted before the app is used
//    (`MainActivity.privacyPolicy()`),
//  * the help of the app is shown on the very first run and the changelog
//    after an update (`MainActivity.upVersion()`),
//  * a crash of the reader is reported (`MainActivity.notifyAppCrash()`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

// MARK: - The privacy policy

/// The privacy policy gate — upstream `MainActivity.privacyPolicy()`.
///
/// The upstream shows an alert with the `privacyPolicy.md` document and the
/// buttons 同意 / 拒绝; refusing closes the app. An iOS app must never close
/// itself, so refusing keeps the gate on the screen.
public struct PrivacyPolicyGateView: View {

    private let onAccept: () -> Void
    private let onRefuse: () -> Void

    public init(onAccept: @escaping () -> Void, onRefuse: @escaping () -> Void) {
        self.onAccept = onAccept
        self.onRefuse = onRefuse
    }

    public var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
            VStack(spacing: 12) {
                Text("隐私政策")
                    .font(.system(size: 18))
                    .bold()
                ScrollView {
                    MarkdownBody(markdown: AboutDocument.privacyPolicy.text)
                }
                HStack(spacing: 24) {
                    Button("拒绝") {
                        onRefuse()
                    }
                    Button("同意") {
                        onAccept()
                    }
                }
            }
            .padding()
        }
    }
}

// MARK: - The startup document

/// The document of the startup sequence — upstream `TextDialog.Mode.MD`.
public struct StartupDocumentSheet: View {

    private let document: StartupDocument
    private let onClose: () -> Void

    public init(document: StartupDocument, onClose: @escaping () -> Void) {
        self.document = document
        self.onClose = onClose
    }

    public var body: some View {
        NavigationStack {
            MarkdownView(title: document.title, markdown: StartupDocumentText.text(for: document))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("好") {
                            onClose()
                        }
                    }
                }
        }
    }
}

/// The text of the documents of the startup sequence.
public enum StartupDocumentText {

    /// The text of a document.
    public static func text(for document: StartupDocument) -> String {
        switch document {
        case .appHelp:
            return AppHelpDocuments.appHelp
        case .updateLog:
            return AboutDocument.updateLog.text
        }
    }
}

// MARK: - The crash prompt

/// The crash prompt — upstream `MainActivity.notifyAppCrash()`.
public struct CrashPromptSheet: View {

    private let onShowLogs: () -> Void
    private let onClose: () -> Void

    public init(onShowLogs: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onShowLogs = onShowLogs
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("检测到阅读发生了崩溃，是否打开崩溃日志以便报告问题？")
                .multilineTextAlignment(.center)
            HStack(spacing: 24) {
                Button("否") {
                    onClose()
                }
                Button("是") {
                    onShowLogs()
                }
            }
        }
        .padding()
    }
}
