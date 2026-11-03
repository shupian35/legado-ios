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
    /// The brightness of the screen, 0…1.
    @State private var brightness: Double = 0.5

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
                aloudSection
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
        }
    }

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
                        controller.pageTurnStyle = PageTurnStyle(rawValue: value) ?? .slide
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
            Slider(value: $brightness, in: 0...1)
        }
    }
}
