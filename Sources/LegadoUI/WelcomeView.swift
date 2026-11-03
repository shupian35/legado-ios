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

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The welcome / splash screen.
public struct WelcomeView: View {

    /// Called when the splash is over.
    var onFinish: () -> Void

    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    public var body: some View {
        ZStack {
            Color.accentColor.opacity(0.08)
            VStack(spacing: 12) {
                Image(systemName: "book.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.accentColor)
                Text("阅读")
                    .font(.system(size: 26, weight: .bold))
                Text("Legado")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .task {
            // The upstream shows the splash for 600 ms.
            try? await Task.sleep(nanoseconds: 600_000_000)
            onFinish()
        }
    }
}
