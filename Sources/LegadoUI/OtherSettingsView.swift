#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

#if canImport(WebKit)
import WebKit
#endif

import Foundation
import LegadoCore

/// The "其它设置" screen — the port of
/// `app/src/main/java/io/legado/app/ui/config/OtherConfigFragment.kt`
/// (`res/xml/pref_config_other.xml`).
///
/// The upstream uses the Android preference framework (number pickers, folder
/// pickers and action preferences); the port reproduces the same items with
/// the SwiftUI equivalents. The Android-only entries (Cronet, the process-text
/// intent, the heap-dump recording) are not ported — see the deviations.
public struct OtherSettingsView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var isSelectingBookFolder = false
    @State private var isClearingWebData = false
    @State private var isShrinkingDatabase = false
    @State private var status: String?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    private var settings: AppSettings { model.environment.settings }

    public var body: some View {
        NavigationStack {
            Form {
                mainSection
                otherSection
                maintenanceSection
                if let status {
                    Section {
                        Text(status)
                            .font(.system(size: 13))
                    }
                }
            }
            .navigationTitle("其它设置")
        }
        .fileImporter(
            isPresented: $isSelectingBookFolder,
            allowedContentTypes: [.folder]
        ) { result in
            if case let .success(url) = result {
                settings.defaultBookTreeUri = url.path
                status = "默认书籍目录：\(url.lastPathComponent)"
            }
        }
        .confirmationDialog("确定删除?", isPresented: $isClearingWebData) {
            Button("清除网页数据") { clearWebViewData() }
            Button("取消", role: ButtonRole.cancel) {}
        }
        .confirmationDialog("确定?", isPresented: $isShrinkingDatabase) {
            Button("压缩数据库") { shrinkDatabase() }
            Button("取消", role: ButtonRole.cancel) {}
        }
    }

    // MARK: - The main interface

    private var mainSection: some View {
        Section("主界面") {
            Toggle("自动刷新", isOn: Binding(
                get: { settings.autoRefreshBook },
                set: { settings.autoRefreshBook = $0 }
            ))
            Toggle("默认阅读", isOn: Binding(
                get: { settings.defaultToRead },
                set: { settings.defaultToRead = $0 }
            ))
            Toggle("显示发现", isOn: Binding(
                get: { settings.showDiscovery },
                set: { settings.showDiscovery = $0 }
            ))
            Toggle("显示RSS", isOn: Binding(
                get: { settings.showRSS },
                set: { settings.showRSS = $0 }
            ))
            Picker("默认首页", selection: Binding(
                get: { settings.homePage },
                set: { settings.homePage = $0 }
            )) {
                // Upstream `MainActivity.upHomePage()` knows the four values
                // "bookshelf", "explore", "rss" and "my".
                ForEach(HomePage.allCases.filter {
                    $0.isVisible(showDiscovery: settings.showDiscovery, showRSS: settings.showRSS)
                }) { page in
                    Text(page.displayName).tag(page)
                }
            }
        }
    }

    // MARK: - The other settings

    private var otherSection: some View {
        Section("其它设置") {
            HStack {
                Text("语言")
                Spacer()
                Text(settings.language.isEmpty ? "跟随系统" : settings.language)
                    .foregroundColor(.secondary)
            }
            TextField("用户代理", text: Binding(
                get: { settings.userAgent },
                set: { settings.userAgent = $0 }
            ))
            Toggle("Web服务唤醒锁", isOn: Binding(
                get: { settings.webServiceWakeLock },
                set: { settings.webServiceWakeLock = $0 }
            ))
            Button("默认书籍目录") {
                isSelectingBookFolder = true
            }
            if !settings.defaultBookTreeUri.isEmpty {
                Text(settings.defaultBookTreeUri)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Stepper(
                "书源编辑最大行数：\(settings.sourceEditMaxLine)",
                value: Binding(
                    get: { settings.sourceEditMaxLine },
                    set: { settings.sourceEditMaxLine = $0 }
                ),
                in: 10...5000
            )
            NavigationLink("检查书源") {
                SourceCheckConfigView(model: model)
            }
            NavigationLink("直链上传规则") {
                DirectLinkUploadConfigView(model: model)
            }
            Toggle("抗锯齿", isOn: Binding(
                get: { settings.useAntiAlias },
                set: { settings.useAntiAlias = $0 }
            ))
            Stepper(
                "图片缓存大小：\(settings.bitmapCacheSize) MB",
                value: Binding(
                    get: { settings.bitmapCacheSize },
                    set: { settings.bitmapCacheSize = $0 }
                ),
                in: 1...1024
            )
            Stepper(
                "图片保留数：\(settings.imageRetainNum)",
                value: Binding(
                    get: { settings.imageRetainNum },
                    set: { settings.imageRetainNum = $0 }
                ),
                in: 0...999
            )
            Stepper(
                "预下载数：\(settings.preDownloadNumber)",
                value: Binding(
                    get: { settings.preDownloadNumber },
                    set: { settings.preDownloadNumber = $0 }
                ),
                in: 0...9999
            )
            Toggle("默认替换规则", isOn: Binding(
                get: { settings.replaceEnableDefault },
                set: { settings.replaceEnableDefault = $0 }
            ))
            Toggle("朗读由媒体键控制", isOn: Binding(
                get: { settings.readAloudByMediaButton },
                set: { settings.readAloudByMediaButton = $0 }
            ))
            Toggle("忽略音频焦点", isOn: Binding(
                get: { settings.ignoreAudioFocus },
                set: { settings.ignoreAudioFocus = $0 }
            ))
            Toggle("自动清除过期缓存", isOn: Binding(
                get: { settings.autoClearExpired },
                set: { settings.autoClearExpired = $0 }
            ))
            Toggle("加入书架时提示", isOn: Binding(
                get: { settings.showAddToShelfAlert },
                set: { settings.showAddToShelfAlert = $0 }
            ))
            Toggle("显示漫画界面", isOn: Binding(
                get: { settings.showMangaUi },
                set: { settings.showMangaUi = $0 }
            ))
            Stepper(
                "Web服务端口：\(settings.webPort)",
                value: Binding(
                    get: { settings.webPort },
                    set: { settings.webPort = $0 }
                ),
                in: 1024...60000
            )
            Stepper(
                "线程数：\(settings.threadCount)",
                value: Binding(
                    get: { settings.threadCount },
                    set: { settings.threadCount = $0 }
                ),
                in: 1...999
            )
            Toggle("记录日志", isOn: Binding(
                get: { settings.recordLog },
                set: { settings.recordLog = $0 }
            ))
        }
    }

    // MARK: - The maintenance actions

    private var maintenanceSection: some View {
        Section("数据") {
            ClearCacheButton(model: model)
            Button("清除网页数据") {
                isClearingWebData = true
            }
            Button("压缩数据库") {
                isShrinkingDatabase = true
            }
        }
    }

    // MARK: - The actions

    /// Removes the cookies and the web view data — upstream
    /// `ConfigViewModel.clearWebViewData()`.
    private func clearWebViewData() {
        model.environment.cookieStore.removeAllCookies()
        #if canImport(WebKit)
        if #available(iOS 11.0, macOS 10.13, *) {
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            WKWebsiteDataStore.default().removeData(
                ofTypes: types,
                modifiedSince: Date.distantPast
            ) { }
        }
        #endif
        status = "网页数据已清除"
    }

    /// Compacts the database file — upstream
    /// `ConfigViewModel.shrinkDatabase()` → `execSQL("VACUUM")`.
    private func shrinkDatabase() {
        do {
            try model.environment.store.shrinkDatabase()
            status = "数据库已压缩"
        } catch {
            status = "压缩失败：\(error.localizedDescription)"
        }
    }
}
