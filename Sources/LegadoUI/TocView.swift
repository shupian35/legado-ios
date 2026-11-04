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
//  The chapter rows open the reader at that chapter (upstream
//  `ChapterListFragment.onChapterClick`), the bookmark rows open it at the
//  bookmark position (upstream `BookmarkFragment.onClick`), the current
//  chapter is highlighted (upstream `ChapterListAdapter.convert`) and the
//  title replace rules are applied to the chapter titles (upstream
//  `ChapterListAdapter.upDisplayTitles`).
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
    /// Called instead of opening a new reader when the table of contents is
    /// shown inside the reader (upstream `ReadMenu` opens the chapter list of
    /// the running reader).
    var onSelectChapter: ((Int) -> Void)?

    @State private var chapters: [BookChapter] = []
    @State private var bookmarks: [Bookmark] = []
    @State private var keyword = ""
    @State private var showsBookmarks = false
    @State private var message: String?
    /// The TOC rule picker — upstream `TxtTocRuleDialog`.
    @State private var isRulePickerPresented = false
    /// Whether the word count is shown — upstream `AppConfig.tocCountWords`.
    @State private var showsWordCount = false
    /// The display titles of the chapters (the replace rules are applied).
    @State private var displayTitles: [String: String] = [:]
    /// Whether the global "use the replace rules in the TOC" is on — upstream
    /// `AppConfig.tocUiUseReplace`.
    @State private var usesGlobalReplace = false

    public init(model: LegadoAppModel, book: Book, onSelectChapter: ((Int) -> Void)? = nil) {
        self.model = model
        self.book = book
        self.onSelectChapter = onSelectChapter
    }

    public var body: some View {
        List {
            if showsBookmarks {
                Section("书签") {
                    ForEach(filteredBookmarks, id: \.time) { bookmark in
                        Button {
                            openBookmark(bookmark)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.chapterName)
                                    .font(.system(size: 14))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("位置 \(bookmark.chapterPos)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            } else {
                if !chapters.isEmpty {
                    Section {
                        HStack {
                            Text("当前章节 \(currentChapterNumber)/\(chapters.count)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button("顶部") {
                                openChapter(index: 0)
                            }
                            .font(.system(size: 12))
                            Button("底部") {
                                openChapter(index: chapters.count - 1)
                            }
                            .font(.system(size: 12))
                        }
                    }
                }
                Section {
                    ForEach(filteredChapters, id: \.url) { chapter in
                        Button {
                            openChapter(index: Int(chapter.index))
                        } label: {
                            HStack {
                                Text(displayTitle(for: chapter))
                                    .font(.system(size: 14))
                                    .foregroundColor(chapter.index == book.durChapterIndex ? .accentColor : .primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if showsWordCount, let wordCount = chapter.wordCount, !wordCount.isEmpty {
                                    Text(wordCount)
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                // Upstream `ChapterListAdapter` — the update
                                // time rule writes the tag of a chapter; the
                                // tag is hidden for the volume chapters.
                                if !chapter.isVolume, let tag = chapter.tag, !tag.isEmpty {
                                    Text(tag)
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                // Upstream `ChapterListAdapter` — the lock of
                                // a VIP chapter that was not paid for.
                                if chapter.isVip && !chapter.isPay {
                                    Text("VIP")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                if chapter.isVolume {
                                    Text("卷")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                if hasCachedContent(chapter) {
                                    // Upstream `ChapterListAdapter.upHasCache`.
                                    Text("已缓存")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
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
        .searchable(text: $keyword, prompt: showsBookmarks ? "搜索书签" : "搜索目录")
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
                        // Upstream `TocActivity.menu_toc_regex` — the managed
                        // list of the TXT table of contents rules.
                        Button("目录正则") {
                            isRulePickerPresented = true
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
        .sheet(isPresented: $isRulePickerPresented) {
            TocRegexPickerView(model: model) { rule in
                applyRule(rule)
            }
        }
    }

    // MARK: - The data

    private var filteredChapters: [BookChapter] {
        TocOperations.filter(chapters: chapters, keyword: keyword)
    }

    private var filteredBookmarks: [Bookmark] {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return bookmarks }
        return bookmarks.filter {
            $0.chapterName.localizedCaseInsensitiveContains(keyword)
                || $0.content.localizedCaseInsensitiveContains(keyword)
        }
    }

    private var currentChapterNumber: Int {
        let index = Int(book.durChapterIndex) + 1
        return max(1, min(index, max(1, chapters.count)))
    }

    /// The display title of a chapter — the title replace rules are applied
    /// when the book uses them (upstream `ChapterListAdapter.upDisplayTitles`).
    private func displayTitle(for chapter: BookChapter) -> String {
        if let title = displayTitles[chapter.title] {
            return title
        }
        return chapter.title
    }

    /// Whether the content of a chapter is cached — upstream
    /// `ChapterListAdapter.upHasCache`.
    private func hasCachedContent(_ chapter: BookChapter) -> Bool {
        model.environment.cacheStorage?.hasContent(book: book, chapter: chapter) ?? false
    }

    // MARK: - The actions

    /// Opens the reader at a chapter — upstream
    /// `ChapterListFragment.onChapterClick`.
    private func openChapter(index: Int) {
        guard index >= 0 else { return }
        if let onSelectChapter {
            onSelectChapter(index)
            return
        }
        Task {
            await model.openReader(for: book, chapterIndex: index)
        }
    }

    /// Opens the reader at a bookmark — upstream `BookmarkFragment.onClick`.
    private func openBookmark(_ bookmark: Bookmark) {
        Task {
            await model.openReader(
                for: book,
                chapterIndex: Int(bookmark.chapterIndex),
                chapterPos: Int(bookmark.chapterPos)
            )
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
        usesGlobalReplace = model.environment.settings.bool(.tocUiUseReplace, default: false)
        reloadDisplayTitles()
    }

    /// Computes the display titles of the chapters — upstream
    /// `ChapterListAdapter.upDisplayTitles`.
    private func reloadDisplayTitles() {
        displayTitles = [:]
        guard book.useReplaceRule else { return }
        let rules = (try? model.environment.store.replaceRulesForTitle(
            name: book.name,
            origin: book.origin
        )) ?? []
        guard !rules.isEmpty else { return }
        for chapter in chapters {
            if let title = try? ReplaceRuleEngine.displayTitle(
                chapter,
                replaceRules: rules,
                useReplace: true,
                chineseConvert: false
            ) {
                displayTitles[chapter.title] = title
            }
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
        usesGlobalReplace.toggle()
        reloadDisplayTitles()
        message = changed.useReplaceRule ? "已使用替换规则" : "已关闭替换规则"
    }

    /// Exports the bookmarks — upstream `TocViewModel.saveBookmark`.
    ///
    /// The upstream writes a file into the download directory; the port writes
    /// it into the cache directory and copies the text to the pasteboard.
    private func exportBookmarks(asMarkdown: Bool) {
        let text = asMarkdown
            ? TocOperations.bookmarkMarkdown(book: book, bookmarks: bookmarks)
            : TocOperations.bookmarkJSON(book: book, bookmarks: bookmarks)
        let name = TocOperations.bookmarkFileName(book: book, fileExtension: asMarkdown ? "md" : "json")
        if let directory = model.environment.cacheStorage?.layout.root {
            let url = directory.appendingPathComponent(name)
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
                message = "已导出 \(name)"
            } catch {
                message = "导出失败：\(error.localizedDescription)"
            }
        } else {
            message = "已导出 \(name)（\(text.count) 字符）"
        }
        UIPasteboardShim.copy(text)
    }
}
