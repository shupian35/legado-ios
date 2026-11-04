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
    /// The default cover that is being deleted — upstream
    /// `CoverConfigFragment.onPreferenceTreeClick` (the 删除 branch).
    @State private var deletingCover: DefaultCover?

    /// The two default covers of the app — upstream `PreferKey.defaultCover`
    /// and `PreferKey.defaultCoverDark`.
    enum DefaultCover: String, Identifiable {
        case day
        case night

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: return "日间封面"
            case .night: return "夜间封面"
            }
        }

        var pathKey: SettingsKey {
            switch self {
            case .day: return .defaultCover
            case .night: return .defaultCoverDark
            }
        }
    }

    public init(model: LegadoAppModel) {
        self.model = model
    }

    private var settings: AppSettings { model.environment.settings }

    public var body: some View {
        Form {
            Section("默认封面") {
                coverRow(.day)
                coverRow(.night)
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
                // Upstream `CoverConfigFragment.onCreatePreferences` — the
                // author toggle is only enabled when the name is shown.
                Toggle("显示作者", isOn: Binding(
                    get: { settings.bool(.coverShowAuthor, default: true) },
                    set: { settings.set($0, for: .coverShowAuthor) }
                ))
                .disabled(!settings.bool(.coverShowName, default: true))
                Toggle("夜间显示书名", isOn: Binding(
                    get: { settings.bool(.coverShowNameN, default: true) },
                    set: { settings.set($0, for: .coverShowNameN) }
                ))
                Toggle("夜间显示作者", isOn: Binding(
                    get: { settings.bool(.coverShowAuthorN, default: true) },
                    set: { settings.set($0, for: .coverShowAuthorN) }
                ))
                .disabled(!settings.bool(.coverShowNameN, default: true))
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
                store(url, for: .day)
            }
        }
        .fileImporter(isPresented: $isPickingDarkCover, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                store(url, for: .night)
            }
        }
        .alert(
            "删除封面",
            isPresented: Binding(
                get: { deletingCover != nil },
                set: { if !$0 { deletingCover = nil } }
            )
        ) {
            Button("取消", role: .cancel) {
                deletingCover = nil
            }
            Button("删除", role: .destructive) {
                if let cover = deletingCover {
                    let path = settings.string(cover.pathKey)
                    settings.set("", for: cover.pathKey)
                    LocalFileStore.removeFile(at: path)
                }
                deletingCover = nil
            }
        } message: {
            Text("确定要删除该封面吗？")
        }
    }

    /// The row of one of the two default covers.
    @ViewBuilder
    private func coverRow(_ cover: DefaultCover) -> some View {
        let path = settings.string(cover.pathKey) ?? ""
        if path.isEmpty {
            Button("选择\(cover.title)") {
                if cover == .day {
                    isPickingCover = true
                } else {
                    isPickingDarkCover = true
                }
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cover.title)
                        .font(.system(size: 15))
                    Text(path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    Button("重新选择") {
                        if cover == .day {
                            isPickingCover = true
                        } else {
                            isPickingDarkCover = true
                        }
                    }
                    Button("删除", role: .destructive) {
                        deletingCover = cover
                    }
                } label: {
                    Text("更多")
                        .font(.system(size: 13))
                }
            }
        }
    }

    /// Copies the picked image into the app's own directory and stores its
    /// path — upstream `CoverConfigFragment.setCoverFromUri` copies the file
    /// into `externalFiles/covers/<md5>.<suffix>`.
    private func store(_ url: URL, for cover: DefaultCover) {
        do {
            let path = try LocalFileStore.importFile(from: url, into: "covers")
            settings.set(path, for: cover.pathKey)
        } catch {
            model.errorMessage = error.localizedDescription
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
    /// The image that is being deleted — upstream `WelcomeConfigFragment`'s
    /// selector with 删除 / 选择图片.
    @State private var deletingImage: WelcomeImage?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    private var settings: AppSettings { model.environment.settings }

    /// The two images of the splash — upstream `PreferKey.welcomeImagePath`
    /// and `PreferKey.welcomeImagePathDark`.
    enum WelcomeImage: String, Identifiable {
        case day
        case night

        var id: String { rawValue }

        var title: String {
            switch self {
            case .day: return "日间启动图"
            case .night: return "夜间启动图"
            }
        }

        var pathKey: SettingsKey {
            switch self {
            case .day: return .welcomeImagePath
            case .night: return .welcomeImagePathDark
            }
        }

        /// The two switches that are reset when the image is deleted.
        var showTextKey: SettingsKey {
            switch self {
            case .day: return .welcomeShowText
            case .night: return .welcomeShowTextDark
            }
        }

        var showIconKey: SettingsKey {
            switch self {
            case .day: return .welcomeShowIcon
            case .night: return .welcomeShowIconDark
            }
        }
    }

    public var body: some View {
        Form {
            Section("启动图") {
                // Upstream `PreferKey.customWelcome` — the master switch of
                // the own splash image.
                Toggle("使用自定义启动图", isOn: Binding(
                    get: { settings.customWelcome },
                    set: { settings.customWelcome = $0 }
                ))
            }
            Section("日间") {
                imageRow(.day)
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
                imageRow(.night)
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
                store(url, for: .day)
            }
        }
        .fileImporter(isPresented: $isPickingDarkImage, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                store(url, for: .night)
            }
        }
        .alert(
            "删除启动图",
            isPresented: Binding(
                get: { deletingImage != nil },
                set: { if !$0 { deletingImage = nil } }
            )
        ) {
            Button("取消", role: .cancel) {
                deletingImage = nil
            }
            Button("删除", role: .destructive) {
                if let image = deletingImage {
                    remove(image)
                }
                deletingImage = nil
            }
        } message: {
            Text("确定要删除该启动图吗？")
        }
    }

    /// The row of one of the two images.
    @ViewBuilder
    private func imageRow(_ image: WelcomeImage) -> some View {
        let path = settings.string(image.pathKey) ?? ""
        if path.isEmpty {
            Button("选择\(image.title)") {
                if image == .day {
                    isPickingImage = true
                } else {
                    isPickingDarkImage = true
                }
            }
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(image.title)
                        .font(.system(size: 15))
                    Text(path)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    Button("重新选择") {
                        if image == .day {
                            isPickingImage = true
                        } else {
                            isPickingDarkImage = true
                        }
                    }
                    Button("删除", role: .destructive) {
                        deletingImage = image
                    }
                } label: {
                    Text("更多")
                        .font(.system(size: 13))
                }
            }
        }
    }

    /// Copies the picked image into the app's own directory and stores its
    /// path — the path of a picked file is temporary on iOS.
    private func store(_ url: URL, for image: WelcomeImage) {
        do {
            let path = try LocalFileStore.importFile(from: url, into: "welcome")
            settings.set(path, for: image.pathKey)
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }

    /// Deletes the image and resets its two switches — upstream
    /// `WelcomeConfigFragment.onPreferenceTreeClick` (the 删除 branch).
    private func remove(_ image: WelcomeImage) {
        let path = settings.string(image.pathKey)
        settings.set("", for: image.pathKey)
        LocalFileStore.removeFile(at: path)
        settings.set(true, for: image.showTextKey)
        settings.set(true, for: image.showIconKey)
    }
}
