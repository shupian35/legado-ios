//
//  TocView.swift
//  LegadoUI
//
//  The table-of-contents screen — upstream `ui/book/toc/TocActivity.kt`.
//
//  The upstream screen has two tabs (the chapters and the bookmarks), a
//  search field and the menu entries: the TOC regex (local TXT books), the
//  split of the long chapters, the reverse, the use of the replace rules,
//  the word count, the bookmark export (JSON / Markdown) and the log.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The table-of-contents screen.
public struct TocView: View {

    @ObservedObject var model: LegadoAppModel
    let book: Book

    @State private var chapters: [BookChapter] = []
    @State private var bookmarks: [Bookmark] = []
    @State private var keyword = ""
    @State private var showsBookmarks = false
    @State private var message: String?
    /// The TOC rule editor — upstream `TxtTocRuleDialog`.
    @State private var isRuleEditorPresented = false
    /// The rule that is being edited.
    @State private var ruleText = ""
    /// Whether the word count is shown — upstream `AppConfig.tocCountWords`.
    @State private var showsWordCount = false

    public init(model: LegadoAppModel, book: Book) {
        self.model = model
        self.book = book
    }

    public var body: some View {
        List {
            if showsBookmarks {
                Section("书签") {
                    ForEach(bookmarks, id: \.time) { bookmark in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bookmark.chapterName)
                            Text("位置 \(bookmark.chapterPos)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            } else {
                Section {
                    ForEach(TocOperations.filter(chapters: chapters, keyword: keyword), id: \.url) { chapter in
                        HStack {
                            Text(chapter.title)
                                .font(.system(size: 14))
                            Spacer()
                            if showsWordCount, let wordCount = chapter.wordCount, !wordCount.isEmpty {
                                Text(wordCount)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            if chapter.isVolume {
                                Text("卷")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
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
        .navigationTitle("目录")
        .searchable(text: $keyword, prompt: "搜索目录")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(showsBookmarks ? "章节" : "书签") {
                    showsBookmarks.toggle()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    // Upstream `TocViewModel.reverseToc`.
                    Button("反转目录") {
                        reverseToc()
                    }
                    Button("使用替换") {
                        toggleReplaceRule()
                    }
                    if book.isLocalTxt {
                        // Upstream `TocActivity.menu_toc_regex`.
                        Button("目录正则") {
                            ruleText = book.tocUrl
                            isRuleEditorPresented = true
                        }
                        // Upstream `TocActivity.menu_split_long_chapter`.
                        Button(book.readConfigBox.splitLongChapter ? "取消分割长章节" : "分割长章节") {
                            toggleSplitLongChapter()
                        }
                    }
                    // Upstream `TocActivity.menu_load_word_count`.
                    Button(showsWordCount ? "隐藏字数" : "显示字数") {
                        showsWordCount.toggle()
                    }
                    Button("导出书签") {
                        exportBookmarks(asMarkdown: false)
                    }
                    Button("导出书签(Markdown)") {
                        exportBookmarks(asMarkdown: true)
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            reload()
        }
        .sheet(isPresented: $isRuleEditorPresented) {
            NavigationStack {
                TocRuleEditorView(rule: ruleText) { rule in
                    applyRule(rule)
                }
            }
        }
    }

    /// Applies a new TOC rule — upstream `TocViewModel.upBookTocRule`.
    private func applyRule(_ rule: String) {
        guard let fileURL = model.localImporter?.fileURL(for: book) else {
            message = "找不到本地文件"
            return
        }
        do {
            let result = try TocOperations.reparse(
                book: book,
                rule: rule,
                fileURL: fileURL,
                splitLongChapter: book.readConfigBox.splitLongChapter
            )
            var changed = book
            changed.tocUrl = result.rule
            changed.totalChapterNum = Int64(result.chapters.count)
            changed.wordCount = TextFormat.wordCountFormat(result.wordCount)
            try? model.environment.store.update(changed)
            try? model.environment.store.deleteChapters(bookUrl: book.bookUrl)
            try? model.environment.store.insert(result.chapters)
            reload()
            message = "已更新目录"
        } catch {
            message = "目录规则无效"
        }
    }

    /// Toggles the split of the long chapters — upstream
    /// `Book.setSplitLongChapter`.
    private func toggleSplitLongChapter() {
        let enabled = !book.readConfigBox.splitLongChapter
        let changed = TocOperations.setSplitLongChapter(enabled, book: book)
        try? model.environment.store.update(changed)
        if enabled, let fileURL = model.localImporter?.fileURL(for: book) {
            try? applyRule(book.tocUrl)
        }
        message = enabled ? "已分割长章节" : "已取消分割长章节"
    }

    private func reload() {
        chapters = (try? model.environment.chapters(of: book)) ?? []
        bookmarks = model.bookmarks.filter {
            $0.bookName == book.name && $0.bookAuthor == book.author
        }
    }

    /// Upstream `TocViewModel.reverseToc` — the flag is flipped, the
    /// chapters are reversed and re-indexed.
    private func reverseToc() {
        var changed = book
        changed.reverseToc.toggle()
        try? model.environment.store.update(changed)
        let reversed = TocOperations.reverse(chapters: chapters)
        try? model.environment.store.deleteChapters(bookUrl: book.bookUrl)
        try? model.environment.store.insert(reversed)
        reload()
        message = "已反转目录"
    }

    private func toggleReplaceRule() {
        var changed = book
        changed.useReplaceRule.toggle()
        try? model.environment.store.update(changed)
        message = changed.useReplaceRule ? "已使用替换规则" : "已关闭替换规则"
    }

    private func exportBookmarks(asMarkdown: Bool) {
        let text = asMarkdown
            ? TocOperations.bookmarkMarkdown(book: book, bookmarks: bookmarks)
            : TocOperations.bookmarkJSON(book: book, bookmarks: bookmarks)
        let name = TocOperations.bookmarkFileName(book: book, fileExtension: asMarkdown ? "md" : "json")
        message = "已导出 \(name)（\(text.count) 字符）"
        UIPasteboardShim.copy(text)
    }
}

/// The TOC rule editor — upstream `ui/book/toc/rule/TxtTocRuleDialog.kt`.
///
/// The rule is a regular expression with the named groups `chapterName` and
/// `chapterUrl`; the port uses the same form.
struct TocRuleEditorView: View {

    @Environment(\.dismiss) private var dismiss

    @State var rule: String
    let onSave: (String) -> Void

    init(rule: String, onSave: @escaping (String) -> Void) {
        self._rule = State(initialValue: rule)
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 12) {
            Text("目录规则是一个正则，需要包含 chapterName 和 chapterUrl 两个命名分组。")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextEditor(text: $rule)
                .font(.system(size: 13))
                .frame(minHeight: 120)
                .border(Color.gray.opacity(0.3))
            Spacer()
        }
        .padding(16)
        .navigationTitle("目录正则")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("保存") {
                    onSave(rule)
                    dismiss()
                }
            }
        }
    }
}
