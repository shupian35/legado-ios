//
//  BookDetailView.swift
//  LegadoUI
//
//  The detail page of a book — upstream `ui/book/info/BookInfoActivity.kt`.
//
//  It shows the cover, the title, the author, the source, the introduction
//  and the table of contents, and it can refresh the information and the
//  chapter list from the book source.
//
//  See `AppModel.swift` for the state.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The detail page of a book.
public struct BookDetailView: View {

    @ObservedObject var model: LegadoAppModel
    let book: Book

    @State private var chapters: [BookChapter] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isChangeSourcePresented = false
    @State private var isContentSearchPresented = false
    @State private var isBookInfoPresented = false
    @State private var isTocPresented = false
    @State private var isGroupPickerPresented = false
    @State private var isSharePresented = false
    /// The confirmation of the upload to the WebDAV server — upstream
    /// `BookInfoActivity.menu_upload`.
    @State private var isUploadConfirmed = false
    /// Whether the log is shown — upstream `BookInfoActivity.menu_log`.
    @State private var isLogPresented = false
    /// Whether the book is on the shelf.
    @State private var isOnShelf = false
    /// The groups the book is in.
    @State private var groupMask: Int64 = 0
    /// The book that is displayed — the store can update it.
    @State private var current: Book

    /// Whether the book is being cached (upstream `CacheBook`).
    private var isCaching: Bool {
        let progress = model.cacheProgress[book.bookUrl]
        return (progress?.downloading ?? 0) + (progress?.waiting ?? 0) > 0
    }

    public init(model: LegadoAppModel, book: Book) {
        self.model = model
        self.book = book
        self._current = State(initialValue: book)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                info
                if let intro = current.customIntro ?? current.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                chapterList
                if let progress = model.cacheProgress[book.bookUrl], progress.succeeded > 0 {
                    Text(progress.summary)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }
            .padding(16)
        }
        .navigationTitle(current.name)
        .refreshable {
            await refresh()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("阅读") {
                    openReader()
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    // Upstream `BookInfoActivity` — the book information
                    // menu (the metadata, the share, the pin, the delete).
                    Button("书籍信息") {
                        isBookInfoPresented = true
                    }
                    // Upstream `BookInfoActivity.menu_refresh` — the book
                    // information is loaded again from the source.
                    Button("刷新") {
                        Task { await refresh() }
                    }
                    // Upstream `BookInfoActivity.menu_login` — the login of
                    // the source of the book.
                    if let source = source {
                        Button("登录") {
                            model.presentLogin(for: source)
                        }
                    }
                    Button(isOnShelf ? "移出书架" : "加入书架") {
                        toggleShelf()
                    }
                    // Upstream `BookInfoActivity.menu_change_group`.
                    Button("换分组") {
                        isGroupPickerPresented = true
                    }
                    Button("换源") {
                        isChangeSourcePresented = true
                    }
                    Button("搜索正文") {
                        isContentSearchPresented = true
                    }
                    // Upstream `TocActivity` — the full table of contents
                    // screen with the bookmarks and the reverse.
                    Button("目录") {
                        isTocPresented = true
                    }
                    // Upstream `CacheBook.start` — the offline download of the
                    // whole book.
                    Button(isCaching ? "停止缓存" : "缓存本书") {
                        if isCaching {
                            Task { await model.stopCaching(book: current) }
                        } else {
                            Task { await model.startCaching(book: current) }
                        }
                    }
                    // Upstream `MainViewModel.updateToc` — the button is
                    // called 更新目录 (检查更新 is the app-version check).
                    Button("更新目录") {
                        Task { await model.updateBook(current) }
                    }
                    // Upstream `BookInfoActivity.menu_copy_toc_url` — the
                    // address of the table of contents.
                    Button("复制目录链接") {
                        UIPasteboardShim.copy(current.tocUrl)
                    }
                    // Upstream `BookInfoActivity.menu_copy_book_url`.
                    Button("复制书籍地址") {
                        UIPasteboardShim.copy(current.bookUrl)
                    }
                    // Upstream `BookInfoActivity.menu_clear_cache`.
                    Button("清除缓存") {
                        model.environment.cacheStorage?.clearCache(book: current)
                        model.reloadBookshelf()
                    }
                    // Upstream `BookInfoActivity.menu_can_update` — the book
                    // may be updated automatically.
                    Button(current.canUpdate ? "禁止更新" : "允许更新") {
                        toggleCanUpdate()
                    }
                    // Upstream `BookInfoActivity.menu_upload` — the local
                    // books are uploaded to the WebDAV server.
                    if BookType.contains(current.type, BookType.local) {
                        Button("上传到远程") {
                            isUploadConfirmed = true
                        }
                    }
                    // Upstream `BookInfoActivity.menu_split_long_chapter` —
                    // only for the local TXT books.
                    if isLocalTxt {
                        Button(current.readConfigBox.splitLongChapter ? "取消分割长章节" : "分割长章节") {
                            toggleSplitLongChapter()
                        }
                    }
                    // Upstream `BookInfoActivity.menu_delete_alert` — whether
                    // the book is deleted after a confirmation.
                    Button(model.environment.localConfig.bookInfoDeleteAlert ? "取消删除提示" : "删除提示") {
                        let value = !model.environment.localConfig.bookInfoDeleteAlert
                        model.environment.localConfig.bookInfoDeleteAlert = value
                    }
                    // Upstream `BookInfoActivity.menu_log` — the log of the
                    // app.
                    Button("日志") {
                        isLogPresented = true
                    }
                    // Upstream `BookInfoActivity.menu_share` — the upstream
                    // shares `${bookUrl}#$bookJson`.
                    Button("分享") {
                        isSharePresented = true
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isChangeSourcePresented) {
            NavigationStack {
                ChangeSourceView(model: model, book: current)
            }
        }
        .sheet(isPresented: $isContentSearchPresented) {
            NavigationStack {
                ContentSearchView(model: model, book: current)
            }
        }
        .sheet(isPresented: $isBookInfoPresented) {
            NavigationStack {
                BookInfoMenuView(model: model, book: current)
            }
        }
        .sheet(isPresented: $isTocPresented) {
            NavigationStack {
                TocView(model: model, book: current)
            }
        }
        .sheet(isPresented: $isGroupPickerPresented) {
            NavigationStack {
                GroupPickerSheet(groups: model.groups, selected: groupMask) { groupId in
                    moveToGroup(groupId)
                }
            }
        }
        .sheet(isPresented: $isSharePresented) {
            ShareSheet(items: [shareText])
        }
        .sheet(isPresented: $isLogPresented) {
            NavigationStack {
                AppLogView()
            }
        }
        .alert("上传到远程", isPresented: $isUploadConfirmed) {
            Button("取消", role: .cancel) {}
            Button("确定") {
                uploadToRemote()
            }
        } message: {
            Text("确定要上传这本书到远程服务器吗？")
        }
        .sheet(isPresented: $model.isReaderPresented) {
            if let reader = model.reader {
                NavigationStack {
                    ReaderView(controller: reader)
                }
            }
        }
        .sheet(isPresented: $model.isMangaPresented) {
            if let manga = model.mangaReader {
                NavigationStack {
                    MangaReaderView(controller: manga)
                }
            }
        }
        .onAppear {
            load()
        }
    }

    // MARK: - Parts

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            BookCoverView(book: current, width: 84, height: 114)
            VStack(alignment: .leading, spacing: 6) {
                Text(current.name)
                    .font(.system(size: 20))
                Text(current.author)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                if let kind = current.kind, !kind.isEmpty {
                    Text(kind)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                if let wordCount = current.wordCount, !wordCount.isEmpty {
                    Text(wordCount)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                // Upstream `BookInfoActivity.tvOrigin` — the name of the
                // source; tapping it opens the source.
                if !sourceName.isEmpty {
                    Button(sourceName) {
                        if let source {
                            model.presentLogin(for: source)
                        }
                    }
                    .font(.system(size: 12))
                    .buttonStyle(PlainButtonStyle())
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// The information block — upstream `BookInfoActivity` shows the latest
    /// chapter, the group and the chapter count.
    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let latest = current.latestChapterTitle, !latest.isEmpty {
                // Upstream `BookInfoActivity.tvLasted` — 最新章节.
                LabeledRow(title: "最新章节", value: latest)
            }
            let names = BookGroups.names(for: current, groups: model.groups)
            if !names.isEmpty {
                // Upstream `BookInfoViewModel.getGroupName` — the group.
                LabeledRow(title: "分组", value: names.joined(separator: ","))
            }
            if current.totalChapterNum > 0 {
                LabeledRow(title: "章节", value: "\(current.totalChapterNum)")
            }
        }
    }

    @ViewBuilder
    private var chapterList: some View {
        if isLoading {
            ProgressView("加载中")
        } else if chapters.isEmpty {
            Text("还没有章节")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("目录（\(chapters.count) 章）")
                    .font(.system(size: 16))
                ForEach(chapters, id: \.url) { chapter in
                    Button {
                        openReader(chapterIndex: chapter.index)
                    } label: {
                        Text(chapter.title)
                            .font(.system(size: 14))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - The data

    /// The source of the book.
    private var source: BookSource? {
        try? model.environment.source(for: current)
    }

    /// The name of the source — upstream `Book.originName`.
    private var sourceName: String {
        if !current.originName.isEmpty {
            return current.originName
        }
        return source?.bookSourceName ?? ""
    }

    /// The text the upstream shares — `${bookUrl}#$bookJson`.
    private var shareText: String {
        let json = (try? LegadoBackup.encodeRows([current.row])) ?? "{}"
        return "\(current.bookUrl)#\(json)"
    }

    // MARK: - Actions

    private func load() {
        guard chapters.isEmpty else { return }
        isLoading = true
        Task {
            do {
                if let source = try model.environment.source(for: current) {
                    let result = try await model.environment.loadChapterList(book: current, source: source)
                    chapters = result.chapters
                    // The upstream writes the chapter-count fields back into the
                    // book; the port keeps them in the store.
                    try? model.environment.store.update(result.book)
                    current = result.book
                } else {
                    chapters = try model.environment.chapters(of: current)
                }
            } catch {
                errorMessage = error.localizedDescription
                chapters = (try? model.environment.chapters(of: current)) ?? []
            }
            isLoading = false
            loadShelfState()
        }
    }

    /// Reads whether the book is on the shelf and in which groups.
    private func loadShelfState() {
        let all = (try? model.environment.store.allBooks()) ?? []
        let stored = all.first { $0.bookUrl == current.bookUrl }
        isOnShelf = stored != nil
        groupMask = stored?.group ?? current.group
    }

    /// Reloads the book information from the source — upstream
    /// `BookInfoViewModel.refreshBook`.
    private func refresh() async {
        guard let source else {
            loadShelfState()
            return
        }
        do {
            let updated = try await model.environment.loadBookInfo(book: current, source: source)
            try? model.environment.store.update(updated)
            current = updated
            chapters = try model.environment.chapters(of: updated)
            model.reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Adds the book to the shelf or removes it — upstream
    /// `BookInfoActivity.menuAddOrRemove`.
    private func toggleShelf() {
        if isOnShelf {
            model.removeFromShelf(current)
            isOnShelf = false
        } else {
            model.addToShelf(current, groupId: groupMask)
            isOnShelf = true
        }
        model.reloadBookshelf()
    }

    /// Moves the book to a group — upstream `BookInfoActivity.menu_change_group`.
    private func moveToGroup(_ groupId: Int64) {
        var updated = current
        updated.group = groupId
        groupMask = groupId
        try? model.environment.store.update(updated)
        current = updated
        model.reloadBookshelf()
    }

    /// Toggles whether the book may be updated automatically — upstream
    /// `BookInfoActivity.menu_can_update`.
    private func toggleCanUpdate() {
        var updated = current
        updated.canUpdate.toggle()
        try? model.environment.store.update(updated)
        current = updated
        model.reloadBookshelf()
    }

    /// Whether the book is a local TXT book — upstream `Book.isLocalTxt`.
    private var isLocalTxt: Bool {
        guard BookType.contains(current.type, BookType.local) else { return false }
        guard let url = model.localImporter?.fileURL(for: current) else { return false }
        return url.pathExtension.lowercased() == "txt"
    }

    /// Toggles the split of the long chapters — upstream
    /// `BookInfoActivity.menu_split_long_chapter`.
    private func toggleSplitLongChapter() {
        let enabled = !current.readConfigBox.splitLongChapter
        let changed = TocOperations.setSplitLongChapter(enabled, book: current)
        try? model.environment.store.update(changed)
        current = changed
        if enabled, let fileURL = model.localImporter?.fileURL(for: current) {
            try? TocOperations.reparse(
                book: changed,
                rule: changed.tocUrl,
                fileURL: fileURL,
                splitLongChapter: true
            )
        }
        load()
    }

    /// Uploads the book to the WebDAV server — upstream
    /// `BookInfoActivity.upLoadBook` + `RemoteBookWebDav.upload`.
    private func uploadToRemote() {
        let account = model.environment.settings.appWebDav
        guard account.isConfigured else {
            errorMessage = "未配置webDav"
            return
        }
        Task {
            do {
                let client = WebDavClient(
                    configuration: account.serviceConfiguration,
                    httpClient: model.environment.httpClient
                )
                let importer = RemoteBookImporter(
                    client: client,
                    rootPath: "books/",
                    serverID: nil
                )
                let uploaded = try await importer.upload(book: current)
                try? model.environment.store.update(uploaded)
                current = uploaded
                model.reloadBookshelf()
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func openReader(chapterIndex: Int64? = nil) {
        // The reader is pushed by the bookshelf in the upstream app; the port
        // opens it as a sheet so the navigation stays simple.
        // An image book opens the manga reader (upstream `ContextExtensions`).
        Task {
            await model.openReader(for: current, chapterIndex: chapterIndex.map(Int.init))
        }
    }
}
