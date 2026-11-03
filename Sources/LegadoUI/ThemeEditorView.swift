//
//  ThemeEditorView.swift
//  LegadoUI
//
//  The theme editor — upstream `res/xml/pref_config_theme.xml`.
//
//  The upstream lets the user edit the four colour keys (the primary, the
//  accent, the background and the bottom background) of the day and the night
//  theme, pick a background image and import / export the theme JSON.
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

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("主题") {
                TextField("名称", text: $themeName)
                Toggle("夜间主题", isOn: $isNightTheme)
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
    }

    private func load() {
        let theme = model.themeManager.currentTheme(isSystemDark: model.isSystemDark)
        themeName = theme.themeName
        primaryColor = theme.primaryColor
        accentColor = theme.accentColor
        backgroundColor = theme.backgroundColor
        bottomBackground = theme.bottomBackground
        isNightTheme = theme.isNightTheme
    }

    private func save() {
        let theme = AppTheme(
            themeName: themeName.isEmpty ? "自定义" : themeName,
            isNightTheme: isNightTheme,
            primaryColor: primaryColor,
            accentColor: accentColor,
            backgroundColor: backgroundColor,
            bottomBackground: bottomBackground
        )
        model.themeManager.add(theme)
        model.selectTheme(index: model.themeManager.themes.count - 1)
        message = "已保存"
    }

    private func exportTheme() {
        let theme = AppTheme(
            themeName: themeName.isEmpty ? "自定义" : themeName,
            isNightTheme: isNightTheme,
            primaryColor: primaryColor,
            accentColor: accentColor,
            backgroundColor: backgroundColor,
            bottomBackground: bottomBackground
        )
        importText = ThemeManager.exportJSON(theme)
        UIPasteboardShim.copy(importText)
        message = "已导出到剪贴板"
    }

    private func importTheme() {
        guard let theme = ThemeManager.importJSON(importText) else {
            message = "格式不对"
            return
        }
        model.themeManager.add(theme)
        model.selectTheme(index: model.themeManager.themes.count - 1)
        load()
        message = "已导入"
    }
}
