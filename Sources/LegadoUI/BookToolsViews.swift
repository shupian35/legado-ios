//
//  BookToolsViews.swift
//  LegadoUI
//
//  The book tools of the upstream app:
//
//  * 换源 (change source) — upstream `ui/book/changesource/`;
//  * 搜索正文 (search inside the book) — upstream `ui/book/searchContent/`;
//  * 校验 (verify a book source) — upstream `ui/config/CheckSourceConfig`.
//
//  The logic lives in `LegadoCore` (`Pipeline/ChangeSource.swift`,
//  `Pipeline/ContentSearch.swift`, `Pipeline/SourceCheck.swift`), the views
//  only drive it.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

// MARK: - 换源

/// The change-source sheet: it searches the other book sources for the same
/// book and lets the reader move the book over to another source.
public struct ChangeSourceView: View {

    @ObservedObject var model: LegadoAppModel
    let book: Book

    @State private var candidates: [ChangeSourceCandidate] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var checkAuthor = true
    @State private var loadWordCount = false
    @State private var didSearch = false

    public init(model: LegadoAppModel, book: Book) {
        self.model = model
        self.book = book
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("校验作者", isOn: $checkAuthor)
                Toggle("加载字数", isOn: $loadWordCount)
                Button("搜索") {
                    search()
                }
            }
            if isLoading {
                ProgressView("正在搜索…")
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
            if candidates.isEmpty && !isLoading && didSearch {
                EmptyState(text: "没有找到其他来源")
            }
            List(candidates, id: \.scoreKey) { candidate in
                VStack(alignment: .leading, spacing: 4) {
                    Text(candidate.sourceName)
                        .font(.system(size: 15, weight: .medium))
                    Text(candidate.book.name)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    HStack {
                        Text(candidate.book.author)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        if let wordCount = candidate.chapterWordCountText {
                            Text(wordCount)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onTapGesture {
                    switchSource(candidate)
                }
            }
            .listStyle(PlainListStyle())
        }
        .padding(16)
        .navigationTitle("换源")
    }

    private func search() {
        isLoading = true
        errorMessage = nil
        didSearch = true
        Task {
            do {
                let sources = try model.environment.sources(enabledOnly: true)
                let options = ChangeSourceOptions(
                    checkAuthor: checkAuthor,
                    loadWordCount: loadWordCount
                )
                let found = try await ChangeSourceService.search(
                    book: book,
                    sources: sources,
                    options: options,
                    dependencies: model.environment.dependencies()
                )
                candidates = found
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func switchSource(_ candidate: ChangeSourceCandidate) {
        do {
            let switched = try ChangeSourceService.switchSource(
                oldBook: book,
                newBook: candidate.book,
                toc: candidate.toc
            )
            try model.environment.store.update(switched)
            model.reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - 搜索正文

/// The content search sheet: it searches the downloaded chapters of a book.
public struct ContentSearchView: View {

    @ObservedObject var model: LegadoAppModel
    let book: Book

    @State private var query: String = ""
    @State private var results: [ContentSearchResult] = []
    @State private var isLoading = false
    @State private var didSearch = false

    public init(model: LegadoAppModel, book: Book) {
        self.model = model
        self.book = book
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("输入关键词", text: $query)
                Button("搜索") {
                    search()
                }
            }
            if isLoading {
                ProgressView("正在搜索…")
            }
            if results.isEmpty && didSearch && !isLoading {
                // The upstream shows the same hint when the purification or the
                // Chinese conversion hides the query.
                EmptyState(text: "搜索内容为空，请检查净化或简繁设置")
            }
            List(results, id: \.resultCount) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.chapterTitle)
                        .font(.system(size: 13, weight: .medium))
                    Text(result.resultText)
                        .font(.system(size: 13))
                }
            }
            .listStyle(PlainListStyle())
        }
        .padding(16)
        .navigationTitle("搜索正文")
    }

    private func search() {
        isLoading = true
        didSearch = true
        Task {
            do {
                guard let storage = model.environment.cacheStorage else {
                    results = []
                    isLoading = false
                    return
                }
                let chapters = try model.environment.chapters(of: book)
                let titleRules = try model.environment.store.replaceRulesForTitle(
                    name: book.name,
                    origin: book.origin
                )
                let contentRules = try model.environment.store.replaceRulesForContent(
                    name: book.name,
                    origin: book.origin
                )
                let options = ContentSearchOptions(
                    useReplaceRule: book.useReplaceRule,
                    chineseConversionMode: ChineseConversionMode(
                        rawValue: model.environment.settings.chineseConverterType
                    ) ?? .off
                )
                results = ContentSearcher.search(
                    book: book,
                    chapters: chapters,
                    query: query,
                    storage: storage,
                    titleRules: titleRules,
                    contentRules: contentRules,
                    options: options,
                    scriptEngine: model.environment.scriptEngine
                )
            } catch {
                results = []
            }
            isLoading = false
        }
    }
}

// The verification of the book sources moved to `SourceCheckView.swift` — it
// now takes the selection of the user, the keyword of the search, the timeout
// of the check and it can be cancelled.
