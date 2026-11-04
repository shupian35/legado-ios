import XCTest

@testable import LegadoCore

/// The deep links that do not import a JSON document — upstream
/// `OnLineImportActivity.kt` and `AddToBookshelfDialog.kt`.
final class DeepLinkActionTests: XCTestCase {

    private func makeStore() -> LegadoStore {
        LegadoStore(tables: MemoryTableStore())
    }

    // MARK: - The action of a path

    func testThePathsSelectTheAction() {
        XCTAssertEqual(DeepLinkService.action(forPath: "/bookSource", host: "import"), .importJSON(.bookSource))
        XCTAssertEqual(DeepLinkService.action(forPath: "/rssSource", host: "import"), .importJSON(.rssSource))
        XCTAssertEqual(DeepLinkService.action(forPath: "/replaceRule", host: "import"), .importJSON(.replaceRule))
        XCTAssertEqual(DeepLinkService.action(forPath: "/textTocRule", host: "import"), .importJSON(.txtRule))
        XCTAssertEqual(DeepLinkService.action(forPath: "/httpTTS", host: "import"), .importJSON(.httpTts))
        XCTAssertEqual(DeepLinkService.action(forPath: "/dictRule", host: "import"), .importJSON(.dictRule))
        XCTAssertEqual(DeepLinkService.action(forPath: "/theme", host: "import"), .importTheme)
        XCTAssertEqual(DeepLinkService.action(forPath: "/readConfig", host: "import"), .importReadConfig)
        XCTAssertEqual(DeepLinkService.action(forPath: "/addToBookshelf", host: "import"), .addToBookshelf)
    }

    func testTheImportOnlineHostsSelectTheJsonImports() {
        XCTAssertEqual(DeepLinkService.action(forPath: "/importonline", host: "booksource"), .importJSON(.bookSource))
        XCTAssertEqual(DeepLinkService.action(forPath: "/importonline", host: "rsssource"), .importJSON(.rssSource))
        XCTAssertEqual(DeepLinkService.action(forPath: "/importonline", host: "replace"), .importJSON(.replaceRule))
        XCTAssertNil(DeepLinkService.action(forPath: "/importonline", host: "other"))
    }

    func testAnUnknownPathHasNoAction() {
        XCTAssertNil(DeepLinkService.action(forPath: "/whatever", host: "import"))
    }

    // MARK: - The download

    func testTheDownloadSendsTheUserAgent() async throws {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: "hello")
        }
        let request = DeepLinkRequest(path: "/theme", host: "import", source: "https://example.com/theme.json")
        let data = try await DeepLinkService.download(from: request, httpClient: stub, userAgent: "UA")
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hello")
        XCTAssertEqual(stub.requests.count, 1)
        XCTAssertEqual(stub.requests[0].headers["User-Agent"], "UA")
    }

    func testTheDownloadWithoutTheUserAgentMarker() async throws {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: "hello")
        }
        let request = DeepLinkRequest(
            path: "/theme",
            host: "import",
            source: "https://example.com/theme.json" + DeepLink.requestWithoutUserAgent
        )
        _ = try await DeepLinkService.download(from: request, httpClient: stub, userAgent: "UA")
        XCTAssertEqual(stub.requests[0].headers["User-Agent"], "null")
        XCTAssertEqual(stub.requests[0].url, "https://example.com/theme.json")
    }

    func testAFailedDownloadIsReported() async {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, code: 404, message: "Not Found")
        }
        let request = DeepLinkRequest(path: "/theme", host: "import", source: "https://example.com/theme.json")
        do {
            _ = try await DeepLinkService.download(from: request, httpClient: stub, userAgent: "UA")
            XCTFail("the download should fail")
        } catch {
            XCTAssertTrue(error is DeepLinkError)
        }
    }

    // MARK: - The theme

    func testTheThemeIsImported() async throws {
        let json = ThemeManager.exportJSON(
            AppTheme(
                themeName: "夜色",
                isNightTheme: true,
                primaryColor: "#112233",
                accentColor: "#445566",
                backgroundColor: "#778899",
                bottomBackground: "#aabbcc"
            )
        )
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: json)
        }
        let request = DeepLinkRequest(path: "/theme", host: "import", source: "https://example.com/theme.json")
        let theme = try await DeepLinkService.importTheme(from: request, httpClient: stub, userAgent: "UA")
        XCTAssertEqual(theme.themeName, "夜色")
        XCTAssertTrue(theme.isNightTheme)
    }

    func testABrokenThemeIsRefused() async {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: "not a theme")
        }
        let request = DeepLinkRequest(path: "/theme", host: "import", source: "https://example.com/theme.json")
        do {
            _ = try await DeepLinkService.importTheme(from: request, httpClient: stub, userAgent: "UA")
            XCTFail("the theme should be refused")
        } catch {
            XCTAssertEqual(error as? DeepLinkActionError, .invalidTheme)
        }
    }

    // MARK: - The reader style

    func testTheReaderStyleIsImported() async throws {
        var config = ReaderConfig()
        config.textSize = 22
        let archive = try ReaderConfigArchive.archive(config: config, font: nil)
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, data: archive)
        }
        let request = DeepLinkRequest(path: "/readConfig", host: "import", source: "https://example.com/readConfig.zip")
        let payload = try await DeepLinkService.importReadConfig(from: request, httpClient: stub, userAgent: "UA")
        XCTAssertEqual(payload.config.textSize, 22)
    }

    func testABrokenReaderStyleIsRefused() async {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: "not an archive")
        }
        let request = DeepLinkRequest(path: "/readConfig", host: "import", source: "https://example.com/readConfig.zip")
        do {
            _ = try await DeepLinkService.importReadConfig(from: request, httpClient: stub, userAgent: "UA")
            XCTFail("the archive should be refused")
        } catch {
            XCTAssertEqual(error as? DeepLinkActionError, .invalidReadConfig)
        }
    }

    // MARK: - The bookshelf

    func testTheBookOnTheShelfIsRefused() async throws {
        let store = makeStore()
        try store.insert([
            Book(bookUrl: "https://example.com/book/1", name: "书", author: "作者")
        ])
        do {
            _ = try await DeepLinkService.addToBookshelf(
                bookUrl: "https://example.com/book/1",
                store: store,
                sources: []
            )
            XCTFail("the book should be refused")
        } catch {
            XCTAssertEqual(error as? DeepLinkActionError, .alreadyOnShelf("书"))
        }
    }

    func testAMalformedBookUrlIsRefused() async throws {
        do {
            _ = try await DeepLinkService.addToBookshelf(
                bookUrl: "not a url",
                store: makeStore(),
                sources: []
            )
            XCTFail("the url should be refused")
        } catch {
            XCTAssertEqual(error as? DeepLinkActionError, .malformedBookUrl)
        }
    }

    func testNoMatchingSourceIsRefused() async throws {
        do {
            _ = try await DeepLinkService.addToBookshelf(
                bookUrl: "https://example.com/book/1",
                store: makeStore(),
                sources: [
                    BookSource(bookSourceUrl: "https://other.com", bookSourceName: "别的源")
                ]
            )
            XCTFail("the book should be refused")
        } catch {
            XCTAssertEqual(error as? DeepLinkActionError, .noMatchingSource)
        }
    }

    func testTheSourceOfTheBaseUrlIsUsed() async throws {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: "<html><body></body></html>")
        }
        let source = BookSource(bookSourceUrl: "https://example.com", bookSourceName: "源")
        let result = try await DeepLinkService.addToBookshelf(
            bookUrl: "https://example.com/book/1",
            store: makeStore(),
            sources: [source],
            dependencies: AnalyzeUrlDependencies(httpClient: stub)
        )
        XCTAssertEqual(result.source.bookSourceUrl, "https://example.com")
        XCTAssertEqual(result.book.bookUrl, "https://example.com/book/1")
        XCTAssertEqual(result.book.origin, "https://example.com")
    }

    func testTheSourceOfTheOptionBlockIsUsedFirst() async throws {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: "<html><body></body></html>")
        }
        // The option block of the url names the source of the book.
        let bookUrl = "https://example.com/book/1,{\"origin\":\"https://named.com\"}"
        let source = BookSource(bookSourceUrl: "https://named.com", bookSourceName: "指定的源")
        let result = try await DeepLinkService.addToBookshelf(
            bookUrl: bookUrl,
            store: makeStore(),
            sources: [source],
            dependencies: AnalyzeUrlDependencies(httpClient: stub)
        )
        XCTAssertEqual(result.source.bookSourceUrl, "https://named.com")
    }

    func testTheSourceOfThePatternIsUsedLast() async throws {
        let stub = StubHttpClient { request in
            HttpResponse(url: request.url, body: "<html><body></body></html>")
        }
        let source = BookSource(
            bookSourceUrl: "https://pattern.com",
            bookSourceName: "正则的源",
            bookUrlPattern: "https://example\\.com/book/.*"
        )
        let result = try await DeepLinkService.addToBookshelf(
            bookUrl: "https://example.com/book/1",
            store: makeStore(),
            sources: [source],
            dependencies: AnalyzeUrlDependencies(httpClient: stub)
        )
        XCTAssertEqual(result.source.bookSourceUrl, "https://pattern.com")
    }

    func testADisabledSourceIsNotUsed() async throws {
        let source = BookSource(
            bookSourceUrl: "https://example.com",
            bookSourceName: "源",
            enabled: false
        )
        do {
            _ = try await DeepLinkService.addToBookshelf(
                bookUrl: "https://example.com/book/1",
                store: makeStore(),
                sources: [source]
            )
            XCTFail("the book should be refused")
        } catch {
            XCTAssertEqual(error as? DeepLinkActionError, .noMatchingSource)
        }
    }
}
