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
//  title of the chapter and to copy the content to the clipboard.
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

    /// The book the chapter belongs to.
    let book: Book
    /// The index of the chapter that is edited.
    let chapterIndex: Int
    /// The title of the chapter.
    @State private var title: String
    /// The content of the chapter.
    @State private var content: String
    /// Whether the content was loaded.
    @State private var isLoading = true
    /// The message of the last action.
    @State private var message: String?
    /// The callback that saves the chapter — it reloads the reader.
    let onSave: (String, String) -> Void

    public init(
        book: Book,
        chapterIndex: Int,
        chapterTitle: String,
        content: String,
        onSave: @escaping (String, String) -> Void
    ) {
        self.book = book
        self.chapterIndex = chapterIndex
        _title = State(wrappedValue: chapterTitle)
        _content = State(wrappedValue: content)
        self.onSave = onSave
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
                    onSave(title, content)
                }
                Button("复制") {
                    UIPasteboardShim.copy(content)
                    message = "已复制到剪贴板"
                }
                Spacer()
                if let message {
                    Text(message)
                        .font(.system(size: 12))
                }
            }
        }
        .padding(16)
        .navigationTitle("编辑内容")
    }
}
