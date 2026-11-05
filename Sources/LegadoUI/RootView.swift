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

    /// The phase of the scene — the upstream backs up when the app is closed
    /// (`MainActivity.onDestroy` → `Backup.autoBack`), the port does it when
    /// the app goes to the background.
    @Environment(\.scenePhase) private var scenePhase

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        ZStack {
            // Upstream `BaseActivity.upBackgroundImage` — the background
            // image of the day or the night theme behind the whole window.
            ShellBackgroundView(model: model)
            tabContent
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    ShellBottomBar(model: model)
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
        // it should be restored. The upstream also cleans up the expired data
        // when the process is created (`App.onCreate`).
        .task {
            await model.runStartupMaintenance()
            await model.checkNewBackup()
        }
        // The upstream backs up once a day when the app is closed
        // (`MainActivity.onDestroy` → `Backup.autoBack`); the port backs up
        // when the app goes to the background.
        .onChange(of: scenePhase) { phase in
            guard phase == .background else { return }
            Task { await model.autoBackup() }
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

    /// The content of the tabs.
    ///
    /// Upstream the fragments of the `BottomNavigationView` of `MainActivity`
    /// stay alive when the tab changes, so the port keeps every tab that was
    /// opened in the stack; the hidden tabs are not touchable.
    @ViewBuilder private var tabContent: some View {
        ZStack {
            BookshelfView(model: model)
                .opacity(model.selectedTab == .bookshelf ? 1 : 0)
                .allowsHitTesting(model.selectedTab == .bookshelf)
            // The upstream hides the discovery and the RSS tabs with the
            // `showDiscovery` / `showRSS` preferences (`AppConfig.kt`).
            if model.visitedTabs.contains(.explore) {
                DiscoverView(model: model)
                    .opacity(model.selectedTab == .explore ? 1 : 0)
                    .allowsHitTesting(model.selectedTab == .explore)
            }
            if model.visitedTabs.contains(.rss) {
                RSSView(model: model)
                    .opacity(model.selectedTab == .rss ? 1 : 0)
                    .allowsHitTesting(model.selectedTab == .rss)
            }
            SettingsView(model: model)
                .opacity(model.selectedTab == .my ? 1 : 0)
                .allowsHitTesting(model.selectedTab == .my)
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

/// The bottom navigation bar of the shell.
///
/// Upstream `MainActivity` uses the Material `BottomNavigationView`; the
/// port draws its own bar, because the bar of `TabView` can neither carry the
/// badge of the books that wait for the update nor report a second tap on
/// the active item (`MainActivity.onNavigationItemReselected`).
public struct ShellBottomBar: View {

    @ObservedObject var model: LegadoAppModel

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs, id: \.self) { tab in
                ShellTabItem(model: model, tab: tab)
            }
        }
        .frame(height: 50)
        .background(model.currentTheme.bottomBackgroundColor)
    }

    /// The tabs of the bar — upstream `MainActivity.upHomePage()` hides the
    /// discovery and the RSS tab when their preference is off.
    private var visibleTabs: [HomePage] {
        HomePage.allCases.filter {
            $0.isVisible(
                showDiscovery: model.environment.settings.showDiscovery,
                showRSS: model.environment.settings.showRSS
            )
        }
    }
}

/// One item of the bottom navigation bar.
public struct ShellTabItem: View {

    @ObservedObject var model: LegadoAppModel

    /// The tab of the item.
    public let tab: HomePage

    public init(model: LegadoAppModel, tab: HomePage) {
        self.model = model
        self.tab = tab
    }

    public var body: some View {
        Button {
            if model.selectedTab == tab {
                // The second tap on the active tab — upstream
                // `MainActivity.onNavigationItemReselected`.
                model.tabReselected(tab)
            } else {
                model.selectTab(tab)
            }
        } label: {
            VStack(spacing: 2) {
                icon
                Text(tab.displayName)
                    .font(.system(size: 11))
            }
            .foregroundColor(model.selectedTab == tab ? model.currentTheme.primary : .secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// The symbol of the item and the badge of the books that wait for the
    /// update of their table of contents — upstream
    /// `MainActivity.kt:335-341` (the badge of the item 0).
    private var icon: some View {
        ZStack(alignment: .topTrailing) {
            Image(systemName: tab.systemImage)
                .font(.system(size: 20))
            if tab == .bookshelf, model.upBooksCount > 0 {
                Text("\(model.upBooksCount)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(3)
                    .background(Color.red)
                    .clipShape(Circle())
                    .offset(x: 10, y: -8)
            }
        }
    }
}
