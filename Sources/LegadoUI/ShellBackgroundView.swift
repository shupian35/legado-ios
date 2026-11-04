//
//  ShellBackgroundView.swift
//  LegadoUI
//
//  Upstream reference:
//  base/BaseActivity.kt:162-174 (`upBackgroundImage`)
//  help/config/ThemeConfig.kt:79-100 (`getBgImage`)
//
//  The upstream puts the background image of the day or the night theme
//  behind the whole window, blurred by `bgImageBlurring` / `bgImageNBlurring`.
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

/// The background of the shell — the theme colour plus the background image.
public struct ShellBackgroundView: View {

    @ObservedObject var model: LegadoAppModel
    @ObservedObject private var loader = ReaderBackgroundImageLoader()

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            model.currentTheme.background
            image
        }
        .onAppear {
            reload()
        }
        .onChange(of: model.isSystemDark) { _ in
            reload()
        }
    }

    /// The background image of the current mode — upstream `ThemeConfig.getBgImage`.
    private var background: (path: String, blurring: Int)? {
        model.environment.settings.backgroundImage(isNight: isNight)
    }

    /// Whether the night theme is active — upstream `AppConfig.isNightTheme`.
    private var isNight: Bool {
        model.environment.settings.isNightTheme
    }

    @ViewBuilder
    private var image: some View {
        if let background, !background.path.isEmpty {
            let content = Group {
                #if canImport(UIKit)
                if let data = loader.data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                #elseif canImport(AppKit)
                if let data = loader.data, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                #endif
            }
            if background.blurring > 0 {
                blurred(content, radius: Double(background.blurring))
            } else {
                content
            }
        }
    }

    private func reload() {
        guard let background else { return }
        loader.load(path: background.path)
    }
}
