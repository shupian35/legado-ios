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

import LegadoCore

/// The bookshelf tab.
public struct BookshelfView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var isLocalBooksPresented = false
    @State private var isManagePresented = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GroupSelector(model: model)
                if model.books.isEmpty {
                    EmptyState(text: "书架里还没有书")
                } else if model.environment.settings.bookshelfLayout == 0 {
                    // Upstream `AppConfig.bookshelfLayout == 0` is the list
                    // style; every other value is a grid with
                    // `bookshelfLayout + 2` columns.
                    List(model.visibleBooks, id: \.bookUrl) { book in
                        NavigationLink {
                            BookDetailView(model: model, book: book)
                        } label: {
                            BookRow(book: book)
                        }
                    }
                    .listStyle(PlainListStyle())
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
                // Upstream `MainViewModel.upAllBookToc` — the shelf menu
                // entry is called 更新目录.
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button("更新目录") {
                            Task { await model.updateAllBooks() }
                        }
                        // Upstream `BookshelfManageActivity` — the batch
                        // management of the shelf.
                        Button("书架管理") {
                            isManagePresented = true
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
            .onAppear {
                model.reloadBookshelf()
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
                        Text(group.groupName)
                            .font(.system(size: 14))
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

/// One book of the bookshelf.
struct BookRow: View {

    let book: Book

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(book.name)
                    .font(.system(size: 16))
                    .lineLimit(1)
                Text(book.author)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
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
                if let title = book.durChapterTitle, !title.isEmpty {
                    Text(title)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
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
