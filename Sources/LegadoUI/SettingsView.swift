//
//  SettingsView.swift
//  LegadoUI
//
//  The settings tab — upstream `ui/settings/`.
//
//  The upstream settings are spread over many activities (the reading
//  settings, the backup settings, the WebDAV settings, the TTS settings).
//  The port groups them into one screen that writes the same preference keys,
//  so a backup made by either app restores into the other.
//
//  See `AppModel.swift` for the state.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#else
import LegadoUIShim
#endif

import LegadoCore

/// The settings tab.
public struct SettingsView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var isSourceManagerPresented = false
    @State private var isBackupPresented = false
    @State private var exportText: String = ""
    @State private var isExportPresented = false
    @State private var isFontImporterPresented = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    private var settings: AppSettings { model.environment.settings }

    public var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题", selection: Binding(
                        get: { model.themeMode },
                        set: { model.setThemeMode($0) }
                    )) {
                        ForEach(ThemeMode.allCases, id: \.rawValue) { mode in
                            Text(mode.name).tag(mode)
                        }
                    }
                    Picker("配色", selection: Binding(
                        get: { model.themeManager.selectedIndex },
                        set: { model.selectTheme(index: $0) }
                    )) {
                        ForEach(Array(model.themeManager.themes.enumerated()), id: \.offset) { index, theme in
                            Text(theme.themeName).tag(index)
                        }
                    }
                    Toggle("显示发现", isOn: Binding(
                        get: { settings.showDiscovery },
                        set: { settings.showDiscovery = $0 }
                    ))
                    Toggle("显示 RSS", isOn: Binding(
                        get: { settings.showRSS },
                        set: { settings.showRSS = $0 }
                    ))
                    NavigationLink("更换图标") {
                        LauncherIconPickerView(model: model)
                    }
                    NavigationLink("本地密码") {
                        LocalPasswordView(model: model)
                    }
                }

                Section("书架") {
                    Picker("排序", selection: Binding(
                        get: { settings.bookshelfSort },
                        set: { settings.bookshelfSort = $0 }
                    )) {
                        ForEach(BookshelfSort.allCases, id: \.rawValue) { sort in
                            Text(sort.name).tag(sort.rawValue)
                        }
                    }
                    Toggle("显示未读", isOn: Binding(
                        get: { settings.showUnread },
                        set: { settings.showUnread = $0 }
                    ))
                    Toggle("使用默认封面", isOn: Binding(
                        get: { settings.useDefaultCover },
                        set: { settings.useDefaultCover = $0 }
                    ))
                    Picker("布局", selection: Binding(
                        get: { settings.bookshelfLayout },
                        set: { settings.bookshelfLayout = $0 }
                    )) {
                        // Upstream: 0 = the list style, every other value is a
                        // grid with `bookshelfLayout + 2` columns.
                        Text("列表").tag(0)
                        Text("三列").tag(1)
                        Text("四列").tag(2)
                        Text("五列").tag(3)
                    }
                }

                // Upstream: the bookshelf menu (the group management, the
                // bookmarks) and the book's replace rules.
                Section("书架管理") {
                    NavigationLink("分组管理") {
                        BookGroupView(model: model)
                    }
                    NavigationLink("书签") {
                        BookmarkView(model: model)
                    }
                    NavigationLink("替换净化") {
                        ReplaceRuleView(model: model)
                    }
                }

                Section("阅读") {
                    Picker("字体大小", selection: Binding(
                        get: { settings.fontScalePreference },
                        set: { settings.fontScalePreference = $0 }
                    )) {
                        ForEach([8, 9, 10, 11, 12, 13, 14, 15, 16], id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    Toggle("全文两端对齐", isOn: Binding(
                        get: { settings.textFullJustify },
                        set: { settings.textFullJustify = $0 }
                    ))
                    Toggle("跟随系统朗读语速", isOn: Binding(
                        get: { settings.ttsFollowSys },
                        set: { settings.ttsFollowSys = $0 }
                    ))
                    // Upstream `ReadBookConfig.autoReadSpeed` — the seconds
                    // per page of the auto pager.
                    TextField("自动翻页间隔（秒）", text: Binding(
                        get: { String(settings.autoReadSpeed) },
                        set: { settings.autoReadSpeed = max(1, Int($0) ?? 10) }
                    ))
                    Button("选择字体文件") {
                        isFontImporterPresented = true
                    }
                    Text(settings.string(.fontFolder) ?? "使用系统字体")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Section("网络") {
                    TextField("User-Agent", text: Binding(
                        get: { settings.userAgent },
                        set: { settings.userAgent = $0 }
                    ))
                    Picker("线程数", selection: Binding(
                        get: { settings.threadCount },
                        set: { settings.threadCount = $0 }
                    )) {
                        ForEach([1, 2, 4, 8, 16, 32], id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    Toggle("启用本地服务", isOn: Binding(
                        get: { settings.webServiceEnabled },
                        set: { settings.webServiceEnabled = $0 }
                    ))
                    TextField("服务端口", text: Binding(
                        get: { String(settings.webPort) },
                        set: { settings.webPort = Int($0) ?? 1122 }
                    ))
                }

                Section("备份") {
                    Toggle("只保留最新备份", isOn: Binding(
                        get: { settings.onlyLatestBackup },
                        set: { settings.onlyLatestBackup = $0 }
                    ))
                    Toggle("导出时使用替换规则", isOn: Binding(
                        get: { settings.exportUseReplace },
                        set: { settings.exportUseReplace = $0 }
                    ))
                    Toggle("导出时不带章节名", isOn: Binding(
                        get: { settings.exportNoChapterName },
                        set: { settings.exportNoChapterName = $0 }
                    ))
                    Toggle("导出图片", isOn: Binding(
                        get: { settings.exportPictureFile },
                        set: { settings.exportPictureFile = $0 }
                    ))
                    Button("备份与恢复") {
                        isBackupPresented = true
                    }
                }

                Section("书源") {
                    Button("管理书源") {
                        isSourceManagerPresented = true
                    }
                    Button("导出书源") {
                        exportText = model.exportedSources()
                        isExportPresented = true
                    }
                }

                Section("高级") {
                    NavigationLink("全部设置") {
                        AdvancedSettingsView(model: model)
                    }
                    NavigationLink("直链上传") {
                        DirectLinkUploadConfigView(model: model)
                    }
                }

                // The upstream "我的" menu (`ui/main/MainActivity` → the
                // "More" popup) opens these screens.
                Section("更多") {
                    NavigationLink("TXT目录规则") {
                        TxtTocRuleView(model: model)
                    }
                    NavigationLink("字典规则") {
                        DictRuleView(model: model)
                    }
                    NavigationLink("阅读记录") {
                        ReadRecordView(model: model)
                    }
                    NavigationLink("HTTP TTS") {
                        HttpTTSView(model: model)
                    }
                    NavigationLink("文件管理") {
                        FileManageView(model: model)
                    }
                    NavigationLink("关于") {
                        AboutView(model: model)
                    }
                }

                Section("关于") {
                    Text("版本 \(LegadoAppInfo.version)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Text("上游包名 \(LegadoAppInfo.upstreamPackage)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $isSourceManagerPresented) {
                SourceManagerView(model: model)
            }
            .sheet(isPresented: $isExportPresented) {
                ScrollView {
                    Text(exportText)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
                .navigationTitle("导出书源")
            }
            .sheet(isPresented: $isBackupPresented) {
                NavigationStack {
                    BackupView(model: model)
                }
            }
            .fileImporter(
                isPresented: $isFontImporterPresented,
                allowedContentTypes: [.font],
                onCompletion: { result in
                    guard case let .success(url) = result else { return }
                    let path = url.path
                    guard FontResolver.isUsableFontPath(path) else {
                        model.errorMessage = "字体文件不可用"
                        return
                    }
                    FontLoader.register(fontPath: path)
                    settings.set(path, for: .fontFolder)
                }
            )
        }
    }
}
