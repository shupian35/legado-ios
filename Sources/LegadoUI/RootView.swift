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
            TabView(selection: $model.selectedTab) {
                BookshelfView(model: model)
                    .tabItem {
                        Label("书架", systemImage: "books.vertical")
                    }
                    .tag(HomePage.bookshelf)
                // The upstream hides the discovery and the RSS tabs with the
                // `showDiscovery` / `showRSS` preferences (`AppConfig.kt`).
                if model.environment.settings.showDiscovery {
                    DiscoverView(model: model)
                        .tabItem {
                            Label("发现", systemImage: "safari")
                        }
                        .tag(HomePage.explore)
                }
                if model.environment.settings.showRSS {
                    RSSView(model: model)
                        .tabItem {
                            Label("订阅", systemImage: "newspaper")
                        }
                        .tag(HomePage.rss)
                }
                SettingsView(model: model)
                    .tabItem {
                        Label("我的", systemImage: "gearshape")
                    }
                    .tag(HomePage.my)
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
        // The upstream looks for a newer backup on the WebDAV server when the
        // app starts (`MainActivity.backupSync()`) and asks the user whether
        // it should be restored.
        .task {
            await model.checkNewBackup()
        }
        // Only one alert can be attached to a view, so the error message, the
        // status message and the backup question share this one.
        .alert(
            alertTitle,
            isPresented: Binding(
                get: { model.errorMessage != nil || model.backupMessage != nil || model.pendingWebDavBackup != nil },
                set: { if !$0 { dismissAlerts() } }
            )
        ) {
            if model.pendingWebDavBackup != nil {
                Button("取消") {
                    model.pendingWebDavBackup = nil
                }
                Button("恢复") {
                    Task { await model.restorePendingWebDavBackup() }
                }
            } else {
                Button("好") {
                    dismissAlerts()
                }
            }
        } message: {
            Text(alertMessage)
        }
    }

    private var alertTitle: String {
        if model.pendingWebDavBackup != nil { return "发现新的备份" }
        if model.errorMessage != nil { return "出错了" }
        return "提示"
    }

    private var alertMessage: String {
        if model.pendingWebDavBackup != nil {
            return "服务器上有一个更新的备份，是否恢复？"
        }
        return model.errorMessage ?? model.backupMessage ?? ""
    }

    private func dismissAlerts() {
        model.errorMessage = nil
        model.backupMessage = nil
        model.pendingWebDavBackup = nil
    }
}
