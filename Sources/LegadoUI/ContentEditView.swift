//
//  ContentEditView.swift
//  LegadoUI
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/ContentEditDialog.kt
//  (and app/src/main/java/io/legado/app/ui/book/read/ContentEditViewModel.kt).
//
//  The content editor of the reader: the content of the current chapter is
//  shown in an editable text view and saved back into the cache, so the
//  change survives the next reload. The upstream also offers to edit the
//  title of the chapter, to reset the content (delete the cache and
//  download the chapter again) and to copy the content to the clipboard.
//
//  The content that is shown is the PROCESSED text (the title is not
//  included — `ContentProcessor.getContent(..., includeTitle = false)`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The content editor — upstream `ContentEditDialog`.
public struct ContentEditView: View {

    /// The reader controller.
    @ObservedObject var controller: ReaderController

    /// The title of the chapter.
    @State private var title: String = ""
    /// The content of the chapter.
    @State private var content: String = ""
    /// Whether the content was loaded.
    @State private var isLoading = true
    /// Whether the reset is running.
    @State private var isResetting = false
    /// The message of the last action.
    @State private var message: String?

    public init(controller: ReaderController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("章节标题", text: $title)
            if isLoading {
                ProgressView("正在加载…")
            } else {
                TextEditor(text: $content)
            }
            HStack {
                Button("保存") {
                    controller.saveEditedContent(title: title, content: content)
                }
                // Upstream `menu_reset` — the cache is deleted and the
                // chapter is downloaded again.
                Button("重置") {
                    reset()
                }
                .disabled(isResetting)
                // Upstream `menu_copy_all`.
                Button("复制") {
                    UIPasteboardShim.copy(content)
                    message = "已复制到剪贴板"
                }
                Spacer()
                if isResetting {
                    ProgressView()
                }
                if let message {
                    Text(message)
                        .font(.system(size: 12))
                }
            }
        }
        .padding(16)
        .navigationTitle("编辑内容")
        .onAppear {
            load()
        }
    }

    /// Loads the content of the chapter — upstream
    /// `ContentEditViewModel.initContent`.
    private func load() {
        isLoading = true
        title = controller.currentChapterTitle
        content = controller.currentChapterContent
        isLoading = false
    }

    /// Deletes the cached content and downloads the chapter again — upstream
    /// `ContentEditViewModel.initContent(reset = true)`.
    private func reset() {
        isResetting = true
        Task {
            await controller.resetEditedContent()
            load()
            isResetting = false
        }
    }
}
