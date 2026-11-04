//
//  RootView.swift
//  LegadoUI
//
//  The root of the application shell.
//
//  Upstream `ui/main/MainActivity` shows the bookshelf, the discovery and the
//  RSS feed in a bottom navigation bar; the "我的" tab of upstream is a menu
//  inside the bookshelf, the port gives it its own tab because iOS has no
//  drawer menu.
//
//  See `AppModel.swift` for the state.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import LegadoCore

/// The tabs of the application.
public struct RootView: View {

    @ObservedObject var model: LegadoAppModel

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            // Upstream `BaseActivity.upBackgroundImage` — the background
            // image of the day or the night theme behind the whole window.
            ShellBackgroundView(model: model)
            TabView {
                BookshelfView(model: model)
                    .tabItem {
                        Label("书架", systemImage: "books.vertical")
                    }
                // The upstream hides the discovery and the RSS tabs with the
                // `showDiscovery` / `showRSS` preferences (`AppConfig.kt`).
                if model.environment.settings.showDiscovery {
                    DiscoverView(model: model)
                        .tabItem {
                            Label("发现", systemImage: "safari")
                        }
                }
                if model.environment.settings.showRSS {
                    RSSView(model: model)
                        .tabItem {
                            Label("订阅", systemImage: "newspaper")
                        }
                }
                SettingsView(model: model)
                    .tabItem {
                        Label("我的", systemImage: "gearshape")
                    }
            }
        }
        .background(model.currentTheme.background)
        // The login of a source is requested from several places (the book
        // detail, the discover, the source manager, the reader); the sheet is
        // presented here so that every request opens it.
        .sheet(isPresented: Binding(
            get: { model.loginSource != nil },
            set: { if !$0 { model.dismissPresentedSheet() } }
        )) {
            if let source = model.loginSource {
                NavigationStack {
                    SourceLoginView(source: source, model: model)
                }
            }
        }
    }
}
