//
//  ThemeListView.swift
//  LegadoUI
//
//  The list of the themes — upstream `ui/config/ThemeListDialog.kt`.
//
//  The upstream shows the themes of `ThemeConfig.configList`, applies the
//  theme the user taps (`ThemeConfig.applyConfig`), shares it, deletes it and
//  imports a theme from the clipboard (`ThemeConfig.addConfig`).
//
//  See `AppModel.swift` for the state.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The list of the themes — upstream `ThemeListDialog`.
public struct ThemeListView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var message: String?
    @State private var isDeletePresented = false
    @State private var deletingIndex: Int = 0
    @State private var isSharePresented = false
    @State private var shareText: String = ""
    @State private var importText: String = ""
    /// The name of the theme that is saved — upstream `saveDayTheme` /
    /// `saveNightTheme` ask for a name.
    @State private var saveName: String = ""

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section("主题列表") {
                if model.themeManager.themes.isEmpty {
                    Text("还没有主题")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(model.themeManager.themes.enumerated()), id: \.offset) { entry in
                        themeRow(entry.offset, theme: entry.element)
                    }
                }
            }
            Section("导入") {
                TextEditor(text: $importText)
                    .frame(minHeight: 100)
                Button("导入") {
                    importTheme()
                }
                // Upstream `ThemeListDialog.onMenuItemClick` — the import
                // reads the clipboard (`Context.getClipText()`).
                Button("从剪贴板导入") {
                    importFromClipboard()
                }
            }
            // Upstream `ThemeConfigFragment` — the menu entries
            // `saveDayTheme` and `saveNightTheme` save the current colours
            // under a new name.
            Section("保存当前主题") {
                TextField("主题名称", text: $saveName)
                Button("保存日间主题") {
                    saveTheme(isNight: false)
                }
                Button("保存夜间主题") {
                    saveTheme(isNight: true)
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
        .navigationTitle("主题列表")
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(items: [shareText])
        }
        .alert("删除主题", isPresented: $isDeletePresented) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                deleteTheme()
            }
        } message: {
            Text("确定删除这个主题吗？")
        }
    }

    /// One theme of the list — upstream `ThemeListDialog` L95-118.
    private func themeRow(_ index: Int, theme: AppTheme) -> some View {
        HStack(spacing: 12) {
            Button {
                // Upstream `ThemeConfig.applyConfig` (L169-191).
                model.selectTheme(index: index)
                message = "已应用 \(theme.themeName)"
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(theme.themeName)
                        .font(.system(size: 15))
                    Text(theme.primaryColor)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if index == model.themeManager.selectedIndex {
                Text("当前")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            // Upstream `ivShare` — the theme is shared as JSON.
            Button("分享") {
                shareText = ThemeManager.exportJSON(theme)
                isSharePresented = true
            }
            .font(.system(size: 12))
            // Upstream `ivDelete`.
            Button("删除", role: .destructive) {
                deletingIndex = index
                isDeletePresented = true
            }
            .font(.system(size: 12))
        }
        .padding(.vertical, 4)
    }

    /// Deletes the theme — upstream `ThemeConfig.delConfig` (L114-117).
    private func deleteTheme() {
        let theme = model.themeManager.themes[deletingIndex]
        model.deleteTheme(index: deletingIndex)
        message = "已删除 \(theme.themeName)"
    }

    /// Imports a theme — upstream `ThemeConfig.addConfig` (L119-142): a theme
    /// with the same name replaces the old one.
    private func importTheme() {
        guard let theme = ThemeManager.importJSON(importText) else {
            message = "格式不对,添加失败"
            return
        }
        guard model.addTheme(theme) else {
            message = "格式不对,添加失败"
            return
        }
        importText = ""
        message = "已导入 \(theme.themeName)"
    }

    /// Saves the current colours under a new name — upstream
    /// `ThemeConfig.saveDayTheme` / `ThemeConfig.saveNightTheme`.
    private func saveTheme(isNight: Bool) {
        let name = saveName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            message = "请输入主题名称"
            return
        }
        let colors = model.environment.settings.themeColors(isNight: isNight)
        guard model.themeManager.saveCurrentTheme(
            name: name,
            isNightTheme: isNight,
            colors: colors
        ) else {
            message = "格式不对,添加失败"
            return
        }
        saveName = ""
        message = "已保存 \(name)"
    }

    /// Imports the theme of the clipboard — upstream
    /// `ThemeListDialog.onMenuItemClick` (L58-71).
    private func importFromClipboard() {
        let text = UIPasteboardShim.string()
        guard !text.isEmpty else {
            message = "剪贴板是空的"
            return
        }
        importText = text
        importTheme()
    }
}
