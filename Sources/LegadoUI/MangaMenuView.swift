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
        }
        .padding(16)
        .background(Color.black.opacity(0.85))
        // The chapter name and the address open the browser — upstream
        // `MangaMenu.chapterViewClickListener`.
        .sheet(isPresented: $showsBrowser) {
            NavigationStack {
                InAppBrowserView(url: controller.chapterURL)
            }
        }
    }

    /// Whether the in-app browser is shown.
    @State private var showsBrowser = false

    /// The toolbar row — upstream `MangaMenu.bindEvent`:
    /// the toolbar opens the book info, the chapter name and the address open
    /// the browser.
    private var header: some View {
        HStack(spacing: 12) {
            Button("书籍信息") {
                onShowBookInfo()
                onClose()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.chapterTitle)
                    .font(.system(size: 15, weight: .semibold))
                Text(controller.chapterURL)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .onTapGesture { showsBrowser = true }
            }
            .onTapGesture { showsBrowser = true }
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
}
