//
//  ReaderMenuView.swift
//  LegadoUI
//
//  The reader menu — upstream `ui/book/read/ReadMenu.kt`.
//
//  The upstream menu is a slide-in panel with the title bar (the book name,
//  the chapter name, the previous/next buttons), the page seek bar, the
//  brightness slider and the bottom bar (the auto page, the replace rules, the
//  chapter list, the search, the source edit, the book info, the read style,
//  the read aloud and the more settings). The port keeps the same entries in
//  a sheet, because a slide-in panel does not fit the SwiftUI reader.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The reader menu.
public struct ReaderMenuView: View {

    @ObservedObject var controller: ReaderController
    @ObservedObject var readAloud: ReadAloudService

    /// Whether the chapter list is shown.
    @State private var isChapterListPresented = false
    /// Whether the effective replace rules are shown — upstream
    /// `ReadBookActivity.menu_effectiveReplaceRules`.
    @State private var isEffectiveRulesPresented = false
    /// Whether the change source screen is shown — upstream
    /// `ReadBookActivity.menu_changeSource`.
    @State private var isChangeSourcePresented = false
    /// Whether the read-aloud settings are shown — upstream
    /// `ReadAloudDialog`.
    @State private var isAloudSettingsPresented = false
    /// Whether the simulated reading is shown — upstream
    /// `ReadBookActivity.menu_simulated_reading`.
    @State private var isSimulatedReadingPresented = false
    /// Whether the table of contents rule picker is shown — upstream
    /// `ReadBookActivity.menu_toc_regex`.
    @State private var isTocRegexPresented = false
    /// Whether the character set is shown — upstream
    /// `ReadBookActivity.menu_set_charset`.
    @State private var isCharsetPresented = false
    /// Whether the offline cache dialog is shown — upstream
    /// `ReadBookActivity.menu_download`.
    @State private var isDownloadPresented = false
    /// Whether the app log is shown — upstream `ReadBookActivity.menu_log`.
    @State private var isLogPresented = false
    /// Whether the reader help is shown — upstream `ReadBookActivity.menu_help`.
    @State private var isHelpPresented = false
    /// Whether the source editor is shown — upstream
    /// `ReadBookActivity.menu_edit_source`.
    @State private var isSourceEditorPresented = false
    /// The character set that the user picked.
    @State private var charset = ""
    /// Closes the sheet.
    @Environment(\.dismiss) private var dismissAction

    public init(controller: ReaderController) {
        self.controller = controller
        self.readAloud = controller.readAloud
    }

    public var body: some View {
        NavigationStack {
            Form {
                progressSection
                chapterSection
                styleSection
                backgroundSection
                aloudSection
                sourceSection
                moreSection
                brightnessSection
            }
            .navigationTitle(controller.book.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismissAction()
                    }
                }
            }
            .sheet(isPresented: $isEffectiveRulesPresented) {
                effectiveRules
            }
            .sheet(isPresented: $isChangeSourcePresented) {
                if let model = controller.model {
                    NavigationStack {
                        ChangeSourceView(model: model, book: controller.book)
                    }
                }
            }
            .sheet(isPresented: $isAloudSettingsPresented) {
                NavigationStack {
                    ReaderAloudDialogView(controller: controller)
                }
            }
            .sheet(isPresented: $isSimulatedReadingPresented) {
                NavigationStack {
                    SimulatedReadingView(book: controller.book) { config in
                        controller.setSimulatedReading(config)
                        isSimulatedReadingPresented = false
                    }
                }
            }
            .sheet(isPresented: $isCharsetPresented) {
                NavigationStack {
                    charsetSheet
                }
            }
            .sheet(isPresented: $isTocRegexPresented) {
                if let model = controller.model {
                    TocRegexPickerView(model: model) { rule in
                        isTocRegexPresented = false
                        Task { await controller.applyTocRegex(rule) }
                    }
                }
            }
            .sheet(isPresented: $isDownloadPresented) {
                if let model = controller.model {
                    NavigationStack {
                        ReaderDownloadDialog(model: model, book: controller.book)
                    }
                }
            }
            .sheet(isPresented: $isLogPresented) {
                NavigationStack {
                    AppLogView()
                }
            }
            .sheet(isPresented: $isHelpPresented) {
                NavigationStack {
                    ReaderHelpView()
                }
            }
            .sheet(isPresented: $isSourceEditorPresented) {
                if let model = controller.model, let source = source {
                    NavigationStack {
                        SourceEditorView(model: model, source: source)
                    }
                }
            }
        }
    }

    /// The source the book came from — upstream `ReadBook.bookSource`.
    private var source: BookSource? {
        guard let model = controller.model else { return nil }
        return try? model.environment.source(for: controller.book)
    }

    /// The character set of a local book — upstream
    /// `BaseReadBookActivity.showCharsetConfig()`.
    private var charsetSheet: some View {
        Form {
            Section("常用编码") {
                ForEach(ReaderMenuView.charsets, id: \.self) { value in
                    Button(value) {
                        controller.setCharset(value)
                        isCharsetPresented = false
                    }
                }
            }
            Section("自定义") {
                TextField("charset", text: $charset)
                Button("确定") {
                    let value = charset.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { return }
                    controller.setCharset(value)
                    isCharsetPresented = false
                }
            }
        }
        .navigationTitle("切换编码")
    }

    /// The character sets offered by the upstream's filter.
    static let charsets = [
        "UTF-8", "UTF-16", "GBK", "GB2312", "GB18030", "BIG5",
        "ISO-8859-1", "Shift_JIS", "EUC-JP", "EUC-KR", "KOI8-R", "MacRoman"
    ]

    // MARK: - The sections

    /// The page seek bar — upstream `binding.seekReadPage`.
    private var progressSection: some View {
        Section {
            VStack(alignment: .leading) {
                Text("\(controller.chapterIndex + 1) / \(controller.chapters.count)")
                    .font(.system(size: 12))
                Slider(
                    value: Binding(
                        get: { Double(controller.pageIndex) },
                        set: { controller.jump(toPage: Int($0)) }
                    ),
                    in: 0...Double(max(0, controller.pageSize - 1))
                )
                Text("本章 \(controller.pageIndex + 1) / \(max(1, controller.pageSize)) 页")
                    .font(.system(size: 12))
            }
        }
    }

    /// The chapter list — upstream `openChapterList`.
    private var chapterSection: some View {
        Section("章节") {
            Button("目录") {
                isChapterListPresented = true
            }
            Button("上一章") {
                Task { await controller.jump(toChapter: controller.chapterIndex - 1) }
            }
            .disabled(controller.chapterIndex <= 0)
            Button("下一章") {
                Task { await controller.jump(toChapter: controller.chapterIndex + 1) }
            }
            .disabled(controller.chapterIndex >= controller.chapters.count - 1)
        }
        .sheet(isPresented: $isChapterListPresented) {
            NavigationStack {
                List(controller.chapters, id: \.url) { chapter in
                    Button {
                        Task {
                            if let index = controller.chapters.firstIndex(where: { $0.url == chapter.url }) {
                                await controller.jump(toChapter: index)
                            }
                        }
                        isChapterListPresented = false
                    } label: {
                        Text(chapter.title)
                            .font(.system(size: 14))
                    }
                }
                .navigationTitle("目录")
            }
        }
    }

    /// The read style — upstream `showReadStyle()` (the font size, the spacing
    /// and the page-turn animation).
    private var styleSection: some View {
        Section("阅读设置") {
            Stepper(
                value: Binding(
                    get: { controller.config.textSize },
                    set: { value in
                        Task { await controller.updateReaderStyle { $0.textSize = value } }
                    }
                ),
                in: 10.0...40.0,
                step: 1
            ) {
                Text("字号 \(Int(controller.config.textSize))")
            }
            Stepper(
                value: Binding(
                    get: { controller.config.titleSize },
                    set: { value in
                        Task { await controller.updateReaderStyle { $0.titleSize = value } }
                    }
                ),
                in: 10.0...40.0,
                step: 1
            ) {
                Text("标题字号 \(Int(controller.config.titleSize))")
            }
            Stepper(
                value: Binding(
                    get: { controller.config.lineSpacingExtra },
                    set: { value in
                        Task { await controller.updateReaderStyle { $0.lineSpacingExtra = value } }
                    }
                ),
                in: 0.0...30.0,
                step: 1
            ) {
                Text("行距 \(Int(controller.config.lineSpacingExtra))")
            }
            Stepper(
                value: Binding(
                    get: { controller.config.paragraphSpacing },
                    set: { value in
                        Task { await controller.updateReaderStyle { $0.paragraphSpacing = value } }
                    }
                ),
                in: 0.0...30.0,
                step: 1
            ) {
                Text("段距 \(Int(controller.config.paragraphSpacing))")
            }
            Picker(
                "翻页动画",
                selection: Binding(
                    get: { controller.pageTurnStyle.rawValue },
                    set: { value in
                        controller.setPageTurnStyle(PageTurnStyle(rawValue: value) ?? .slide)
                    }
                )
            ) {
                ForEach(PageTurnStyle.allCases, id: \.rawValue) { style in
                    Text(style.name).tag(style.rawValue)
                }
            }
            Toggle(
                "两端对齐",
                isOn: Binding(
                    get: { controller.config.textFullJustify },
                    set: { value in
                        Task { await controller.updateReaderStyle { $0.textFullJustify = value } }
                    }
                )
            )
            Toggle(
                "自动翻页",
                isOn: Binding(
                    get: { controller.isAutoPaging },
                    set: { _ in controller.toggleAutoPage() }
                )
            )
        }
    }

    /// The background — upstream `ReadStyleDialog` (the style list, the
    /// background colour, the text colour and the opacity) and
    /// `ReadBookConfig.changeBgTextConfig`.
    private var backgroundSection: some View {
        Section("背景") {
            if !controller.backgroundPresets.isEmpty {
                Picker(
                    "样式",
                    selection: Binding(
                        get: { controller.backgroundStyleIndex },
                        set: { value in
                            Task { await controller.selectBackgroundPreset(index: value) }
                        }
                    )
                ) {
                    ForEach(Array(controller.backgroundPresets.enumerated()), id: \.offset) { index, preset in
                        Text(preset.name.isEmpty ? "样式 \(index + 1)" : preset.name)
                            .tag(index)
                    }
                }
            }
            ReaderColorRows(
                config: Binding(
                    get: { controller.config },
                    set: { value in
                        Task { await controller.updateReaderStyle { $0 = value } }
                    }
                )
            )
            Picker(
                "繁简转换",
                selection: Binding(
                    get: { controller.configStore.chineseConverterType },
                    set: { value in
                        Task {
                            await controller.setChineseConverter(
                                ChineseConversionMode(rawValue: value) ?? .off
                            )
                        }
                    }
                )
            ) {
                ForEach(ChineseConversionMode.allCases, id: \.rawValue) { mode in
                    Text(ReaderConverterRow.name(of: mode)).tag(mode.rawValue)
                }
            }
        }
    }

    /// The read aloud — upstream `showReadAloudDialog()`.
    private var aloudSection: some View {
        Section("朗读") {
            Button(readAloud.state == .playing ? "暂停朗读" : "开始朗读") {
                Task { await controller.startReadAloud() }
            }
            Button("上一段") {
                readAloud.previousParagraph()
            }
            .disabled(readAloud.state == .stopped)
            Button("下一段") {
                readAloud.nextParagraph()
            }
            .disabled(readAloud.state == .stopped)
            Button("停止朗读") {
                readAloud.stop()
            }
            .disabled(readAloud.state == .stopped)
        }
    }

    /// The brightness — upstream `binding.seekBrightness` (the screen
    /// brightness, not the reader background).
    private var brightnessSection: some View {
        Section("亮度") {
            Slider(
                value: Binding(
                    get: { Double(controller.system.brightnessPercent) / 100.0 },
                    set: { value in
                        // The screen brightness is a main-actor API on Apple;
                        // the hop keeps the call valid on every platform.
                        Task { @MainActor in
                            controller.system.setBrightness(percent: Int((value * 100).rounded()))
                        }
                    }
                ),
                in: 0...1
            )
            Text("\(controller.system.brightnessPercent) %")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - The upstream top bar options

    /// The source actions — upstream `res/menu/book_read_source.xml`
    /// (`menu_login`, `menu_chapter_pay`, `menu_edit_source`,
    /// `menu_disable_source`).
    private var sourceSection: some View {
        Section("书源") {
            if let source {
                // Upstream `ReadBookActivity.showLogin()` — the login of the
                // source of the book.
                Button("登录") {
                    controller.model?.presentLogin(for: source)
                }
                // Upstream `ReadBookActivity.payAction()` — the purchase of the
                // current chapter.
                Button("章节购买") {
                    Task { await controller.payChapter() }
                }
                // Upstream `ReadBookActivity.openSourceEditActivity()`.
                Button("编辑书源") {
                    isSourceEditorPresented = true
                }
                // Upstream `ReadBookActivity.disableSource()`.
                Button("禁用书源") {
                    controller.model?.setSource(source, enabled: false)
                }
            }
        }
    }

    /// The options of the upstream's `res/menu/book_read.xml` that the port
    /// can offer.
    private var moreSection: some View {
        Section("更多") {
            // Upstream `ReadMenu.menu_search_content` — the search of the
            // content of the book.
            Button("搜索正文") {
                controller.isSearchPresented = true
                dismissAction()
            }
            // Upstream `ReadBookActivity.menu_updateToc`.
            Button("更新目录") {
                Task { await controller.checkForNewChapters() }
            }
            // Upstream `ReadBookActivity.menu_refresh` — the content of the
            // current chapter is fetched again.
            Button("刷新本章") {
                controller.refreshCurrentContent()
            }
            // Upstream `ReadBookActivity.menu_refresh_after` — the content of
            // the chapters after the current one.
            Button("刷新后续") {
                controller.refreshContentAfter()
            }
            // Upstream `ReadBookActivity.menu_refresh_all` — the content of
            // the whole book.
            Button("刷新全部") {
                controller.refreshAllContent()
            }
            // Upstream `ReadBookActivity.menu_replaceRuleState` — the
            // "启用替换净化" switch.
            Toggle(
                "启用替换净化",
                isOn: Binding(
                    get: { controller.book.useReplaceRule },
                    set: { _ in controller.toggleReplaceRule() }
                )
            )
            // Upstream `ReadBookActivity.menu_effectiveReplaceRules`.
            Button("有效替换规则") {
                isEffectiveRulesPresented = true
            }
            // Upstream `ReadBookActivity.menu_changeSource`.
            Button("换源") {
                isChangeSourcePresented = true
            }
            // Upstream `ReadBookActivity.menu_addBookmark`.
            Button("添加书签") {
                Task { await controller.addCurrentBookmark() }
            }
            // Upstream `ReadMenu.menu_nightMode` — the night palette of the
            // reader.
            Toggle(
                "夜间模式",
                isOn: Binding(
                    get: { controller.systemNightMode },
                    set: { controller.systemNightMode = $0 }
                )
            )
            // Upstream `AutoReadDialog` — the seconds per page.
            Stepper(
                value: Binding(
                    get: { Double(controller.autoPager.configuration.speed) },
                    set: { value in
                        var configuration = controller.autoPager.configuration
                        configuration.speed = Int(value)
                        controller.autoPager.configuration = configuration
                    }
                ),
                in: 1.0...60.0,
                step: 1
            ) {
                Text("自动翻页间隔 \(controller.autoPager.configuration.speed) 秒")
            }
            // Upstream `ReadAloudDialog` — the speech rate, the timer and
            // the HTTP TTS engines.
            Button("朗读设置") {
                isAloudSettingsPresented = true
            }
            // Upstream `ReadBookActivity.menu_simulated_reading`.
            Button("模拟阅读") {
                isSimulatedReadingPresented = true
            }
            // Upstream `ReadBookActivity.menu_toc_regex` — the managed list of
            // the TXT table of contents rules.
            if controller.book.isLocalTxt {
                Button("目录正则") {
                    isTocRegexPresented = true
                }
            }
            // Upstream `ReadBookActivity.menu_set_charset` — the character
            // set of a local book.
            Button("切换编码") {
                charset = controller.book.charset ?? ""
                isCharsetPresented = true
            }
            // Upstream `ReadBookActivity.menu_re_segment`.
            Toggle(
                "重新分段",
                isOn: Binding(
                    get: { controller.book.reSegment },
                    set: { _ in controller.toggleReSegment() }
                )
            )
            // Upstream `ReadBookActivity.menu_del_ruby_tag` /
            // `menu_del_h_tag` — the tags removed from the content.
            Toggle(
                "删除ruby标签",
                isOn: Binding(
                    get: { controller.book.hasDelTag(BookTag.rubyTag.rawValue) },
                    set: { _ in controller.toggleDelTag(BookTag.rubyTag.rawValue) }
                )
            )
            Toggle(
                "删除h标签",
                isOn: Binding(
                    get: { controller.book.hasDelTag(BookTag.hTag.rawValue) },
                    set: { _ in controller.toggleDelTag(BookTag.hTag.rawValue) }
                )
            )
            // Upstream `ReadBookActivity.menu_same_title_removed`.
            Toggle(
                "移除相同标题",
                isOn: Binding(
                    get: { controller.removesSameTitle },
                    set: { _ in controller.toggleSameTitleRemoved() }
                )
            )
            // Upstream `ReadBookActivity.menu_reverse_content` — the
            // paragraphs of the current chapter are reversed.
            Button("反转正文") {
                controller.reverseCurrentContent()
            }
            // Upstream `ReadBookActivity.menu_image_style`.
            Picker(
                "图片样式",
                selection: Binding(
                    get: { controller.imageStyle.rawValue },
                    set: { value in
                        if let style = BookImageStyle(rawValue: value) {
                            controller.setImageStyle(style)
                        }
                    }
                )
            ) {
                ForEach(BookImageStyle.allCases) { style in
                    Text(style.displayName).tag(style.rawValue)
                }
            }
            // Upstream `ReadBookActivity.menu_edit_content` — the content
            // editor of the current chapter.
            Button("编辑内容") {
                controller.isContentEditPresented = true
                dismissAction()
            }
            // Upstream `ReadBookActivity.menu_get_progress` — the reading
            // progress is fetched from the WebDAV server.
            Button("获取进度") {
                Task { await controller.fetchRemoteProgress() }
            }
            // Upstream `ReadBookActivity.menu_cover_progress` — the local
            // progress overwrites the one of the WebDAV server.
            Button("覆盖进度") {
                Task { await controller.uploadProgress() }
            }
            // Upstream `ReadBookActivity.menu_download` — the offline cache.
            Button("离线缓存") {
                isDownloadPresented = true
            }
            // Upstream `ReadBookActivity.menu_log` — the app log.
            Button("日志") {
                isLogPresented = true
            }
            // Upstream `ReadBookActivity.menu_help` — the reader help.
            Button("帮助") {
                isHelpPresented = true
            }
        }
    }

    /// The replace rules that are applied to the current chapter — upstream
    /// `ReadBookActivity.menu_effectiveReplaceRules`.
    private var effectiveRules: some View {
        NavigationStack {
            List {
                let rules = controller.effectiveReplaceRules
                if rules.isEmpty {
                    Text("没有生效的替换规则")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(rules, id: \.id) { rule in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rule.name)
                                .font(.system(size: 14))
                            Text("\(rule.pattern) → \(rule.replacement)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("有效替换规则")
        }
    }
}
