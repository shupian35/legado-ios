//
//  ThemeEditorView.swift
//  LegadoUI
//
//  The theme editor — upstream `res/xml/pref_config_theme.xml` and
//  `ui/config/ThemeConfigFragment.kt`.
//
//  The upstream lets the user edit the four colour keys (the primary, the
//  accent, the background and the bottom background) of the day and the night
//  theme, pick a background image (with a blur radius) and import / export
//  the theme JSON. The list of the themes lives in `ThemeListDialog.kt`
//  (`ThemeListView.swift`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The theme editor.
public struct ThemeEditorView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var themeName = ""
    @State private var primaryColor = ""
    @State private var accentColor = ""
    @State private var backgroundColor = ""
    @State private var bottomBackground = ""
    @State private var isNightTheme = false
    @State private var message: String?
    @State private var importText = ""
    /// The background image of the shell — upstream `PreferKey.bgImage` /
    /// `bgImageN` and `bgImageBlurring` / `bgImageNBlurring`.
    @State private var isPickingDayImage = false
    @State private var isPickingNightImage = false
    @State private var dayBlurring: Double = 0
    @State private var nightBlurring: Double = 0

    public init(model: LegadoAppModel) {
        self.model = model
    }

    private var settings: AppSettings { model.environment.settings }

    /// The font scale as a text — upstream `ThemeConfigFragment` shows the
    /// effective scale (`AppContextWrapper.getFontScale`).
    private var fontScaleText: String {
        let preference = settings.fontScalePreference
        guard preference != 0 else { return "跟随系统" }
        return String(format: "%.1f", Double(preference) / 10.0)
    }

    public var body: some View {
        Form {
            // Upstream `ThemeConfigFragment.onPreferenceTreeClick` — the
            // "themeList" preference opens the list of the themes.
            Section("主题") {
                NavigationLink("主题列表") {
                    ThemeListView(model: model)
                }
            }
            // Upstream `pref_config_theme.xml` — the category "dayThemeCategory".
            Section("日间") {
                TextField("主色", text: colorBinding(.colorPrimary, fallback: ThemeColors.dayDefault.primary))
                TextField("强调色", text: colorBinding(.colorAccent, fallback: ThemeColors.dayDefault.accent))
                TextField("背景色", text: colorBinding(.colorBackground, fallback: ThemeColors.dayDefault.background))
                TextField("底部背景", text: colorBinding(.colorBottomBackground, fallback: ThemeColors.dayDefault.bottomBackground))
                backgroundImageSection(isNight: false)
                Button("保存日间主题") {
                    saveTheme(isNight: false)
                }
            }
            // Upstream `pref_config_theme.xml` — the category "nightThemeCategory".
            Section("夜间") {
                TextField("主色", text: colorBinding(.colorPrimaryNight, fallback: ThemeColors.nightDefault.primary))
                TextField("强调色", text: colorBinding(.colorAccentNight, fallback: ThemeColors.nightDefault.accent))
                TextField("背景色", text: colorBinding(.colorBackgroundNight, fallback: ThemeColors.nightDefault.background))
                TextField("底部背景", text: colorBinding(.colorBottomBackgroundNight, fallback: ThemeColors.nightDefault.bottomBackground))
                backgroundImageSection(isNight: true)
                Button("保存夜间主题") {
                    saveTheme(isNight: true)
                }
            }
            Section("名称") {
                TextField("名称", text: $themeName)
                Toggle("夜间主题", isOn: $isNightTheme)
            }
            // Upstream `ThemeConfigFragment.onPreferenceTreeClick` — the
            // `barElevation` and the `fontScale` number pickers.
            Section("外观") {
                Stepper("工具栏高度：\(settings.barElevation)", value: Binding(
                    get: { settings.barElevation },
                    set: { settings.barElevation = $0 }
                ), in: 0...32)
                Button("重置工具栏高度") {
                    settings.barElevation = 4
                }
                Stepper("字体缩放：\(fontScaleText)", value: Binding(
                    get: { settings.fontScalePreference },
                    set: { settings.fontScalePreference = $0 }
                ), in: 8...16)
                Button("重置字体缩放") {
                    settings.fontScalePreference = 0
                }
            }
            Section("颜色") {
                TextField("主色", text: $primaryColor)
                TextField("强调色", text: $accentColor)
                TextField("背景色", text: $backgroundColor)
                TextField("底部背景", text: $bottomBackground)
            }
            Section {
                Button("保存") {
                    save()
                }
                Button("导出") {
                    exportTheme()
                }
            }
            Section("导入") {
                TextEditor(text: $importText)
                    .frame(minHeight: 100)
                Button("导入") {
                    importTheme()
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
        .navigationTitle("主题编辑")
        .onAppear {
            load()
        }
        .fileImporter(isPresented: $isPickingDayImage, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                pickBackgroundImage(url, isNight: false)
            }
        }
        .fileImporter(isPresented: $isPickingNightImage, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                pickBackgroundImage(url, isNight: true)
            }
        }
    }

    // MARK: - The colours

    /// The binding of a colour preference — the colours are stored as
    /// integers (upstream `putPrefInt`) and shown as `#RRGGBB`.
    private func colorBinding(_ key: SettingsKey, fallback: String) -> Binding<String> {
        Binding(
            get: {
                let value = settings.int(key, default: ThemeColors.intValue(fallback) ?? 0)
                return ThemeColors.hexValue(value)
            },
            set: { newValue in
                if let value = ThemeColors.intValue(newValue) {
                    settings.set(value, for: key)
                }
            }
        )
    }

    // MARK: - The background image

    /// The background image of the day or the night theme — upstream
    /// `ThemeConfigFragment.selectBgAction`: the image, the blur radius and
    /// the delete action.
    @ViewBuilder
    private func backgroundImageSection(isNight: Bool) -> some View {
        let path = isNight ? (settings.nightBackgroundImagePath ?? "") : (settings.dayBackgroundImagePath ?? "")
        Button(isNight ? "选择夜间背景图片" : "选择背景图片") {
            if isNight {
                isPickingNightImage = true
            } else {
                isPickingDayImage = true
            }
        }
        if !path.isEmpty {
            Text(path)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Slider(
                value: Binding(
                    get: { Double(isNight ? settings.nightBackgroundImageBlurring : settings.dayBackgroundImageBlurring) },
                    set: { newValue in
                        if isNight {
                            settings.nightBackgroundImageBlurring = Int(newValue)
                        } else {
                            settings.dayBackgroundImageBlurring = Int(newValue)
                        }
                    }
                ),
                in: 0...25,
                step: 1
            )
            Button("删除背景图片", role: .destructive) {
                if isNight {
                    settings.nightBackgroundImagePath = nil
                    settings.nightBackgroundImageBlurring = 0
                } else {
                    settings.dayBackgroundImagePath = nil
                    settings.dayBackgroundImageBlurring = 0
                }
            }
        }
    }

    /// Copies the picked image into the container of the application — upstream
    /// `ThemeConfigFragment.setBgFromUri` (the image is stored in
    /// `externalFiles/bg/<key>`).
    private func pickBackgroundImage(_ url: URL, isNight: Bool) {
        let name = isNight ? "backgroundImageNight" : "backgroundImage"
        guard let destination = copyIntoDocuments(url, name: name) else {
            message = "复制图片失败"
            return
        }
        if isNight {
            settings.nightBackgroundImagePath = destination
        } else {
            settings.dayBackgroundImagePath = destination
        }
        message = "已设置背景图片"
    }

    /// Copies a file into `<documents>/bg/<name>.<extension>`.
    private func copyIntoDocuments(_ url: URL, name: String) -> String? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = documents.appendingPathComponent("bg", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let destination = folder.appendingPathComponent("\(name).\(ext)")
        try? FileManager.default.removeItem(at: destination)
        do {
            try FileManager.default.copyItem(at: url, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }

    // MARK: - The theme list

    private func load() {
        let theme = model.themeManager.currentTheme(isSystemDark: model.isSystemDark)
        themeName = theme.themeName
        primaryColor = theme.primaryColor
        accentColor = theme.accentColor
        backgroundColor = theme.backgroundColor
        bottomBackground = theme.bottomBackground
        isNightTheme = theme.isNightTheme
    }

    /// The theme of the form.
    private var theme: AppTheme {
        AppTheme(
            themeName: themeName.isEmpty ? "自定义" : themeName,
            isNightTheme: isNightTheme,
            primaryColor: primaryColor,
            accentColor: accentColor,
            backgroundColor: backgroundColor,
            bottomBackground: bottomBackground
        )
    }

    /// Saves the theme — upstream `ThemeConfig.addConfig` (L119-142): a theme
    /// with the same name replaces the old one.
    private func save() {
        guard model.addTheme(theme) else {
            message = "格式不对,添加失败"
            return
        }
        model.selectTheme(index: model.themeManager.themes.count - 1)
        message = "已保存"
    }

    /// Saves the current colours under a new name — upstream
    /// `ThemeConfig.saveDayTheme` / `saveNightTheme`: the colours of the
    /// preferences are copied into a new entry of the list.
    private func saveTheme(isNight: Bool) {
        let name = themeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            message = "请输入主题名称"
            return
        }
        let colors = settings.themeColors(isNight: isNight)
        guard model.themeManager.saveCurrentTheme(
            name: name,
            isNightTheme: isNight,
            colors: colors
        ) else {
            message = "格式不对,添加失败"
            return
        }
        message = "已保存 \(name)"
    }

    private func exportTheme() {
        importText = ThemeManager.exportJSON(theme)
        UIPasteboardShim.copy(importText)
        message = "已导出到剪贴板"
    }

    private func importTheme() {
        guard let theme = ThemeManager.importJSON(importText) else {
            message = "格式不对,添加失败"
            return
        }
        guard model.addTheme(theme) else {
            message = "格式不对,添加失败"
            return
        }
        model.selectTheme(index: model.themeManager.themes.count - 1)
        load()
        message = "已导入"
    }
}
