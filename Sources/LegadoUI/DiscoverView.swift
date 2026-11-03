//
//  DiscoverView.swift
//  LegadoUI
//
//  The discovery tab — upstream `ui/main/discover/`.
//
//  It lists the book sources, their explore categories and the books of the
//  selected category, and it offers the search (upstream
//  `ui/book/search/BookSearchActivity`).
//
//  See `AppModel.swift` for the state.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import LegadoCore

/// The discovery tab.
public struct DiscoverView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var selectedSource: BookSource?
    @State private var categories: [ExploreCategory] = []
    @State private var results: [SearchBook] = []
    @State private var isLoading = false
    @State private var isSearchPresented = false
    @State private var keyword: String = ""

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                sourceList
                categoryList
                resultList
            }
            .navigationTitle("发现")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("搜索") {
                        isSearchPresented = true
                    }
                }
            }
            .sheet(isPresented: $isSearchPresented) {
                SearchView(model: model, keyword: keyword, source: selectedSource)
            }
            .onAppear {
                model.reloadSources()
                if selectedSource == nil {
                    selectedSource = model.sources.first
                    loadCategories()
                }
            }
        }
    }

    // MARK: - Parts

    private var sourceList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.sources, id: \.bookSourceUrl) { source in
                    Button {
                        selectedSource = source
                        loadCategories()
                        results = []
                    } label: {
                        Text(source.bookSourceName)
                            .font(.system(size: 14))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                selectedSource?.bookSourceUrl == source.bookSourceUrl
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

    @ViewBuilder
    private var categoryList: some View {
        if !categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { category in
                        Button {
                            load(category: category)
                        } label: {
                            Text(category.name)
                                .font(.system(size: 13))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.12))
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if isLoading {
            ProgressView("加载中")
        } else if results.isEmpty {
            EmptyState(text: "没有内容")
        } else {
            List(results, id: \.bookUrl) { book in
                Button {
                    open(book)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(book.name)
                            .font(.system(size: 16))
                            .lineLimit(1)
                        Text(book.author)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .listStyle(PlainListStyle())
        }
    }

    // MARK: - Actions

    private func loadCategories() {
        categories = selectedSource.map { model.environment.exploreCategories(source: $0) } ?? []
    }

    private func load(category: ExploreCategory) {
        guard let source = selectedSource else { return }
        isLoading = true
        Task {
            do {
                results = try await model.environment.explore(source: source, url: category.url)
            } catch {
                model.errorMessage = error.localizedDescription
                results = []
            }
            isLoading = false
        }
    }

    private func open(_ searchBook: SearchBook) {
        guard let source = selectedSource else { return }
        var book = searchBook.toBook()
        book.origin = source.bookSourceUrl
        do {
            try model.environment.saveToShelf(book)
            model.reloadBookshelf()
        } catch {
            model.errorMessage = error.localizedDescription
        }
    }
}

/// The search screen — upstream `ui/book/search/BookSearchActivity`.
public struct SearchView: View {

    @ObservedObject var model: LegadoAppModel
    @State var keyword: String
    @State var source: BookSource?
    @State private var results: [SearchBook] = []
    @State private var isLoading = false

    public init(model: LegadoAppModel, keyword: String, source: BookSource?) {
        self.model = model
        self._keyword = State(initialValue: keyword)
        self._source = State(initialValue: source)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("书名或作者", text: $keyword)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("搜索") {
                        search()
                    }
                }
                .padding(12)
                if isLoading {
                    ProgressView("搜索中")
                } else if results.isEmpty {
                    EmptyState(text: "没有结果")
                } else {
                    List(results, id: \.bookUrl) { book in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.name)
                                .font(.system(size: 16))
                            Text(book.author)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            if let intro = book.intro, !intro.isEmpty {
                                Text(intro)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("搜索")
            .onAppear {
                if source == nil {
                    source = model.sources.first
                }
            }
        }
    }

    private func search() {
        guard let source, !keyword.isEmpty else { return }
        isLoading = true
        Task {
            do {
                results = try await model.environment.search(source: source, keyword: keyword)
            } catch {
                model.errorMessage = error.localizedDescription
                results = []
            }
            isLoading = false
        }
    }
}
