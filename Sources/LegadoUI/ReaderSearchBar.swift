#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import LegadoCore

/// The search bar of the reader — upstream `ui/book/read/SearchMenu.kt`.
///
/// The upstream bar shows the number of the results and the current chapter
/// (`updateSearchInfo`), the previous / the next result
/// (`navigateToSearch`) and the buttons for the main menu, the result list
/// and the exit.
public struct ReaderSearchBar: View {

    /// The reader controller.
    @ObservedObject var controller: ReaderController
    /// Called when the search is closed.
    var onExit: () -> Void = {}
    /// Called when the user asks for the full result list.
    var onShowResults: (String) -> Void = { _ in }
    /// Called when the user asks for the main menu.
    var onShowMenu: () -> Void = {}

    @State private var query: String = ""
    @State private var results: [ContentSearchResult] = []
    @State private var currentIndex: Int = 0
    @State private var isSearching = false
    @State private var useReplaceRule = false

    public init(
        controller: ReaderController,
        onExit: @escaping () -> Void = {},
        onShowResults: @escaping (String) -> Void = { _ in },
        onShowMenu: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self.onExit = onExit
        self.onShowResults = onShowResults
        self.onShowMenu = onShowMenu
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("搜索正文", text: $query)
                Button("搜索") {
                    search()
                }
                Button("结果") {
                    onShowResults(query)
                }
                Button("菜单") {
                    onShowMenu()
                }
                Button("退出") {
                    onExit()
                }
            }
            .font(.system(size: 13))
            if isSearching {
                Text("正在搜索…")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            // The upstream shows the number of the results and the current
            // chapter (`SearchMenu.updateSearchInfo`).
            Text("搜索结果: \(results.count) / 当前章节: \(controller.chapterTitle)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            if !results.isEmpty {
                HStack {
                    Button("上一个") {
                        navigate(offset: -1)
                    }
                    Spacer()
                    Text("\(currentIndex + 1) / \(results.count)")
                        .font(.system(size: 12))
                    Spacer()
                    Button("下一个") {
                        navigate(offset: 1)
                    }
                }
                .font(.system(size: 13))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    /// Searches the cached chapters of the book — upstream
    /// `SearchContentViewModel.searchContent`.
    private func search() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            results = []
            return
        }
        isSearching = true
        Task {
            defer { isSearching = false }
            guard let storage = controller.environment.cacheStorage else {
                results = []
                return
            }
            let chapters = try? controller.environment.chapters(of: controller.book)
            let titleRules = (try? controller.environment.store.replaceRulesForTitle(
                name: controller.book.name,
                origin: controller.book.origin
            )) ?? []
            let contentRules = (try? controller.environment.store.replaceRulesForContent(
                name: controller.book.name,
                origin: controller.book.origin
            )) ?? []
            let found = ContentSearcher.search(
                book: controller.book,
                chapters: chapters ?? [],
                query: keyword,
                storage: storage,
                titleRules: titleRules,
                contentRules: contentRules,
                options: ContentSearchOptions(useReplaceRule: useReplaceRule)
            )
            results = found
            currentIndex = 0
            if let first = found.first {
                await navigate(to: first)
            }
        }
    }

    /// Moves to the previous or the next result — upstream
    /// `SearchMenu.updateSearchResultIndex` + `navigateToSearch`.
    private func navigate(offset: Int) {
        guard !results.isEmpty else { return }
        let index = max(0, min(currentIndex + offset, results.count - 1))
        currentIndex = index
        let result = results[index]
        Task { await navigate(to: result) }
    }

    /// Jumps to the chapter and the position of the result — upstream
    /// `ReadBookActivity.navigateToSearch`.
    private func navigate(to result: ContentSearchResult) async {
        await controller.jump(toChapter: result.chapterIndex, position: result.queryIndexInChapter)
    }
}
