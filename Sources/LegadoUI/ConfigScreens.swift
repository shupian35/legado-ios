//
//  ConfigScreens.swift
//  LegadoUI
//
//  The configuration screens of the upstream `ui/config/`:
//
//  - `CoverConfigFragment` — the default covers and the generated cover.
//  - `CoverRuleConfigDialog` — the rule that searches the cover of a book.
//  - `WelcomeConfigFragment` — the images and the switches of the welcome
//    screen.
//
//  The upstream opens them from the preference screens; the port opens them
//  from the settings tab and from the advanced settings.
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

import Foundation
import LegadoCore

// MARK: - The cover configuration

/// The cover configuration — upstream `CoverConfigFragment`.
public struct CoverConfigView: View {

    @ObservedObject var model: LegadoAppModel

    /// Whether the image picker is shown.
    @State private var isPickingCover = false
    /// Whether the dark image picker is shown.
    @State private var isPickingDarkCover = false
    /// Whether the cover rule sheet is shown.
    @State private var isCoverRulePresented = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    private var settings: AppSettings { model.environment.settings }

    public var body: some View {
        Form {
            Section("默认封面") {
                Button("选择日间封面") {
                    isPickingCover = true
                }
                Text(settings.string(.defaultCover) ?? "未设置")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Button("选择夜间封面") {
                    isPickingDarkCover = true
                }
                Text(settings.string(.defaultCoverDark) ?? "未设置")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Toggle("使用默认封面", isOn: Binding(
                    get: { settings.useDefaultCover },
                    set: { settings.useDefaultCover = $0 }
                ))
                Toggle("仅在 Wi-Fi 下加载封面", isOn: Binding(
                    get: { settings.loadCoverOnlyWifi },
                    set: { settings.loadCoverOnlyWifi = $0 }
                ))
            }
            Section("生成封面") {
                Toggle("显示书名", isOn: Binding(
                    get: { settings.bool(.coverShowName, default: true) },
                    set: { settings.set($0, for: .coverShowName) }
                ))
                Toggle("显示作者", isOn: Binding(
                    get: { settings.bool(.coverShowAuthor, default: true) },
                    set: { settings.set($0, for: .coverShowAuthor) }
                ))
                Toggle("夜间显示书名", isOn: Binding(
                    get: { settings.bool(.coverShowNameN, default: true) },
                    set: { settings.set($0, for: .coverShowNameN) }
                ))
                Toggle("夜间显示作者", isOn: Binding(
                    get: { settings.bool(.coverShowAuthorN, default: true) },
                    set: { settings.set($0, for: .coverShowAuthorN) }
                ))
            }
            Section("封面搜索") {
                NavigationLink("封面规则") {
                    CoverRuleConfigView(model: model)
                }
            }
        }
        .navigationTitle("封面设置")
        .fileImporter(isPresented: $isPickingCover, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                settings.set(url.path, for: .defaultCover)
            }
        }
        .fileImporter(isPresented: $isPickingDarkCover, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                settings.set(url.path, for: .defaultCoverDark)
            }
        }
    }
}

/// The cover rule — upstream `CoverRuleConfigDialog`.
public struct CoverRuleConfigView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var isEnabled = false
    @State private var searchUrl = ""
    @State private var coverRule = ""
    @State private var message = ""

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("封面规则") {
                Toggle("启用", isOn: $isEnabled)
                TextField("搜索url", text: $searchUrl)
                TextField("cover规则", text: $coverRule)
            }
            Section {
                Button("保存") {
                    save()
                }
                Button("删除", role: .destructive) {
                    delete()
                }
                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("封面规则")
        .onAppear { load() }
    }

    private func load() {
        let config = BookCoverService.config(store: model.environment.store)
        isEnabled = config.enable
        searchUrl = config.searchUrl
        coverRule = config.coverRule
    }

    private func save() {
        // Upstream: the search URL and the rule may not be empty.
        guard !searchUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !coverRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "搜索url和cover规则不能为空"
            return
        }
        let config = CoverRule(
            enable: isEnabled,
            searchUrl: searchUrl,
            coverRule: coverRule
        )
        do {
            try BookCoverService.save(config, store: model.environment.store)
            message = "已保存"
        } catch {
            message = "保存失败：\(error.localizedDescription)"
        }
    }

    private func delete() {
        do {
            try BookCoverService.delete(store: model.environment.store)
            isEnabled = false
            searchUrl = ""
            coverRule = ""
            message = "已删除"
        } catch {
            message = "删除失败：\(error.localizedDescription)"
        }
    }
}

// MARK: - The welcome configuration

/// The welcome screen configuration — upstream `WelcomeConfigFragment`.
public struct WelcomeConfigView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var isPickingImage = false
    @State private var isPickingDarkImage = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    private var settings: AppSettings { model.environment.settings }

    public var body: some View {
        Form {
            Section("启动图") {
                Button("选择启动图") {
                    isPickingImage = true
                }
                Text(settings.string(.welcomeImagePath) ?? "未设置")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Button("选择夜间启动图") {
                    isPickingDarkImage = true
                }
                Text(settings.string(.welcomeImagePathDark) ?? "未设置")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Section("日间") {
                Toggle("显示文字", isOn: Binding(
                    get: { settings.bool(.welcomeShowText, default: true) },
                    set: { settings.set($0, for: .welcomeShowText) }
                ))
                .disabled((settings.string(.welcomeImagePath) ?? "").isEmpty)
                Toggle("显示图标", isOn: Binding(
                    get: { settings.bool(.welcomeShowIcon, default: true) },
                    set: { settings.set($0, for: .welcomeShowIcon) }
                ))
                .disabled((settings.string(.welcomeImagePath) ?? "").isEmpty)
            }
            Section("夜间") {
                Toggle("显示文字", isOn: Binding(
                    get: { settings.bool(.welcomeShowTextDark, default: true) },
                    set: { settings.set($0, for: .welcomeShowTextDark) }
                ))
                .disabled((settings.string(.welcomeImagePathDark) ?? "").isEmpty)
                Toggle("显示图标", isOn: Binding(
                    get: { settings.bool(.welcomeShowIconDark, default: true) },
                    set: { settings.set($0, for: .welcomeShowIconDark) }
                ))
                .disabled((settings.string(.welcomeImagePathDark) ?? "").isEmpty)
            }
        }
        .navigationTitle("启动页样式")
        .fileImporter(isPresented: $isPickingImage, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                settings.set(url.path, for: .welcomeImagePath)
            }
        }
        .fileImporter(isPresented: $isPickingDarkImage, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                settings.set(url.path, for: .welcomeImagePathDark)
            }
        }
    }
}
