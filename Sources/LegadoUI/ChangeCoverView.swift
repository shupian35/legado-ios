//
//  ChangeCoverView.swift
//  LegadoUI
//
//  Port of `app/src/main/java/io/legado/app/ui/book/changecover/`.
//
//  The screen searches the covers of a book in the sources that have a cover
//  rule and shows them in a grid; the first entry is the generated default
//  cover. The upstream searches every enabled source in parallel and stops
//  after the first hit of each one.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The marker of the generated default cover — upstream
/// `ChangeCoverViewModel.defaultCover`'s `coverUrl = "use_default_cover"`.
public let legadoDefaultCoverMarker = "use_default_cover"

/// The cover source picker — upstream `ChangeCoverDialog`.
public struct ChangeCoverView: View {

    @ObservedObject var model: LegadoAppModel
    /// The book whose cover is changed.
    let book: Book
    /// The callback of the selection — upstream `ChangeCoverDialog.CallBack`.
    let onSelect: (String) -> Void

    /// The covers that were found.
    @State private var covers: [CoverSearchResult] = []
    /// Whether the search is running — upstream `searchStateData`.
    @State private var isSearching = false
    /// The running search — upstream `ChangeCoverViewModel.task`.
    @State private var searchTask: Task<Void, Never>?

    public init(model: LegadoAppModel, book: Book, onSelect: @escaping (String) -> Void) {
        self.model = model
        self.book = book
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 8
            ) {
                // Upstream `ChangeCoverViewModel.defaultCover` — the first
                // entry is always the generated default cover.
                coverCell(
                    url: legadoDefaultCoverMarker,
                    originName: "默认封面",
                    isDefault: true
                )
                ForEach(covers) { item in
                    coverCell(url: item.coverUrl, originName: item.originName, isDefault: false)
                }
            }
            .padding(8)
            if isSearching {
                HStack {
                    ProgressView()
                    Text("正在搜索封面…")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .padding(8)
            }
        }
        .navigationTitle("更换封面")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Upstream `res/menu/change_cover.xml` → `menu_start_stop`.
                Button(isSearching ? "停止" : "刷新") {
                    if isSearching {
                        stop()
                    } else {
                        start()
                    }
                }
            }
        }
        .task {
            start()
        }
        .onDisappear {
            stop()
        }
    }

    /// A cell of the grid — upstream `CoverAdapter.convert`.
    @ViewBuilder
    private func coverCell(url: String, originName: String, isDefault: Bool) -> some View {
        Button {
            onSelect(url)
        } label: {
            VStack(spacing: 4) {
                if isDefault {
                    BookCoverView(book: book, width: 90, height: 120)
                } else if let remote = URL(string: url) {
                    AsyncImage(url: remote) { phase in
                        if case let .success(image) = phase {
                            return AnyView(image.resizable().aspectRatio(contentMode: .fill))
                        }
                        return AnyView(
                            Rectangle().fill(Color.gray.opacity(0.15))
                        )
                    }
                    .frame(width: 90, height: 120)
                    .cornerRadius(4)
                    .clipped()
                }
                Text(originName)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    /// Starts the search — upstream `ChangeCoverViewModel.startSearch`.
    private func start() {
        stop()
        isSearching = true
        searchTask = Task {
            let sources = (try? model.environment.sources(enabledOnly: true)) ?? []
            let found = await BookCoverService.searchCovers(
                book: book,
                sources: sources,
                dependencies: model.environment.dependencies()
            )
            if Task.isCancelled { return }
            covers = found
            isSearching = false
        }
    }

    /// Stops the search — upstream `ChangeCoverViewModel.stopSearch`.
    private func stop() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }
}

/// The full-screen cover preview — upstream `PhotoDialog`.
public struct BookCoverPreviewView: View {

    @Environment(\.dismiss) private var dismiss

    /// The URL of the cover.
    let url: String?
    /// The title of the screen.
    var title: String = "封面"

    public init(url: String?, title: String = "封面") {
        self.url = url
        self.title = title
    }

    public var body: some View {
        NavigationStack {
            Group {
                if let url, let remote = URL(string: url) {
                    AsyncImage(url: remote) { phase in
                        if case let .success(image) = phase {
                            return AnyView(image.resizable().aspectRatio(contentMode: .fit))
                        }
                        return AnyView(
                            VStack {
                                ProgressView()
                                Text("加载中…")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        )
                    }
                } else {
                    Text("没有封面")
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}
