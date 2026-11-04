import XCTest

@testable import LegadoCore

/// The per-chapter source change (章节换源) — the port of
/// `ui/book/changesource/ChangeChapterSourceDialog.kt` and
/// `ChangeChapterSourceViewModel.kt`.
final class ChangeChapterSourceTests: XCTestCase {

    // MARK: - The helpers

    private func chapter(_ index: Int64, _ title: String) -> BookChapter {
        BookChapter(
            url: "https://example.com/\(index)",
            title: title,
            isVolume: false,
            bookUrl: "https://example.com/book",
            index: index
        )
    }

    private func makeSource() -> BookSource {
        BookSource(
            bookSourceUrl: "https://example.com",
            bookSourceName: "示例书源",
            enabled: true,
            ruleToc: "{\"chapterList\":\"div.chapter\",\"chapterName\":\"a.title@text\",\"chapterUrl\":\"a@href\"}",
            ruleContent: "{\"content\":\"div.content@text\"}"
        )
    }

    private func makeDependencies(_ body: @escaping @Sendable (HttpRequest) -> String) -> AnalyzeUrlDependencies {
        let client = StubHttpClient { request in
            HttpResponse(url: request.url, body: body(request))
        }
        return AnalyzeUrlDependencies(httpClient: client)
    }

    // MARK: - The matching chapter

    func testTheMatchingChapterIsFoundInTheListOfTheOtherSource() async throws {
        let book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        let toc = (1...20).map { chapter(Int64($0), "第\($0)章 标题\($0)") }
        let candidate = ChangeSourceCandidate(
            book: book,
            sourceUrl: "https://example.com",
            sourceName: "示例书源",
            toc: toc
        )

        let match = try await ChangeChapterSourceService.loadMatch(
            candidate: candidate,
            source: makeSource(),
            chapterIndex: 4,
            chapterTitle: "第5章 标题5",
            oldChapterCount: 20,
            dependencies: makeDependencies { _ in "" }
        )

        XCTAssertEqual(match.durChapterIndex, 4)
        XCTAssertEqual(match.toc.count, 20)
        XCTAssertEqual(match.sourceUrl, "https://example.com")
    }

    func testTheTableOfContentsIsLoadedWhenTheCandidateHasNone() async throws {
        var book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        book.tocUrl = "https://example.com/toc"
        let candidate = ChangeSourceCandidate(
            book: book,
            sourceUrl: "https://example.com",
            sourceName: "示例书源"
        )

        let body: @Sendable (HttpRequest) -> String = { request in
            """
            <div class="chapter"><a class="title" href="/1">第一章</a></div>
            <div class="chapter"><a class="title" href="/2">第二章</a></div>
            <div class="chapter"><a class="title" href="/3">第三章</a></div>
            """
        }

        let match = try await ChangeChapterSourceService.loadMatch(
            candidate: candidate,
            source: makeSource(),
            chapterIndex: 1,
            chapterTitle: "第二章",
            oldChapterCount: 3,
            dependencies: makeDependencies(body)
        )

        XCTAssertEqual(match.toc.count, 3)
        // The second chapter of the other source matches the second chapter of
        // the current book.
        XCTAssertEqual(match.durChapterIndex, 1)
    }

    func testTheMatchingChapterFallsBackToTheNumberOfTheChapter() async throws {
        let book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        // The title of the other source is different, so only the number can
        // match.
        let toc = (1...10).map { chapter(Int64($0), "第\($0)章 别的标题\($0)") }
        let candidate = ChangeSourceCandidate(
            book: book,
            sourceUrl: "https://example.com",
            sourceName: "示例书源",
            toc: toc
        )

        let match = try await ChangeChapterSourceService.loadMatch(
            candidate: candidate,
            source: makeSource(),
            chapterIndex: 6,
            chapterTitle: "第7章 原标题",
            oldChapterCount: 10,
            dependencies: makeDependencies { _ in "" }
        )

        XCTAssertEqual(match.durChapterIndex, 6)
    }

    // MARK: - The content

    func testTheContentIsFetchedFromTheOtherSource() async throws {
        var book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        book.tocUrl = "https://example.com/toc"
        let toc = [chapter(1, "第一章"), chapter(2, "第二章")]
        let candidate = ChangeSourceCandidate(
            book: book,
            sourceUrl: "https://example.com",
            sourceName: "示例书源",
            toc: toc
        )
        let match = ChapterSourceMatch(
            book: book,
            sourceUrl: "https://example.com",
            sourceName: "示例书源",
            toc: toc,
            durChapterIndex: 0
        )

        let body: @Sendable (HttpRequest) -> String = { _ in
            "<div class=\"content\">来自另一个书源的正文</div>"
        }

        let content = try await ChangeChapterSourceService.content(
            match: match,
            source: makeSource(),
            chapter: toc[0],
            dependencies: makeDependencies(body)
        )

        XCTAssertTrue(content.contains("来自另一个书源的正文"))
    }

    func testAFailingSourceReportsTheError() async {
        let book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        let toc = [chapter(1, "第一章")]
        let match = ChapterSourceMatch(
            book: book,
            sourceUrl: "https://example.com",
            sourceName: "示例书源",
            toc: toc,
            durChapterIndex: 0
        )

        do {
            _ = try await ChangeChapterSourceService.content(
                match: match,
                source: makeSource(),
                chapter: toc[0],
                dependencies: AnalyzeUrlDependencies(httpClient: FailingHttpClient())
            )
            XCTFail("the error should be reported")
        } catch let error as ChangeChapterSourceService.Error {
            guard case .contentFailed = error else {
                return XCTFail("the error should be a content failure")
            }
        } catch {
            XCTFail("the error should be a content failure, got \(error)")
        }
    }

    // MARK: - The next chapter

    func testTheNextChapterIsTheOneAfterTheCurrentOne() {
        let toc = [chapter(1, "第一章"), chapter(2, "第二章"), chapter(3, "第三章")]
        XCTAssertEqual(
            ChangeChapterSourceService.nextChapterUrl(in: toc, after: 0),
            "https://example.com/2"
        )
        XCTAssertEqual(
            ChangeChapterSourceService.nextChapterUrl(in: toc, after: 1),
            "https://example.com/3"
        )
        // The last chapter has no next one.
        XCTAssertNil(ChangeChapterSourceService.nextChapterUrl(in: toc, after: 2))
        XCTAssertNil(ChangeChapterSourceService.nextChapterUrl(in: toc, after: 9))
    }
}

/// An HTTP client that always fails.
private final class FailingHttpClient: HttpClient, @unchecked Sendable {
    struct Failure: Error {}
    func send(_ request: HttpRequest) async throws -> HttpResponse {
        throw Failure()
    }
}
