//
//  DownloadViews.swift
//  LegadoUI
//
//  The offline cache — upstream
//  `app/src/main/java/io/legado/app/ui/book/read/BaseReadBookActivity.kt:266`
//  (`showDownloadDialog`) and
//  `app/src/main/java/io/legado/app/ui/book/cache/CacheActivity.kt`
//  (the cache / download screen).
//
//  The download engine itself is the port of upstream `model/CacheBook.kt` and
//  lives in the core (`Sources/LegadoCore/Net/BookCache.swift`); this file is
//  only the user interface.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The reader's "离线缓存" dialog — upstream `showDownloadDialog()`.
///
/// The dialog asks for the first and the last chapter of the range to cache;
/// the upstream submits `start - 1` and `end - 1` (the chapters are 0-based).
public struct ReaderDownloadDialog: View {

    @ObservedObject var model: LegadoAppModel
    let book: Book

    @State private var start: String = ""
    @State private var end: String = ""
    @State private var message: String?

    @Environment(\.dismiss) private var dismiss

    public init(model: LegadoAppModel, book: Book) {
        self.model = model
        self.book = book
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("离线缓存")
                .font(.system(size: 16, weight: .semibold))
            TextField("起始章节", text: $start)
                .textFieldStyle(.roundedBorder)
            TextField("结束章节", text: $end)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("确定") { submit() }
            }
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onAppear {
            start = String(book.durChapterIndex + 1)
            end = String(book.totalChapterNum)
        }
    }

    private func submit() {
        let first = Int(start) ?? 1
        let last = Int(end) ?? Int(book.totalChapterNum)
        guard first >= 1 else {
            message = "起始章节必须大于0"
            return
        }
        Task {
            await model.startCaching(book: book, start: first - 1, end: last - 1)
            dismiss()
        }
    }
}

/// The cache / download screen — upstream `ui/book/cache/CacheActivity.kt`.
///
/// It lists the books of the shelf with their download progress and offers
/// the per-book actions (cache from the current chapter, cache everything,
/// stop, export) plus the toolbar actions (cache everything, stop everything,
/// export everything, the app log).
public struct DownloadManageView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var books: [Book] = []
    @State private var isLogPresented = false
    @State private var message: String?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            if books.isEmpty {
                Text("没有书籍")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            ForEach(books, id: \.bookUrl) { book in
                DownloadBookRow(
                    book: book,
                    progress: model.cacheProgress[book.bookUrl],
                    onCache: { startCaching(book, from: Int(book.durChapterIndex)) },
                    onCacheAll: { startCaching(book, from: 0) },
                    onStop: { Task { await model.stopCaching(book: book) } },
                    onExport: { export(book) }
                )
            }
        }
        .navigationTitle("缓存管理")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu("更多") {
                    Button("全部缓存") {
                        for book in books {
                            startCaching(book, from: 0)
                        }
                    }
                    Button("全部停止") {
                        Task {
                            for book in books {
                                await model.stopCaching(book: book)
                            }
                        }
                    }
                    Button("日志") {
                        isLogPresented = true
                    }
                }
            }
        }
        .sheet(isPresented: $isLogPresented) {
            AppLogView()
        }
        .alert("缓存管理", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        books = (try? model.environment.bookshelf().books(
            inGroup: BookGroup.Id.all,
            settings: model.environment.settings
        )) ?? []
        Task {
            for book in books {
                await model.refreshCacheProgress(bookUrl: book.bookUrl)
            }
        }
    }

    private func startCaching(_ book: Book, from start: Int) {
        Task {
            await model.startCaching(book: book, start: start, end: Int.max)
            await model.refreshCacheProgress(bookUrl: book.bookUrl)
        }
    }

    private func export(_ book: Book) {
        Task {
            do {
                let file = try await model.exportBook(book: book, format: .txt)
                message = "已导出：\(file.fileName)"
            } catch {
                message = "导出失败：\(error.localizedDescription)"
            }
        }
    }
}

/// One row of the cache screen — upstream `CacheAdapter`.
public struct DownloadBookRow: View {

    let book: Book
    let progress: CacheBookProgress?
    let onCache: () -> Void
    let onCacheAll: () -> Void
    let onStop: () -> Void
    let onExport: () -> Void

    public init(
        book: Book,
        progress: CacheBookProgress?,
        onCache: @escaping () -> Void,
        onCacheAll: @escaping () -> Void,
        onStop: @escaping () -> Void,
        onExport: @escaping () -> Void
    ) {
        self.book = book
        self.progress = progress
        self.onCache = onCache
        self.onCacheAll = onCacheAll
        self.onStop = onStop
        self.onExport = onExport
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(book.name)
                .font(.system(size: 14, weight: .medium))
            Text(book.author)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            if let progress, !progress.isIdle {
                Text(progress.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            HStack {
                Button("缓存") { onCache() }
                Button("全部缓存") { onCacheAll() }
                Button("停止") { onStop() }
                Button("导出") { onExport() }
            }
            .font(.system(size: 12))
        }
        .padding(.vertical, 2)
    }
}
