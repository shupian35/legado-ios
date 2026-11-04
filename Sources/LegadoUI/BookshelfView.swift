//
//  BookshelfView.swift
//  LegadoUI
//
//  The bookshelf — upstream `ui/main/bookshelf/`.
//
//  The bookshelf shows the books of the selected group, sorted the way the
//  upstream sort rules define it, with a group selector and a search field.
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

/// The bookshelf tab.
public struct BookshelfView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var isLocalBooksPresented = false
    @State private var isManagePresented = false
    @State private var isGroupManagePresented = false
    @State private var isCachePresented = false
    @State private var isSearchPresented = false
    @State private var isAddUrlPresented = false
    @State private var isExportPresented = false
    @State private var isImportPresented = false
    /// Whether the bookshelf configuration is shown — upstream
    /// `BaseBookshelfFragment.configBookshelf`.
    @State private var isConfigPresented = false
    /// Whether the app log is shown — upstream `R.id.menu_log`.
    @State private var isLogPresented = false
    /// The book whose information is shown (the long press).
    @State private var selectedBook: Book?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.environment.settings.bookGroupStyle == 1 {
                    // Upstream `AppConfig.bookGroupStyle == 1` selects the
                    // second bookshelf style (`BookshelfFragment2`), where the
                    // groups are shown as the folders of the shelf.
                    GroupFolderList(model: model)
                } else {
                    GroupSelector(model: model)
                }
                if model.visibleBooks.isEmpty {
                    EmptyState(text: "书架里还没有书")
                } else if model.environment.settings.bookshelfLayout == 0 {
                    // Upstream `AppConfig.bookshelfLayout == 0` is the list
                    // style; every other value is a grid with
                    // `bookshelfLayout + 2` columns.
                    bookList
                } else {
                    grid
                }
            }
            .navigationTitle("书架")
            .searchable(text: $model.bookFilter, prompt: "搜索书名或作者")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("刷新") {
                        model.reloadBookshelf()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("导入") {
                        isLocalBooksPresented = true
                    }
                }
                // Upstream `BaseBookshelfFragment.onCompatOptionsItemSelected` —
                // the menu of the bookshelf.
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        // Upstream `R.id.menu_search` — the source-wide
                        // search.
                        Button("搜索") {
                            isSearchPresented = true
                        }
                        // Upstream `R.id.menu_update_toc` — the update of the
                        // table of contents of the whole shelf.
                        Button("更新目录") {
                            Task { await model.updateAllBooks() }
                        }
                        // Upstream `R.id.menu_group_manage`.
                        Button("分组管理") {
                            isGroupManagePresented = true
                        }
                        // Upstream `R.id.menu_bookshelf_manage`.
                        Button("书架管理") {
                            isManagePresented = true
                        }
                        // Upstream `R.id.menu_add_url` — add a book by its
                        // address.
                        Button("添加网址") {
                            isAddUrlPresented = true
                        }
                        // Upstream `R.id.menu_download` — the cache activity.
                        Button("缓存") {
                            isCachePresented = true
                        }
                        // Upstream `R.id.menu_export_bookshelf`.
                        Button("导出书架") {
                            isExportPresented = true
                        }
                        // Upstream `R.id.menu_import_bookshelf`.
                        Button("导入书架") {
                            isImportPresented = true
                        }
                        // Upstream `R.id.menu_bookshelf_config` — the
                        // configuration of the shelf.
                        Button("书架布局") {
                            isConfigPresented = true
                        }
                        // Upstream `R.id.menu_log` — the app log.
                        Button("日志") {
                            isLogPresented = true
                        }
                    } label: {
                        Label("更多", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $isManagePresented) {
                NavigationStack {
                    BookshelfManageView(model: model)
                }
            }
            .sheet(isPresented: $isLocalBooksPresented) {
                NavigationStack {
                    LocalBookView(model: model)
                }
            }
            .sheet(isPresented: $isGroupManagePresented) {
                NavigationStack {
                    GroupManageView(model: model)
                }
            }
            .sheet(isPresented: $isCachePresented) {
                NavigationStack {
                    CacheManageView(model: model)
                }
            }
            .sheet(isPresented: $isSearchPresented) {
                NavigationStack {
                    DiscoverView(model: model)
                }
            }
            .sheet(isPresented: $isAddUrlPresented) {
                NavigationStack {
                    AddBookByUrlView(model: model)
                }
            }
            .sheet(isPresented: $isExportPresented) {
                NavigationStack {
                    ExportBookshelfView(model: model)
                }
            }
            .sheet(isPresented: $isImportPresented) {
                NavigationStack {
                    ImportBookshelfView(model: model)
                }
            }
            .sheet(isPresented: $isConfigPresented) {
                NavigationStack {
                    BookshelfConfigView(model: model)
                }
            }
            .sheet(isPresented: $isLogPresented) {
                NavigationStack {
                    AppLogView()
                }
            }
            .sheet(item: $selectedBook) { book in
                NavigationStack {
                    BookInfoMenuView(model: model, book: book)
                }
            }
            .onAppear {
                model.reloadBookshelf()
            }
        }
    }

    /// The list style of the shelf — upstream `BooksFragment` with the
    /// `BooksAdapterList` and the optional fast scroll bar
    /// (`AppConfig.showBookshelfFastScroller`).
    private var bookList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .trailing) {
                List(model.visibleBooks, id: \.bookUrl) { book in
                    NavigationLink {
                        BookDetailView(model: model, book: book)
                    } label: {
                        BookRow(
                            book: book,
                            showsLastUpdateTime: model.environment.settings.bool(.showLastUpdateTime, default: false),
                            showsUnread: model.environment.settings.showUnread
                        )
                    }
                    .id(book.bookUrl)
                    .onLongPressGesture {
                        selectedBook = book
                    }
                }
                .listStyle(PlainListStyle())
                if model.environment.settings.showBookshelfFastScroller {
                    BookshelfFastScroller(count: model.visibleBooks.count) { index in
                        guard index >= 0, index < model.visibleBooks.count else { return }
                        proxy.scrollTo(model.visibleBooks[index].bookUrl, anchor: .top)
                    }
                    .padding(.trailing, 2)
                }
            }
        }
    }

    /// The grid style — upstream `GridLayoutManager(context, bookshelfLayout + 2)`.
    private var grid: some View {
        ScrollView {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: max(1, model.environment.settings.bookshelfLayout + 2)
                ),
                spacing: 12
            ) {
                ForEach(model.visibleBooks, id: \.bookUrl) { book in
                    NavigationLink {
                        BookDetailView(model: model, book: book)
                    } label: {
                        BookGridCell(book: book)
                    }
                    .onLongPressGesture {
                        selectedBook = book
                    }
                }
            }
            .padding(12)
        }
    }
}

/// One cell of the bookshelf grid.
struct BookGridCell: View {

    let book: Book

    var body: some View {
        VStack(spacing: 4) {
            BookCoverView(book: book, width: 72, height: 96)
            Text(book.name)
                .font(.system(size: 13))
                .lineLimit(2)
                .multilineTextAlignment(.center)
            Text(book.author)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// The horizontal group selector of the bookshelf.
struct GroupSelector: View {

    @ObservedObject var model: LegadoAppModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.groups, id: \.groupId) { group in
                    Button {
                        model.select(groupId: group.groupId)
                    } label: {
                        HStack(spacing: 4) {
                            Text(group.groupName)
                                .font(.system(size: 14))
                            // Upstream `AppConfig.showWaitUpCount` — the
                            // number of the books that wait for an update.
                            if model.environment.settings.bool(.showWaitUpCount, default: false) {
                                let count = model.waitingUpdateCount(inGroup: group.groupId)
                                if count > 0 {
                                    Text("\(count)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            model.selectedGroupId == group.groupId
                                ? Color.accentColor.opacity(0.2)
                                : Color.gray.opacity(0.12)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}

/// The group selector of the shelf in the "folder" style.
///
/// Upstream `AppConfig.bookGroupStyle == 1` selects the second bookshelf
/// style (`BookshelfFragment2`), where the groups are the folders of the
/// shelf: they are the first items of the list and a tap opens the group.
struct GroupFolderList: View {

    @ObservedObject var model: LegadoAppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(model.groups, id: \.groupId) { group in
                        Button {
                            model.select(groupId: group.groupId)
                        } label: {
                            HStack(spacing: 6) {
                                // Upstream `BookGroup.cover` — the group tile
                                // shows its cover (`BooksAdapterGrid`:
                                // `ivCover.load(item.cover)`).
                                GroupCoverIcon(cover: group.cover)
                                Text(group.groupName)
                                    .font(.system(size: 15))
                                // Upstream `AppConfig.showWaitUpCount` — the
                                // number of the books that wait for an update.
                                if model.environment.settings.bool(.showWaitUpCount, default: false) {
                                    let count = model.waitingUpdateCount(inGroup: group.groupId)
                                    if count > 0 {
                                        Text("\(count)")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                model.selectedGroupId == group.groupId
                                    ? Color.accentColor.opacity(0.2)
                                    : Color.gray.opacity(0.12)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            Divider()
        }
    }
}

/// The cover of a group — upstream `BookGroup.cover`.
///
/// The group tile of the shelf shows the cover of the group when it has one
/// (`BooksAdapterGrid`: `ivCover.load(item.cover)`); otherwise the folder icon
/// is used.
struct GroupCoverIcon: View {

    /// The path of the cover file.
    let cover: String?

    var body: some View {
        if let cover, !cover.isEmpty {
            AsyncImage(url: URL(fileURLWithPath: cover)) { phase in
                if case let .success(image) = phase {
                    return AnyView(image.resizable().aspectRatio(contentMode: .fill))
                }
                return AnyView(
                    Image(systemName: "folder")
                        .font(.system(size: 13))
                )
            }
            .frame(width: 18, height: 18)
            .cornerRadius(3)
            .clipped()
        } else {
            Image(systemName: "folder")
                .font(.system(size: 13))
        }
    }
}

/// The fast scroll bar of the shelf.
///
/// Upstream `AppConfig.showBookshelfFastScroller` enables the `FastScroller`
/// of the shelf (`ui/widget/recycler/scroller/FastScroller.kt`): a thin
/// handle on the right edge that is dragged to scroll the list. The upstream
/// adapter does not implement a `SectionIndexer`, so the scroller only jumps
/// proportionally — the port does the same.
struct BookshelfFastScroller: View {

    /// The number of the books of the list.
    let count: Int
    /// The new position of the list — the index of the first visible book.
    let onSelect: (Int) -> Void

    @State private var isDragging = false
    @State private var fraction: Double = 0

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.clear
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.secondary.opacity(isDragging ? 0.8 : 0.35))
                    .frame(width: 6)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 8)
                    .offset(y: handleOffset(in: proxy.size.height))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let height = max(proxy.size.height, 1)
                        let value2 = min(max(value.location.y / height, 0), 1)
                        fraction = value2
                        guard count > 0 else { return }
                        let index = min(Int(value2 * Double(count)), count - 1)
                        onSelect(max(index, 0))
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .frame(width: 16)
    }

    /// The vertical position of the handle — upstream the handle follows the
    /// finger.
    private func handleOffset(in height: Double) -> Double {
        let travel = max(height - 16 - 40, 0)
        return travel * fraction
    }
}

/// One book of the bookshelf.
///
/// Upstream `style1/books/BooksAdapterList` and `style2/BooksAdapterList`.
struct BookRow: View {

    let book: Book
    /// Whether the time of the last update is shown — upstream
    /// `AppConfig.showLastUpdateTime`.
    var showsLastUpdateTime = false
    /// Whether the number of the chapters that were not read is shown —
    /// upstream `AppConfig.showUnread`.
    var showsUnread = true

    var body: some View {
        HStack(spacing: 12) {
            BookCoverView(book: book, width: 52, height: 70)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(book.name)
                        .font(.system(size: 16))
                        .lineLimit(1)
                    // Upstream `BooksAdapterList.upUnread` — the number of the
                    // chapters that were not read yet.
                    let unread = BookRow.unreadCount(book)
                    if showsUnread, unread > 0 {
                        Text("\(unread)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }
                Text(book.author)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                // Upstream `BooksAdapterList.tvLast` — the latest chapter.
                if let latest = book.latestChapterTitle, !latest.isEmpty {
                    Text(latest)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if let kind = book.kind, !kind.isEmpty {
                    Text(kind)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if let wordCount = book.wordCount, !wordCount.isEmpty {
                    Text(wordCount)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                // Upstream `BooksAdapterList.upLastUpdateTime` — the time of
                // the last update (behind `AppConfig.showLastUpdateTime`).
                if book.lastCheckTime > 0, showsLastUpdateTime {
                    Text(BookRow.lastUpdateText(book.lastCheckTime))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// The number of the chapters that were not read — upstream
    /// `Book.getUnreadChapterNum()` (the simulated reading is honoured).
    static func unreadCount(_ book: Book) -> Int {
        Int(book.unreadChapterNum())
    }

    /// The text of the time of the last update — upstream
    /// `BooksAdapterList.upLastUpdateTime`.
    static func lastUpdateText(_ millis: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(millis / 1000))
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return formatter.string(from: date)
    }
}

/// The placeholder of an empty list.
struct EmptyState: View {

    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Text(text)
                .font(.system(size: 15))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
