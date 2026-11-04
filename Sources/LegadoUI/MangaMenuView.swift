//
//  MangaMenuView.swift
//  LegadoUI
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/MangaMenu.kt (the menu of the
//  manga reader: the toolbar opens the book info, the chapter name and the
//  address open the browser, the seek bar jumps to a page) and
//  app/src/main/java/io/legado/app/ui/book/manga/ReadMangaActivity.kt (the
//  menu entries of `res/menu/book_manga`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The menu of the manga reader — upstream `ui/book/read/MangaMenu.kt`.
public struct MangaMenuView: View {

    /// The controller of the manga reader.
    @ObservedObject var controller: MangaReaderController

    /// Called when the menu closes.
    var onClose: () -> Void
    /// Called when the book info is requested — upstream
    /// `MangaMenu.CallBack.openBookInfoActivity`.
    var onShowBookInfo: () -> Void

    public init(
        controller: MangaReaderController,
        onClose: @escaping () -> Void = {},
        onShowBookInfo: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self.onClose = onClose
        self.onShowBookInfo = onShowBookInfo
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            pageSlider
            chapterButtons
            brightnessSlider
            settingsSection
        }
        .padding(16)
        .background(Color.black.opacity(0.85))
        // The chapter name and the address open the browser — upstream
        // `MangaMenu.chapterViewClickListener`.
        .sheet(isPresented: $showsBrowser) {
            NavigationStack {
                InAppBrowserView(url: browserURL)
            }
        }
        .sheet(isPresented: $showsColorFilter) {
            MangaColorFilterSheet(controller: controller)
        }
        .sheet(isPresented: $showsFooterConfig) {
            MangaFooterConfigSheet(controller: controller)
        }
        .sheet(isPresented: $showsToc) {
            if let model = controller.model {
                NavigationStack {
                    TocView(model: model, book: controller.book) { index in
                        showsToc = false
                        Task { await controller.loadChapter(at: index) }
                    }
                }
            }
        }
    }

    /// Whether the in-app browser is shown.
    @State private var showsBrowser = false
    /// The address the built-in browser shows.
    @State private var browserURL = ""
    /// Whether the colour filter dialog is shown — upstream
    /// `MangaColorFilterDialog`.
    @State private var showsColorFilter = false
    /// Whether the footer configuration is shown — upstream
    /// `MangaFooterSettingDialog`.
    @State private var showsFooterConfig = false
    /// The pre-download count — upstream `AppConfig.mangaPreDownloadNum` (10).
    @State private var preDownloadNum: Int = 10
    /// The auto page speed — upstream `AppConfig.mangaAutoPageSpeed` (3 s).
    @State private var autoPageSpeed: Int = 3

    /// The toolbar row — upstream `MangaMenu.bindEvent`:
    /// the toolbar opens the book info, the chapter name and the address open
    /// the browser.
    private var header: some View {
        HStack(spacing: 12) {
            Button("书籍信息") {
                onShowBookInfo()
                onClose()
            }
            // The chapter name and the address — upstream
            // `MangaMenu.tvChapterName` / `MangaMenu.tvChapterUrl`.
            ChapterLinkView(
                title: controller.chapterTitle,
                url: controller.chapterURL,
                openInSystemBrowser: controller.environment.settings.bool(.readUrlOpenInBrowser, default: false),
                onOpenInApp: { url in
                    browserURL = url
                    showsBrowser = true
                },
                onChooseBrowser: { useSystemBrowser in
                    controller.environment.settings.set(useSystemBrowser, for: .readUrlOpenInBrowser)
                }
            )
            Spacer()
            Button("关闭") { onClose() }
        }
    }

    /// The page seek bar — upstream `seekReadPage` (`MangaMenu.upSeekBar`).
    private var pageSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(controller.pageText)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Slider(
                value: Binding(
                    get: { Double(controller.pageIndex) },
                    set: { controller.skipToPage(Int($0.rounded())) }
                ),
                in: 0...Double(max(0, controller.pageCount - 1))
            )
        }
    }

    /// The previous / the next chapter — upstream `tvPre` / `tvNext`.
    private var chapterButtons: some View {
        HStack {
            Button("上一章") {
                Task { await controller.moveToPrevChapter() }
                onClose()
            }
            Spacer()
            Button("下一章") {
                Task { await controller.moveToNextChapter() }
                onClose()
            }
        }
    }

    /// The brightness — upstream `MangaMenu.upBrightnessVwPos` (the same
    /// slider as the text reader uses).
    private var brightnessSlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("亮度")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Slider(
                value: Binding(
                    get: { Double(controller.brightnessPercent) },
                    set: { controller.setBrightness(percent: Int($0.rounded())) }
                ),
                in: 0...100
            )
        }
    }

    // MARK: - The manga settings

    /// The settings of the manga reader — upstream `res/menu/book_manga`
    /// (`ReadMangaActivity.onCompatOptionsItemSelected`).
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("设置")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            HStack {
                Button("换源") {
                    onShowBookInfo()
                    onClose()
                }
                Button("刷新") {
                    Task { await controller.reloadChapter() }
                }
                Button("目录") {
                    showsToc = true
                    onClose()
                }
            }
            Toggle("禁用缩放", isOn: settingBinding(.disableMangaScale))
            Toggle("禁用点击滚动", isOn: settingBinding(.disableClickScroll))
            Toggle("自动翻页", isOn: $isAutoPage)
            Toggle("自动滚动", isOn: $isAutoScroll)
            Toggle("横向滚动", isOn: settingBinding(.enableMangaHorizontalScroll))
            Toggle("禁用翻页动画", isOn: settingBinding(.disableMangaPageAnim))
            Toggle("隐藏标题", isOn: settingBinding(.hideMangaTitle))
            Toggle("电子墨水", isOn: settingBinding(.enableMangaEInk))
            Toggle("灰度", isOn: settingBinding(.enableMangaGray))
            Stepper("预下载数：\(preDownloadNum)", value: $preDownloadNum, in: 0...99)
            Stepper("自动翻页速度：\(autoPageSpeed)", value: $autoPageSpeed, in: 1...60)
            Button("页脚设置") {
                showsFooterConfig = true
            }
            Button("颜色滤镜") {
                showsColorFilter = true
            }
        }
        .onAppear {
            preDownloadNum = controller.environment.settings.int(.mangaPreDownloadNum, default: 10)
            autoPageSpeed = controller.environment.settings.int(.mangaAutoPageSpeed, default: 3)
        }
        .onChange(of: preDownloadNum) { _, value in
            controller.environment.settings.set(value, for: .mangaPreDownloadNum)
        }
        .onChange(of: autoPageSpeed) { _, value in
            controller.environment.settings.set(value, for: .mangaAutoPageSpeed)
        }
    }

    /// Whether the auto page is on — upstream `enableAutoScrollPage`.
    @State private var isAutoPage = false
    /// Whether the auto scroll is on — upstream `enableAutoScroll`.
    @State private var isAutoScroll = false
    /// Whether the chapter list is shown — upstream `menu_catalog`.
    @State private var showsToc = false

    /// A binding that reads and writes a boolean preference.
    private func settingBinding(_ key: SettingsKey) -> Binding<Bool> {
        Binding(
            get: { controller.environment.settings.bool(key, default: false) },
            set: { newValue in
                controller.environment.settings.set(newValue, for: key)
                controller.refreshDisplay()
            }
        )
    }
}
