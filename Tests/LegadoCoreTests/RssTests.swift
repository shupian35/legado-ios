import XCTest

@testable import LegadoCore

final class RssTests: XCTestCase {

    // MARK: - Rule based feed

    private func makeSource(
        articles: String? = "class.item",
        nextPage: String? = nil,
        title: String? = "tag.a@text",
        pubDate: String? = "class.date@text",
        description: String? = "class.desc@text",
        image: String? = nil,
        link: String? = "tag.a@href"
    ) -> RssSource {
        RssSource(
            sourceUrl: "https://example.com/rss",
            sourceName: "Example",
            sortUrl: "https://example.com/list",
            ruleArticles: articles,
            ruleNextPage: nextPage,
            ruleTitle: title,
            rulePubDate: pubDate,
            ruleDescription: description,
            ruleImage: image,
            ruleLink: link
        )
    }

    private let listHTML = """
        <html><body>
        <div class="item"><a href="/a1">Title One</a><span class="date">2024-01-01</span>\
        <p class="desc">Desc one</p></div>
        <div class="item"><a href="/a2">Title Two</a><span class="date">2024-01-02</span>\
        <p class="desc">Desc two</p></div>
        </body></html>
        """

    func testParsesArticlesWithRules() throws {
        let page = try Rss.parseArticles(
            sortName: "默认",
            sortUrl: "https://example.com/list",
            redirectUrl: "https://example.com/list",
            body: listHTML,
            rssSource: makeSource(),
            ruleData: RuleDataBox()
        )

        XCTAssertEqual(page.articles.count, 2)
        XCTAssertNil(page.nextUrl)

        let first = page.articles[0]
        XCTAssertEqual(first.title, "Title One")
        XCTAssertEqual(first.pubDate, "2024-01-01")
        XCTAssertEqual(first.description, "Desc one")
        // The link is resolved against the RSS source url.
        XCTAssertEqual(first.link, "https://example.com/a1")
        XCTAssertEqual(first.sort, "默认")
        XCTAssertEqual(first.origin, "https://example.com/rss")
    }

    func testBlankTitleDropsArticle() throws {
        let html = """
            <html><body>
            <div class="item"><span class="date">2024-01-01</span></div>
            <div class="item"><a href="/a2">Kept</a></div>
            </body></html>
            """
        let page = try Rss.parseArticles(
            sortName: "默认",
            sortUrl: "https://example.com/list",
            redirectUrl: "https://example.com/list",
            body: html,
            rssSource: makeSource(),
            ruleData: RuleDataBox()
        )

        XCTAssertEqual(page.articles.count, 1)
        XCTAssertEqual(page.articles[0].title, "Kept")
    }

    func testReversedList() throws {
        let page = try Rss.parseArticles(
            sortName: "默认",
            sortUrl: "https://example.com/list",
            redirectUrl: "https://example.com/list",
            body: listHTML,
            rssSource: makeSource(articles: "-class.item"),
            ruleData: RuleDataBox()
        )

        XCTAssertEqual(page.articles.map(\.title), ["Title Two", "Title One"])
    }

    func testDescriptionRuleEmptyKeepsNil() throws {
        let page = try Rss.parseArticles(
            sortName: "默认",
            sortUrl: "https://example.com/list",
            redirectUrl: "https://example.com/list",
            body: listHTML,
            rssSource: makeSource(description: nil),
            ruleData: RuleDataBox()
        )

        // No description rule — the content page is parsed instead.
        XCTAssertNil(page.articles[0].description)
    }

    func testNextPageRuleResolvesUrl() throws {
        let html = """
            <html><body>
            <div class="item"><a href="/a1">One</a></div>
            <a class="next" href="/list/2">next</a>
            </body></html>
            """
        let page = try Rss.parseArticles(
            sortName: "默认",
            sortUrl: "https://example.com/list",
            redirectUrl: "https://example.com/list",
            body: html,
            rssSource: makeSource(nextPage: "class.next@href"),
            ruleData: RuleDataBox()
        )

        XCTAssertEqual(page.nextUrl, "https://example.com/list/2")
    }

    func testNextPageRulePageKeepsSameUrl() throws {
        let page = try Rss.parseArticles(
            sortName: "默认",
            sortUrl: "https://example.com/list",
            redirectUrl: "https://example.com/list",
            body: listHTML,
            rssSource: makeSource(nextPage: "PAGE"),
            ruleData: RuleDataBox()
        )

        XCTAssertEqual(page.nextUrl, "https://example.com/list")
    }

    func testEmptyBodyThrows() {
        XCTAssertThrowsError(
            try Rss.parseArticles(
                sortName: "默认",
                sortUrl: "https://example.com/list",
                redirectUrl: "https://example.com/list",
                body: "  ",
                rssSource: makeSource(),
                ruleData: RuleDataBox()
            )
        ) { error in
            XCTAssertEqual(
                error as? RssError,
                .emptyBody("https://example.com/rss")
            )
        }
    }

    // MARK: - Default parser

    private let rssXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0"><channel>
        <item>
          <title>Atom One</title>
          <link>https://example.com/p/1</link>
          <description>&lt;img src="https://example.com/1.jpg"&gt; body one</description>
          <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
        </item>
        <item>
          <title>Atom Two</title>
          <link>https://example.com/p/2</link>
          <media:thumbnail url="https://example.com/2.jpg"/>
          <content:encoded>body two</content:encoded>
          <pubDate>Tue, 02 Jan 2024 00:00:00 GMT</pubDate>
        </item>
        </channel></rss>
        """

    func testDefaultParserReadsItems() throws {
        let page = try Rss.parseDefault(
            sortName: "默认",
            xml: rssXML,
            sourceUrl: "https://example.com/rss"
        )

        XCTAssertEqual(page.articles.count, 2)
        XCTAssertNil(page.nextUrl)

        let first = page.articles[0]
        XCTAssertEqual(first.title, "Atom One")
        XCTAssertEqual(first.link, "https://example.com/p/1")
        XCTAssertEqual(first.pubDate, "Mon, 01 Jan 2024 00:00:00 GMT")
        // The image is recovered from the first <img> of the description.
        XCTAssertEqual(first.image, "https://example.com/1.jpg")
        XCTAssertEqual(first.origin, "https://example.com/rss")

        let second = page.articles[1]
        XCTAssertEqual(second.image, "https://example.com/2.jpg")
        XCTAssertEqual(second.content, "body two")
    }

    func testBlankArticlesRuleFallsBackToDefaultParser() throws {
        let page = try Rss.parseArticles(
            sortName: "默认",
            sortUrl: "https://example.com/rss",
            redirectUrl: "https://example.com/rss",
            body: rssXML,
            rssSource: makeSource(articles: nil),
            ruleData: RuleDataBox()
        )

        XCTAssertEqual(page.articles.count, 2)
        XCTAssertEqual(page.articles[0].title, "Atom One")
    }

    func testImageURLFromTag() {
        XCTAssertEqual(
            Rss.imageURL(in: "before <img class=\"a\" src=\"/img/1.png\"/> after"),
            "/img/1.png"
        )
        XCTAssertNil(Rss.imageURL(in: "no image here"))
    }

    // MARK: - Model helpers

    func testArticleVariableRoundTrip() {
        var article = RssArticle(
            origin: "https://example.com/rss",
            sort: "默认",
            title: "T",
            link: "https://example.com/p/1"
        )
        article.variable = "{\"a\":\"b\"}"
        XCTAssertEqual(article.variable, "{\"a\":\"b\"}")
    }
}
