//
//  SearchScopeTests.swift
//  LegadoCoreTests
//
//  The scope of the search, the history of the searches and the merge of the
//  results.
//
//  Upstream:
//  app/src/main/java/io/legado/app/ui/book/search/SearchScope.kt
//  app/src/main/java/io/legado/app/ui/book/search/SearchViewModel.kt
//  app/src/main/java/io/legado/app/model/webBook/SearchModel.kt
//

import XCTest
@testable import LegadoCore

final class SearchScopeTests: XCTestCase {

    // MARK: - The scope

    func testTheEmptyScopeIsEverySource() {
        let scope = SearchScope.all
        XCTAssertTrue(scope.isAll)
        XCTAssertFalse(scope.isSource)
        XCTAssertEqual(scope.display, "全部书源")
        XCTAssertEqual(scope.groupNames, [])
    }

    func testTheScopeOfASource() {
        let source = BookSource(bookSourceUrl: "https://a.com", bookSourceName: "A")
        let scope = SearchScope(source: source)
        XCTAssertTrue(scope.isSource)
        XCTAssertFalse(scope.isAll)
        XCTAssertEqual(scope.sourceName, "A")
        XCTAssertEqual(scope.display, "A")
        XCTAssertEqual(scope.groupNames, [])
    }

    func testTheScopeOfTheGroups() {
        let scope = SearchScope(scope: "one, two")
        XCTAssertFalse(scope.isAll)
        XCTAssertFalse(scope.isSource)
        XCTAssertEqual(scope.groupNames, ["one", "two"])
        XCTAssertEqual(scope.display, "one,two")
    }

    func testTheSourceScopeIsResetWhenAGroupIsRemoved() {
        let source = BookSource(bookSourceUrl: "https://a.com", bookSourceName: "A")
        XCTAssertEqual(SearchScope(source: source).removing("one"), .all)
        XCTAssertEqual(SearchScope(scope: "one,two").removing("one").groupNames, ["two"])
    }

    // MARK: - The sources of the scope

    func testTheScopeOfEverySourceUsesTheEnabledSources() {
        let sources = [
            BookSource(bookSourceUrl: "a", customOrder: 2, enabled: true),
            BookSource(bookSourceUrl: "b", customOrder: 1, enabled: false),
            BookSource(bookSourceUrl: "c", customOrder: 3, enabled: true)
        ]
        let result = SearchScope.all.sources(from: sources)
        XCTAssertEqual(result.map(\.bookSourceUrl), ["a", "c"])
    }

    func testTheScopeOfASourceUsesTheSourceItself() {
        let sources = [
            BookSource(bookSourceUrl: "a", enabled: false),
            BookSource(bookSourceUrl: "b", enabled: true)
        ]
        let scope = SearchScope(source: BookSource(bookSourceUrl: "a", bookSourceName: "A"))
        XCTAssertEqual(scope.sources(from: sources).map(\.bookSourceUrl), ["a"])
    }

    func testTheScopeOfTheGroupsUsesTheSourcesOfTheGroups() {
        let sources = [
            BookSource(bookSourceUrl: "a", bookSourceGroup: "one"),
            BookSource(bookSourceUrl: "b", bookSourceGroup: "two"),
            BookSource(bookSourceUrl: "c", bookSourceGroup: "one,two")
        ]
        let scope = SearchScope(scope: "one")
        XCTAssertEqual(scope.sources(from: sources).map(\.bookSourceUrl), ["a", "c"])
    }

    func testTheScopeOfTheGroupsFallsBackToEveryEnabledSource() {
        let sources = [
            BookSource(bookSourceUrl: "a", bookSourceGroup: "one", enabled: true),
            BookSource(bookSourceUrl: "b", bookSourceGroup: "two", enabled: true)
        ]
        // Upstream `SearchScope.getBookSourceParts` — when the groups hold no
        // enabled source every enabled source is used.
        let scope = SearchScope(scope: "three")
        XCTAssertEqual(scope.sources(from: sources).map(\.bookSourceUrl), ["a", "b"])
    }

    // MARK: - The preferences

    func testTheScopeIsKeptInThePreferences() {
        let settings = AppSettings(store: InMemorySettingsStore())
        XCTAssertEqual(settings.searchScope, .all)
        settings.setSearchScope(SearchScope(scope: "one"))
        XCTAssertEqual(settings.searchScope.groupNames, ["one"])
        // Upstream `AppConfig.searchGroup` — the single group is kept.
        XCTAssertEqual(settings.settingsStore.string(forKey: SearchScope.groupKey), "one")
        settings.setSearchScope(SearchScope(scope: "one,two"))
        XCTAssertEqual(settings.settingsStore.string(forKey: SearchScope.groupKey), "")
    }

    // MARK: - The merge of the results

    func testTheEqualMatchesComeFirst() {
        let books = [
            SearchBook(bookUrl: "1", name: "Legend", author: "Someone"),
            SearchBook(bookUrl: "2", name: "Legend of the sea", author: "A"),
            SearchBook(bookUrl: "3", name: "Other", author: "B")
        ]
        let merged = SearchResultMerge.merge(books, keyword: "Legend", precision: false)
        XCTAssertEqual(merged.map(\.bookUrl), ["1", "2", "3"])
    }

    func testThePreciseSearchDropsTheOtherResults() {
        let books = [
            SearchBook(bookUrl: "1", name: "Legend of the sea", author: "A"),
            SearchBook(bookUrl: "2", name: "Other", author: "B")
        ]
        let merged = SearchResultMerge.merge(books, keyword: "Legend", precision: true)
        XCTAssertEqual(merged.map(\.bookUrl), ["1"])
    }

    func testTheBooksWithTheSameNameAndAuthorAreMerged() {
        let books = [
            SearchBook(bookUrl: "1", name: "Legend", author: "Someone"),
            SearchBook(bookUrl: "2", name: "Legend", author: "Someone")
        ]
        let merged = SearchResultMerge.merge(books, keyword: "Legend", precision: true)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.bookUrl, "1")
    }

    // MARK: - The history

    func testTheHistoryKeepsTheKeywords() throws {
        let store = try makeStore()
        let settings = AppSettings(store: InMemorySettingsStore())
        SearchHistory.save("Legend", store: store, settings: settings)
        SearchHistory.save("Other", store: store, settings: settings)
        let words = SearchHistory.keywords(store: store, settings: settings).map(\.word)
        XCTAssertTrue(words.contains("Legend"))
        XCTAssertTrue(words.contains("Other"))
    }

    func testTheUsageOfAKeywordIsCounted() throws {
        let store = try makeStore()
        let settings = AppSettings(store: InMemorySettingsStore())
        SearchHistory.save("Legend", store: store, settings: settings)
        SearchHistory.save("Legend", store: store, settings: settings)
        let keyword = SearchHistory.keywords(store: store, settings: settings)
            .first { $0.word == "Legend" }
        XCTAssertEqual(keyword?.usage, 2)
    }

    func testAKeywordCanBeDeleted() throws {
        let store = try makeStore()
        let settings = AppSettings(store: InMemorySettingsStore())
        SearchHistory.save("Legend", store: store, settings: settings)
        SearchHistory.delete("Legend", settings: settings)
        XCTAssertTrue(SearchHistory.keywords(store: store, settings: settings).isEmpty)
    }

    func testTheHistoryCanBeCleared() throws {
        let store = try makeStore()
        let settings = AppSettings(store: InMemorySettingsStore())
        SearchHistory.save("Legend", store: store, settings: settings)
        SearchHistory.save("Other", store: store, settings: settings)
        SearchHistory.clear(store: store, settings: settings)
        XCTAssertTrue(SearchHistory.keywords(store: store, settings: settings).isEmpty)
    }

    func testADeletedKeywordComesBack() throws {
        let store = try makeStore()
        let settings = AppSettings(store: InMemorySettingsStore())
        SearchHistory.save("Legend", store: store, settings: settings)
        SearchHistory.delete("Legend", settings: settings)
        SearchHistory.save("Legend", store: store, settings: settings)
        XCTAssertEqual(SearchHistory.keywords(store: store, settings: settings).count, 1)
    }

    // MARK: - The helpers

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        return store
    }
}
