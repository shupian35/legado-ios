import XCTest
@testable import LegadoCore

/// The RSS library — the favourites, the groups and the read records.
final class RssLibraryTests: XCTestCase {

    private func source(_ name: String, group: String? = nil) -> RssSource {
        var source = RssSource(sourceUrl: "https://rss.example/\(name)", sourceName: name)
        source.sourceGroup = group
        return source
    }

    private func article(_ title: String, link: String = "https://rss.example/1") -> RssArticle {
        RssArticle(origin: "https://rss.example", sort: "Feed", title: title, link: link)
    }

    func testTheSourceGroupsAreCounted() {
        let sources = [
            source("A", group: "新闻,技术"),
            source("B", group: "新闻"),
            source("C")
        ]
        let groups = RssLibrary.sourceGroups(sources)
        XCTAssertEqual(groups.map(\.name), ["新闻", "技术"])
        XCTAssertEqual(groups.map(\.count), [2, 1])
    }

    func testTheGroupListIsSplitOnCommas() {
        XCTAssertEqual(RssLibrary.splitGroups("a, b ,c"), ["a", "b", "c"])
        XCTAssertEqual(RssLibrary.splitGroups(nil), [])
        XCTAssertEqual(RssLibrary.splitGroups(""), [])
    }

    func testAddingAndRemovingAGroup() {
        var item = source("A")
        RssLibrary.addGroup("新闻", to: &item)
        XCTAssertEqual(item.sourceGroup, "新闻")
        RssLibrary.addGroup("技术", to: &item)
        XCTAssertEqual(item.sourceGroup, "新闻,技术")
        // Adding the same group twice does nothing.
        RssLibrary.addGroup("新闻", to: &item)
        XCTAssertEqual(item.sourceGroup, "新闻,技术")
        RssLibrary.removeGroup("新闻", from: &item)
        XCTAssertEqual(item.sourceGroup, "技术")
        RssLibrary.removeGroup("技术", from: &item)
        XCTAssertNil(item.sourceGroup)
    }

    func testTheStarGroupsUseTheDefaultGroup() {
        var star = RssStar(origin: "o", sort: "s", title: "t", link: "l")
        star.group = ""
        let groups = RssLibrary.starGroups([star])
        XCTAssertEqual(groups.map(\.name), [RssLibrary.defaultGroup])
        XCTAssertEqual(groups.map(\.count), [1])
    }

    func testTogglingTheStar() {
        let article = self.article("标题")
        let stars: [RssStar] = []
        let added = RssLibrary.toggleStar(article: article, in: stars)
        XCTAssertNotNil(added.star)
        XCTAssertEqual(added.star?.title, "标题")
        XCTAssertEqual(added.star?.group, RssLibrary.defaultGroup)
        XCTAssertTrue(added.remaining.isEmpty)

        let removed = RssLibrary.toggleStar(article: article, in: [added.star!])
        XCTAssertNil(removed.star)
        XCTAssertTrue(removed.remaining.isEmpty)
    }

    func testTheStarOfAnArticle() {
        let article = self.article("标题")
        let star = RssStar(origin: "o", sort: "s", title: "标题", link: article.link)
        XCTAssertNotNil(RssLibrary.star(of: article, in: [star]))
        XCTAssertNil(RssLibrary.star(of: article, in: []))
    }

    func testMarkingAnArticleAsRead() {
        let article = self.article("标题")
        let result = RssLibrary.markRead(article: article, in: [])
        XCTAssertTrue(result.record.read)
        XCTAssertEqual(result.record.record, article.link)
        XCTAssertEqual(result.remaining.count, 1)
    }

    func testTheUnreadArticles() {
        let a = article("A", link: "https://rss.example/a")
        let b = article("B", link: "https://rss.example/b")
        let records = [RssReadRecord(record: a.link, read: true)]
        XCTAssertEqual(RssLibrary.unread([a, b], records: records).map(\.title), ["B"])
    }

    func testTheStoreKeepsTheStarsAndTheReadRecords() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        var star = RssStar(origin: "o", sort: "s", title: "t", link: "l", group: "默认分组")
        star.starTime = 100
        try store.insert(star)
        XCTAssertEqual(try store.allRssStars().count, 1)
        XCTAssertEqual(try store.rssStars(group: "默认分组").count, 1)
        XCTAssertEqual(try store.rssStars(group: "其它").count, 0)

        try store.insert(RssReadRecord(record: "l", title: "t", readTime: 1, read: true))
        XCTAssertEqual(try store.allRssReadRecords().count, 1)
        XCTAssertEqual(try store.rssReadRecord(record: "l")?.read, true)

        try store.deleteRssStars(group: "默认分组")
        XCTAssertEqual(try store.allRssStars().count, 0)
    }
}
