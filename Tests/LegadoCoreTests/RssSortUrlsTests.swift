//
//  RssSortUrlsTests.swift
//  LegadoCoreTests
//
//  The sorts of an RSS source — upstream
//  `help/source/RssSourceExtensions.kt:17-56`.
//

import XCTest
@testable import LegadoCore

final class RssSortUrlsTests: XCTestCase {

    /// A source without a `sortUrl` has a single sort (the source address).
    func testASourceWithoutSortsFallsBackToTheSourceUrl() {
        let sorts = RssSortUrls.parse(sortUrl: nil, sourceUrl: "https://example.com/rss")
        XCTAssertEqual(sorts.count, 1)
        XCTAssertEqual(sorts[0].name, "")
        XCTAssertEqual(sorts[0].url, "https://example.com/rss")
    }

    /// An empty `sortUrl` also falls back to the source address.
    func testAnEmptySortUrlFallsBackToTheSourceUrl() {
        let sorts = RssSortUrls.parse(sortUrl: "", sourceUrl: "https://example.com/rss")
        XCTAssertEqual(sorts.count, 1)
        XCTAssertEqual(sorts[0].url, "https://example.com/rss")
    }

    /// A single `名称::网址` pair.
    func testASingleSort() {
        let sorts = RssSortUrls.parse(
            sortUrl: "最新::https://example.com/latest",
            sourceUrl: "https://example.com/rss"
        )
        XCTAssertEqual(sorts.count, 1)
        XCTAssertEqual(sorts[0].name, "最新")
        XCTAssertEqual(sorts[0].url, "https://example.com/latest")
    }

    /// The sorts are separated by `&&` or a line break.
    func testSeveralSortsAreSeparated() {
        let sorts = RssSortUrls.parse(
            sortUrl: "最新::https://example.com/a\n热门::https://example.com/b&&推荐::https://example.com/c",
            sourceUrl: "https://example.com/rss"
        )
        XCTAssertEqual(sorts.count, 3)
        XCTAssertEqual(sorts[0].name, "最新")
        XCTAssertEqual(sorts[1].name, "热门")
        XCTAssertEqual(sorts[2].name, "推荐")
        XCTAssertEqual(sorts[2].url, "https://example.com/c")
    }

    /// A relative URL is resolved against the address of the source.
    func testARelativeUrlIsResolved() {
        let sorts = RssSortUrls.parse(sortUrl: "最新::/latest", sourceUrl: "https://example.com/rss")
        XCTAssertEqual(sorts[0].url, "https://example.com/latest")
    }

    /// A `{{…}}` URL is kept as it is (it is a template).
    func testATemplateUrlIsKept() {
        let sorts = RssSortUrls.parse(
            sortUrl: "最新::{{page}}",
            sourceUrl: "https://example.com/rss"
        )
        XCTAssertEqual(sorts[0].url, "{{page}}")
    }

    /// A sort without a URL is skipped.
    func testASortWithoutAUrlIsSkipped() {
        let sorts = RssSortUrls.parse(
            sortUrl: "最新::\n热门::https://example.com/b",
            sourceUrl: "https://example.com/rss"
        )
        XCTAssertEqual(sorts.count, 1)
        XCTAssertEqual(sorts[0].name, "热门")
    }

    /// The name is the part before the first "::".
    ///
    /// The URL is resolved against the address of the source (the upstream
    /// `NetworkUtils.getAbsoluteURL`), so a URL that is not absolute becomes a
    /// path of the source.
    func testTheNameStopsAtTheFirstSeparator() {
        let sorts = RssSortUrls.parse(
            sortUrl: "a::b::https://example.com/x",
            sourceUrl: "https://example.com/rss"
        )
        XCTAssertEqual(sorts.count, 1)
        XCTAssertEqual(sorts[0].name, "a")
        XCTAssertTrue(sorts[0].url.contains("b::"))
    }
}
