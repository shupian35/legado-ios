//
//  ChapterLinkView.swift
//  LegadoUI
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/ReadMenu.kt:329-367 and
//  app/src/main/java/io/legado/app/ui/book/read/MangaMenu.kt:174-204 — the
//  chapter name and the chapter address of the title bar open the web page of
//  the chapter; a long press asks whether the address opens with the system
//  browser or with the built-in browser (`AppConfig.readUrlInBrowser`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

#if canImport(UIKit)
import UIKit
#endif

/// Opens a link with the system browser — upstream `context.openUrl(url)`.
public enum ExternalLink {

    /// Whether the link can be opened with the system browser.
    public static func canOpen(_ url: String) -> Bool {
        guard let value = URL(string: url) else { return false }
        return value.scheme != nil
    }

    /// Opens the link with the system browser.
    ///
    /// The upstream strips the rule that some sources append to the chapter
    /// address (`url.substringBefore(",{")`) before handing the address to the
    /// browser.
    public static func open(_ url: String) {
        let trimmed = url.components(separatedBy: ",{").first ?? url
        guard let value = URL(string: trimmed.trimmingCharacters(in: .whitespaces)),
              value.scheme != nil else { return }
        #if canImport(UIKit)
        Task { @MainActor in
            UIApplication.shared.open(value)
        }
        #endif
    }
}

/// The chapter name and the chapter address of the reader title bar —
/// upstream `ReadMenu.tvChapterName` / `ReadMenu.tvChapterUrl`.
///
/// Tapping opens the web page of the chapter: with the system browser when
/// `readUrlInBrowser` is on, otherwise with the built-in browser. A long press
/// asks which browser to use.
public struct ChapterLinkView: View {

    /// The title of the chapter.
    public var title: String
    /// The absolute address of the chapter.
    public var url: String
    /// Whether the address opens with the system browser — upstream
    /// `AppConfig.readUrlInBrowser`.
    public var openInSystemBrowser: Bool
    /// Called when the address opens with the built-in browser.
    public var onOpenInApp: (String) -> Void
    /// Called when the user picks the browser — upstream
    /// `ReadMenu.chapterViewLongClickListener`.
    public var onChooseBrowser: (Bool) -> Void

    public init(
        title: String,
        url: String,
        openInSystemBrowser: Bool = false,
        onOpenInApp: @escaping (String) -> Void = { _ in },
        onChooseBrowser: @escaping (Bool) -> Void = { _ in }
    ) {
        self.title = title
        self.url = url
        self.openInSystemBrowser = openInSystemBrowser
        self.onOpenInApp = onOpenInApp
        self.onChooseBrowser = onChooseBrowser
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
            if !url.isEmpty {
                Text(url)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { open() }
        .onLongPressGesture { showsBrowserChoice = true }
        .alert("打开方式", isPresented: $showsBrowserChoice) {
            Button("用浏览器打开") { choose(true) }
            Button("用内置浏览器打开") { choose(false) }
            Button("取消", role: .cancel) { }
        }
    }

    /// Whether the browser choice is shown.
    @State private var showsBrowserChoice = false

    /// Opens the chapter address.
    private func open() {
        guard !url.isEmpty else { return }
        if openInSystemBrowser {
            ExternalLink.open(url)
        } else {
            onOpenInApp(url)
        }
    }

    /// Saves the browser choice — upstream `AppConfig.readUrlInBrowser`.
    private func choose(_ useSystemBrowser: Bool) {
        onChooseBrowser(useSystemBrowser)
    }
}
