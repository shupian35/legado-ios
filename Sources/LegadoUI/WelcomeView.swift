//
//  WelcomeView.swift
//  LegadoUI
//
//  The welcome screen — upstream `ui/welcome/WelcomeActivity.kt`.
//
//  The upstream splash is the launcher activity: it shows the app icon for
//  600 ms and then opens the main activity. When the preference
//  `defaultToRead` is on and the user has a last-read book, the reader is
//  opened directly (`WelcomeActivity.startMainActivity`).
//
//  The background of the splash is configurable: the preference
//  `customWelcome` switches the own image on, `welcomeImage` /
//  `welcomeImageDark` hold its path and `welcomeShowText` /
//  `welcomeShowIcon` (and their night variants) hide the text and the icon
//  (`WelcomeActivity.upBackgroundImage`).
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
#elseif canImport(AppKit)
import AppKit
#endif

/// The welcome / splash screen.
public struct WelcomeView: View {

    /// Called when the splash is over.
    var onFinish: () -> Void
    /// The settings of the app — upstream `AppConfig`.
    var settings: AppSettings?

    /// The data of the background image — upstream `BitmapUtils.decodeBitmap`.
    @State private var imageData: Data?

    public init(onFinish: @escaping () -> Void, settings: AppSettings? = nil) {
        self.onFinish = onFinish
        self.settings = settings
    }

    public var body: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
            backgroundImage
            VStack(spacing: 12) {
                if showsIcon {
                    Image(systemName: "book.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.accentColor)
                }
                if showsText {
                    Text("阅读")
                        .font(.system(size: 26, weight: .bold))
                    Text("Legado")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
        }
        .task {
            loadBackgroundImage()
            // The upstream shows the splash for 600 ms.
            try? await Task.sleep(nanoseconds: 600_000_000)
            onFinish()
        }
    }

    // MARK: - The configuration

    /// Whether the own background image is used — upstream
    /// `PreferKey.customWelcome`.
    private var usesOwnImage: Bool {
        guard let settings else { return false }
        return settings.customWelcome
    }

    /// Whether the text is shown — upstream `AppConfig.welcomeShowText`.
    private var showsText: Bool {
        guard let settings else { return true }
        return settings.welcomeShowsText
    }

    /// Whether the icon is shown — upstream `AppConfig.welcomeShowIcon`.
    private var showsIcon: Bool {
        guard let settings else { return true }
        return settings.welcomeShowsIcon
    }

    /// The path of the background image of the current mode.
    private var imagePath: String? {
        guard let settings else { return nil }
        return settings.welcomeImage
    }

    /// Loads the background image of the splash.
    private func loadBackgroundImage() {
        guard usesOwnImage, let path = imagePath, !path.isEmpty else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }
        imageData = data
    }

    @ViewBuilder
    private var backgroundImage: some View {
        // SwiftUI has no cross-platform image initialiser — `Image(uiImage:)`
        // on iOS and `Image(nsImage:)` on macOS.
        #if canImport(UIKit)
        if let data = imageData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        #elseif canImport(AppKit)
        if let data = imageData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        }
        #endif
    }
}
