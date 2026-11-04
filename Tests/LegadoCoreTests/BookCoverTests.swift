import XCTest

@testable import LegadoCore

/// The cover rule — the port of `model/BookCover.kt`.
final class BookCoverTests: XCTestCase {

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        return store
    }

    // MARK: - The configuration

    func testTheDefaultRuleIsUsedWhenThereIsNoConfiguration() throws {
        let store = try makeStore()
        let config = BookCoverService.config(store: store)
        XCTAssertFalse(config.enable)
        XCTAssertEqual(config.searchUrl, "")
        XCTAssertEqual(config.coverRule, "")
    }

    func testTheConfigurationIsStoredAndReadBack() throws {
        let store = try makeStore()
        let config = CoverRule(
            enable: true,
            searchUrl: "https://example.com/search?key={key}",
            coverRule: "img.cover@src"
        )
        try BookCoverService.save(config, store: store)
        let loaded = BookCoverService.config(store: store)
        XCTAssertTrue(loaded.enable)
        XCTAssertEqual(loaded.searchUrl, "https://example.com/search?key={key}")
        XCTAssertEqual(loaded.coverRule, "img.cover@src")
    }

    func testTheConfigurationIsDeleted() throws {
        let store = try makeStore()
        try BookCoverService.save(
            CoverRule(enable: true, searchUrl: "https://example.com", coverRule: "img@src"),
            store: store
        )
        try BookCoverService.delete(store: store)
        XCTAssertFalse(BookCoverService.config(store: store).enable)
    }

    func testTheRuleIsParsedFromItsJson() {
        let json = """
        {"enable":true,"searchUrl":"https://example.com","coverRule":"img@src",\
        "concurrentRate":"1/1000","enabledCookieJar":true}
        """
        let rule = CoverRule.parse(json)
        XCTAssertNotNil(rule)
        XCTAssertEqual(rule?.enable, true)
        XCTAssertEqual(rule?.searchUrl, "https://example.com")
        XCTAssertEqual(rule?.coverRule, "img@src")
        XCTAssertEqual(rule?.concurrentRate, "1/1000")
        XCTAssertEqual(rule?.enabledCookieJar, true)
    }

    func testABrokenJsonIsNotParsed() {
        XCTAssertNil(CoverRule.parse("not json"))
        XCTAssertNil(CoverRule.parse(""))
    }

    // MARK: - The search

    func testTheCoverIsSearchedWithTheNameOfTheBook() async throws {
        let client = StubHttpClient { request in
            HttpResponse(url: request.url, body: """
            <html><body><img class="cover" src="https://example.com/cover.jpg"/></body></html>
            """)
        }
        let book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        let config = CoverRule(
            enable: true,
            searchUrl: "https://example.com/search?key={key}",
            coverRule: "img.cover@src"
        )
        let cover = try await BookCoverService.searchCover(
            book: book,
            config: config,
            dependencies: AnalyzeUrlDependencies(httpClient: client)
        )
        XCTAssertEqual(cover, "https://example.com/cover.jpg")
        XCTAssertEqual(client.requests.count, 1)
        // Upstream `AnalyzeUrl` binds the key for the scripts; it does not
        // replace `{key}` in the URL.
        XCTAssertTrue(client.requests[0].url.contains("example.com/search"))
    }

    func testTheSearchIsSkippedWhenTheRuleIsDisabled() async throws {
        let client = StubHttpClient { request in HttpResponse(url: request.url, body: "") }
        let book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        let config = CoverRule(
            enable: false,
            searchUrl: "https://example.com/search?key={key}",
            coverRule: "img.cover@src"
        )
        let cover = try await BookCoverService.searchCover(
            book: book,
            config: config,
            dependencies: AnalyzeUrlDependencies(httpClient: client)
        )
        XCTAssertNil(cover)
        XCTAssertEqual(client.requests.count, 0)
    }

    // MARK: - The cover source search

    /// A source with a search rule that has a cover URL.
    private func makeCoverSource(name: String = "Test", order: Int64 = 0) -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.com/\(name)",
            bookSourceName: name,
            customOrder: order,
            searchUrl: "https://example.com/search",
            ruleSearch: """
            {"bookList":"div.book","name":"h3 a@text","author":"span.author@text",\
            "coverUrl":"img.cover@src","bookUrl":"h3 a@href"}
            """
        )
    }

    private let searchHTML = """
    <div class="book">
      <h3><a href="/book/1">测试书</a></h3>
      <span class="author">作者</span>
      <img class="cover" src="https://example.com/cover.jpg"/>
    </div>
    """

    func testTheCoversAreSearchedInTheSources() async throws {
        let client = StubHttpClient { request in
            HttpResponse(url: request.url, body: self.searchHTML)
        }
        let book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        let covers = await BookCoverService.searchCovers(
            book: book,
            sources: [makeCoverSource()],
            dependencies: AnalyzeUrlDependencies(httpClient: client)
        )
        XCTAssertEqual(covers.count, 1)
        XCTAssertEqual(covers[0].coverUrl, "https://example.com/cover.jpg")
        XCTAssertEqual(covers[0].originName, "Test")
    }

    func testTheSourcesWithoutACoverRuleAreSkipped() async throws {
        let client = StubHttpClient { request in
            HttpResponse(url: request.url, body: self.searchHTML)
        }
        let source = BookSource(
            bookSourceUrl: "https://example.com/plain",
            bookSourceName: "Plain",
            searchUrl: "https://example.com/search",
            ruleSearch: "{\"bookList\":\"div.book\",\"name\":\"h3 a@text\"}"
        )
        let book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        let covers = await BookCoverService.searchCovers(
            book: book,
            sources: [source],
            dependencies: AnalyzeUrlDependencies(httpClient: client)
        )
        XCTAssertTrue(covers.isEmpty)
        XCTAssertEqual(client.requests.count, 0)
    }

    func testTheCoversAreSortedByTheOrderOfTheSource() async throws {
        let client = StubHttpClient { request in
            HttpResponse(url: request.url, body: self.searchHTML)
        }
        let book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        let covers = await BookCoverService.searchCovers(
            book: book,
            sources: [
                makeCoverSource(name: "Second", order: 5),
                makeCoverSource(name: "First", order: 1)
            ],
            dependencies: AnalyzeUrlDependencies(httpClient: client)
        )
        XCTAssertEqual(covers.count, 2)
        XCTAssertEqual(covers[0].originName, "First")
        XCTAssertEqual(covers[1].originName, "Second")
    }

    func testABookWithAnotherNameIsNotACover() async throws {
        let client = StubHttpClient { request in
            HttpResponse(url: request.url, body: self.searchHTML)
        }
        let book = Book(bookUrl: "https://example.com/book", name: "别的书", author: "作者")
        let covers = await BookCoverService.searchCovers(
            book: book,
            sources: [makeCoverSource()],
            dependencies: AnalyzeUrlDependencies(httpClient: client)
        )
        XCTAssertTrue(covers.isEmpty)
    }
}

/// The saving of the current theme — upstream `ThemeConfig.saveDayTheme` /
/// `ThemeConfig.saveNightTheme`.
final class ThemeSaveTests: XCTestCase {

    func testTheCurrentDayColoursAreSavedUnderANewName() {
        let manager = ThemeManager(themes: AppTheme.defaults, selectedIndex: 0)
        let count = manager.themes.count
        XCTAssertTrue(manager.saveCurrentTheme(name: "我的日间", isNightTheme: false))
        XCTAssertEqual(manager.themes.count, count + 1)
        let saved = manager.themes.last
        XCTAssertEqual(saved?.themeName, "我的日间")
        XCTAssertEqual(saved?.isNightTheme, false)
        XCTAssertEqual(saved?.primaryColor, AppTheme.defaults[0].primaryColor)
        XCTAssertEqual(saved?.accentColor, AppTheme.defaults[0].accentColor)
    }

    func testTheCurrentNightColoursAreSavedUnderANewName() {
        let manager = ThemeManager(themes: AppTheme.defaults, selectedIndex: 0)
        let night = AppTheme.defaults.first { $0.isNightTheme }
        XCTAssertNotNil(night)
        XCTAssertTrue(manager.saveCurrentTheme(name: "我的夜间", isNightTheme: true))
        let saved = manager.themes.last
        XCTAssertEqual(saved?.themeName, "我的夜间")
        XCTAssertEqual(saved?.isNightTheme, true)
        XCTAssertEqual(saved?.primaryColor, night?.primaryColor)
    }

    func testAThemeWithoutANameIsNotSaved() {
        let manager = ThemeManager(themes: AppTheme.defaults, selectedIndex: 0)
        let count = manager.themes.count
        XCTAssertFalse(manager.saveCurrentTheme(name: "", isNightTheme: false))
        XCTAssertEqual(manager.themes.count, count)
    }
}
