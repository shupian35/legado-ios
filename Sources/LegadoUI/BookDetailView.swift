//
//  BookDetailView.swift
//  LegadoUI
//
//  The detail page of a book — upstream `ui/book/info/`.
//
//  It shows the cover, the title, the author, the introduction and the table
//  of contents, and it can refresh the information and the chapter list from
//  the book source.
//
//  See `AppModel.swift` for the state.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

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

    /// Whether the book is being cached (upstream `CacheBook`).
    private var isCaching: Bool {
        let progress = model.cacheProgress[book.bookUrl]
        return (progress?.downloading ?? 0) + (progress?.waiting ?? 0) > 0
    }

    public init(model: LegadoAppModel, book: Book) {
        self.model = model
        self.book = book
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if let intro = book.customIntro ?? book.intro, !intro.isEmpty {
                    Section {
                        Text(intro)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
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
        .navigationTitle(book.name)
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
                            Task { await model.stopCaching(book: book) }
                        } else {
                            Task { await model.startCaching(book: book) }
                        }
                    }
                    // Upstream `MainViewModel.updateToc` — the button is
                    // called 更新目录 (检查更新 is the app-version check).
                    Button("更新目录") {
                        Task { await model.updateBook(book) }
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $isChangeSourcePresented) {
            NavigationStack {
                ChangeSourceView(model: model, book: book)
            }
        }
        .sheet(isPresented: $isContentSearchPresented) {
            NavigationStack {
                ContentSearchView(model: model, book: book)
            }
        }
        .sheet(isPresented: $isBookInfoPresented) {
            NavigationStack {
                BookInfoMenuView(model: model, book: book)
            }
        }
        .sheet(isPresented: $isTocPresented) {
            NavigationStack {
                TocView(model: model, book: book)
            }
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
        VStack(alignment: .leading, spacing: 8) {
            Text(book.name)
                .font(.system(size: 20))
            Text(book.author)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
            if let kind = book.kind, !kind.isEmpty {
                Text(kind)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            if let wordCount = book.wordCount, !wordCount.isEmpty {
                Text(wordCount)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
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

    // MARK: - Actions

    private func load() {
        guard chapters.isEmpty else { return }
        isLoading = true
        Task {
            do {
                if let source = try model.environment.source(for: book) {
                    let result = try await model.environment.loadChapterList(book: book, source: source)
                    chapters = result.chapters
                    // The upstream writes the chapter-count fields back into the
                    // book; the port keeps them in the store.
                    try? model.environment.store.update(result.book)
                } else {
                    chapters = try model.environment.chapters(of: book)
                }
            } catch {
                errorMessage = error.localizedDescription
                chapters = (try? model.environment.chapters(of: book)) ?? []
            }
            isLoading = false
        }
    }

    private func openReader(chapterIndex: Int64? = nil) {
        // The reader is pushed by the bookshelf in the upstream app; the port
        // opens it as a sheet so the navigation stays simple.
        // An image book opens the manga reader (upstream `ContextExtensions`).
        Task {
            await model.openReader(for: book, chapterIndex: chapterIndex.map(Int.init))
        }
    }
}
