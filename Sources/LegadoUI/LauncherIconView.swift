//
//  LauncherIconView.swift
//  LegadoUI
//
//  The launcher icon picker — upstream `help/LauncherIconHelp.kt` and the
//  icon grid of `ui/config/ThemeConfigFragment.kt`.
//
//  Upstream keeps six launcher activities and enables the one the user picked.
//  The iOS port uses the alternate icons of the app bundle
//  (`CFBundleAlternateIcons`) and the same preference value.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// The alternate launcher icons — the counterpart of the upstream
/// `LauncherIconHelp.changeIcon`.
public enum LauncherIconController {

    /// The icon the app uses right now; `nil` is the primary icon.
    @MainActor
    public static var current: LauncherIcon? {
        #if canImport(UIKit) && !os(watchOS)
        let name = UIApplication.shared.alternateIconName
        guard let name else { return nil }
        return LauncherIcon.allCases.first { $0.alternateName == name }
        #else
        return nil
        #endif
    }

    /// Sets the icon of the app; `nil` restores the primary one.
    ///
    /// iOS shows its own confirmation dialog, so the call reports the failure
    /// of the user instead of changing the icon.
    @MainActor
    public static func set(_ icon: LauncherIcon?) async throws {
        #if canImport(UIKit) && !os(watchOS)
        // The real API is callback based — `setAlternateIconName(_:completionHandler:)`.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UIApplication.shared.setAlternateIconName(icon?.alternateName) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        #endif
    }
}

/// The picker of the launcher icons.
public struct LauncherIconPickerView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var current: LauncherIcon?
    @State private var message: String?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("图标") {
                Button {
                    select(nil)
                } label: {
                    HStack {
                        Image("AppIcon60x60")
                            .resizable()
                            .frame(width: 44, height: 44)
                        Text("默认图标")
                        Spacer()
                        if current == nil {
                            Text("当前").foregroundColor(.secondary)
                        }
                    }
                }
                ForEach(LauncherIcon.allCases) { icon in
                    Button {
                        select(icon)
                    } label: {
                        HStack {
                            Image(icon.alternateName)
                                .resizable()
                                .frame(width: 44, height: 44)
                            Text(icon.displayName)
                            Spacer()
                            if current == icon {
                                Text("当前").foregroundColor(.secondary)
                            }
                        }
                    }
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
        .navigationTitle("更换图标")
        .onAppear {
            current = model.environment.settings.launcherIcon
        }
    }

    private func select(_ icon: LauncherIcon?) {
        Task {
            do {
                try await LauncherIconController.set(icon)
                model.environment.settings.launcherIcon = icon
                current = icon
                message = "图标已更换"
            } catch {
                message = "更换失败：\(error.localizedDescription)"
            }
        }
    }
}
