//
//  StorageTests.swift
//  LegadoCoreTests
//
//  Tests for the storage layer (schema, in-memory table store), the repository
//  layer (`LegadoStore`, the counterpart of the upstream Room DAOs) and the
//  model layer (row mapping, group helpers, rule decoding).
//
//  Upstream reference: app/src/main/java/io/legado/app/data/AppDatabase.kt,
//  app/src/main/java/io/legado/app/data/DatabaseMigrations.kt,
//  app/src/main/java/io/legado/app/data/dao/*.kt,
//  app/src/main/java/io/legado/app/data/entities/*.kt
//

import XCTest
@testable import LegadoCore

// MARK: - Schema

final class LegadoSchemaTests: XCTestCase {

    func testSchemaVersionMatchesTheUpstreamRoomVersion() {
        XCTAssertEqual(LegadoSchema.version, 75)
    }

    func testSchemaContainsEveryUpstreamTable() {
        let names = Set(LegadoSchema.tables.map(\.name))
        let expected: Set<String> = [
            "books", "book_groups", "book_sources", "chapters", "replace_rules",
            "searchBooks", "search_keywords", "cookies", "rssSources", "bookmarks",
            "rssArticles", "rssReadRecords", "rssStars", "txtTocRules", "readRecord",
            "httpTTS", "caches", "ruleSubs", "dictRules", "keyboardAssists", "servers"
        ]
        XCTAssertEqual(names, expected)
    }

    func testBooksPrimaryKeyAndUniqueIndex() {
        let books = LegadoSchema.table("books")
        XCTAssertNotNil(books)
        XCTAssertEqual(books?.primaryKey, ["bookUrl"])
        let indexes = books?.createIndexStatements ?? []
        XCTAssertTrue(indexes.contains { $0.contains("index_books_name_author") })
    }

    func testChaptersCascadeToBooks() {
        let chapters = LegadoSchema.table("chapters")
        XCTAssertNotNil(chapters)
        XCTAssertEqual(chapters?.primaryKey, ["url", "bookUrl"])
        let statement = chapters?.createStatement ?? ""
        XCTAssertTrue(statement.contains("FOREIGN KEY"))
        XCTAssertTrue(statement.contains("CASCADE"))
    }

    func testDefaultGroupsMatchTheUpstreamWellKnownIds() {
        let ids = LegadoSchema.defaultGroups.map(\.id).sorted()
        XCTAssertEqual(ids, [-11, -5, -4, -3, -2, -1])
    }

    func testDefaultGroupsMatchTheUpstreamSeed() {
        // Upstream `AppDatabase.dbCallback.onCreate` inserts the six groups
        // with these ids, names, orders and show flags.
        let groups = LegadoSchema.defaultGroups
        XCTAssertEqual(groups.count, 6)
        XCTAssertEqual(groups[0].id, BookGroup.Id.all)
        XCTAssertEqual(groups[0].name, "全部")
        XCTAssertEqual(groups[0].order, -10)
        XCTAssertEqual(groups[1].id, BookGroup.Id.local)
        XCTAssertEqual(groups[1].name, "本地")
        XCTAssertEqual(groups[1].order, -9)
        XCTAssertFalse(groups[1].enableRefresh)
        XCTAssertEqual(groups[2].id, BookGroup.Id.audio)
        XCTAssertEqual(groups[2].name, "音频")
        XCTAssertEqual(groups[2].order, -8)
        XCTAssertEqual(groups[3].id, BookGroup.Id.netNoGroup)
        XCTAssertEqual(groups[3].name, "网络未分组")
        XCTAssertEqual(groups[3].order, -7)
        XCTAssertEqual(groups[4].id, BookGroup.Id.localNoGroup)
        XCTAssertEqual(groups[4].name, "本地未分组")
        XCTAssertEqual(groups[4].order, -6)
        XCTAssertFalse(groups[4].enableRefresh)
        XCTAssertFalse(groups[4].show)
        XCTAssertEqual(groups[5].id, BookGroup.Id.updateError)
        XCTAssertEqual(groups[5].name, "更新失败")
        XCTAssertEqual(groups[5].order, -1)
    }
}

// MARK: - MemoryTableStore

final class MemoryTableStoreTests: XCTestCase {

    private func makeStore() throws -> MemoryTableStore {
        let store = MemoryTableStore()
        try store.createSchema()
        return store
    }

    func testInsertAndReadBack() throws {
        let store = try makeStore()
        try store.insert(["bookUrl": .text("u1"), "name": .text("Book")], into: "books")
        let rows = try store.rows(in: "books", where: .all, orderBy: [])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["name"]?.stringValue, "Book")
    }

    func testInsertReplacesOnThePrimaryKey() throws {
        let store = try makeStore()
        try store.insert(["bookUrl": .text("u1"), "name": .text("A")], into: "books")
        try store.insert(["bookUrl": .text("u1"), "name": .text("B")], into: "books")
        let rows = try store.rows(in: "books", where: .all, orderBy: [])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["name"]?.stringValue, "B")
    }

    func testEqualsPredicate() throws {
        let store = try makeStore()
        try store.insert(["bookUrl": .text("u1"), "name": .text("A")], into: "books")
        try store.insert(["bookUrl": .text("u2"), "name": .text("B")], into: "books")
        let rows = try store.rows(
            in: "books",
            where: .equals(column: "name", value: .text("B")),
            orderBy: []
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["bookUrl"]?.stringValue, "u2")
    }

    func testBitwiseAndNotZeroMatchesTheUpstreamGroupModel() throws {
        let store = try makeStore()
        try store.insert(["bookUrl": .text("u1"), "group": .integer(0b0100)], into: "books")
        try store.insert(["bookUrl": .text("u2"), "group": .integer(0b0001)], into: "books")
        let rows = try store.rows(
            in: "books",
            where: .bitwiseAndNotZero(column: "group", mask: 0b0100),
            orderBy: []
        )
        XCTAssertEqual(rows.map { $0["bookUrl"]?.stringValue }, ["u1"])
    }

    func testAllOfCombinesPredicates() throws {
        let store = try makeStore()
        try store.insert(
            ["bookSourceUrl": .text("https://s1"), "bookSourceName": .text("A"), "enabled": .integer(1)],
            into: "book_sources"
        )
        try store.insert(
            ["bookSourceUrl": .text("https://s2"), "bookSourceName": .text("B"), "enabled": .integer(0)],
            into: "book_sources"
        )
        let rows = try store.rows(
            in: "book_sources",
            where: .allOf([
                .equals(column: "enabled", value: .integer(1)),
                .equals(column: "bookSourceName", value: .text("A"))
            ]),
            orderBy: []
        )
        XCTAssertEqual(rows.count, 1)
    }

    func testOrderByAscendingAndDescending() throws {
        let store = try makeStore()
        try store.insert(["bookUrl": .text("u1"), "order": .integer(2)], into: "books")
        try store.insert(["bookUrl": .text("u2"), "order": .integer(1)], into: "books")
        let ascending = try store.rows(in: "books", where: .all, orderBy: [OrderTerm(column: "order")])
        XCTAssertEqual(ascending.map { $0["bookUrl"]?.stringValue }, ["u2", "u1"])
        let descending = try store.rows(
            in: "books",
            where: .all,
            orderBy: [OrderTerm(column: "order", descending: true)]
        )
        XCTAssertEqual(descending.map { $0["bookUrl"]?.stringValue }, ["u1", "u2"])
    }

    func testDeleteByPredicate() throws {
        let store = try makeStore()
        try store.insert(["bookUrl": .text("u1")], into: "books")
        try store.insert(["bookUrl": .text("u2")], into: "books")
        let removed = try store.delete(from: "books", where: .equals(column: "bookUrl", value: .text("u1")))
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(try store.rows(in: "books", where: .all, orderBy: []).count, 1)
    }

    func testTransactionRollsBackOnError() throws {
        let store = try makeStore()
        try store.insert(["bookUrl": .text("u1")], into: "books")
        struct Boom: Error {}
        XCTAssertThrowsError(try store.transaction {
            try store.insert(["bookUrl": .text("u2")], into: "books")
            throw Boom()
        })
        let rows = try store.rows(in: "books", where: .all, orderBy: [])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?["bookUrl"]?.stringValue, "u1")
    }

    func testDeleteAll() throws {
        let store = try makeStore()
        try store.insert(["bookUrl": .text("u1")], into: "books")
        try store.deleteAll(from: "books")
        XCTAssertEqual(try store.rows(in: "books", where: .all, orderBy: []).count, 0)
    }
}

// MARK: - LegadoStore (repository)

final class LegadoStoreTests: XCTestCase {

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        try store.seedDefaultGroups()
        return store
    }

    func testSeedDefaultGroups() throws {
        let store = try makeStore()
        let groups = try store.allGroups()
        XCTAssertEqual(groups.count, 6)
        XCTAssertTrue(groups.contains { $0.groupId == BookGroup.Id.all })
        XCTAssertTrue(groups.contains { $0.groupName == "全部" })
    }

    func testBookRoundTrip() throws {
        let store = try makeStore()
        let book = Book(bookUrl: "u1", name: "Novel", author: "Author", group: 0b0010)
        try store.insert(book)
        let loaded = try store.book(url: "u1")
        XCTAssertEqual(loaded?.name, "Novel")
        XCTAssertEqual(loaded?.author, "Author")
        XCTAssertEqual(try store.allBooks().count, 1)
    }

    func testUpdateProgressAndLastReadBook() throws {
        let store = try makeStore()
        var book = Book(bookUrl: "u1", name: "Novel", author: "Author")
        try store.insert(book)
        book.durChapterIndex = 12
        book.durChapterPos = 34
        book.durChapterTitle = "Chapter 13"
        book.durChapterTime = 1_700_000_000
        try store.updateProgress(book: book)
        let loaded = try store.book(url: "u1")
        XCTAssertEqual(loaded?.durChapterIndex, 12)
        XCTAssertEqual(loaded?.durChapterPos, 34)
        XCTAssertEqual(try store.lastReadBook()?.bookUrl, "u1")
    }

    func testBooksInGroupUsesTheBitmask() throws {
        let store = try makeStore()
        try store.insert(Book(bookUrl: "u1", group: 0b0001))
        try store.insert(Book(bookUrl: "u2", group: 0b0010))
        try store.insert(Book(bookUrl: "u3", group: 0b0011))
        let first = try store.books(inGroup: 0b0001)
        XCTAssertEqual(Set(first.map(\.bookUrl)), ["u1", "u3"])
    }

    func testBooksWithoutGroupUsesTheSumTrick() throws {
        let store = try makeStore()
        // A user group has a positive (power of two) id; the well known groups
        // are negative and therefore ignored by the upstream `sum(groupId)`.
        try store.insert(BookGroup(groupId: 2, groupName: "Mine"))
        try store.insert(Book(bookUrl: "u1", group: 0))
        try store.insert(Book(bookUrl: "u2", group: 0b0010))
        let ungrouped = try store.booksWithoutGroup()
        XCTAssertEqual(ungrouped.map(\.bookUrl), ["u1"])
    }

    func testLocalAndAudioBooks() throws {
        let store = try makeStore()
        try store.insert(Book(bookUrl: "u1", type: BookType.local))
        try store.insert(Book(bookUrl: "u2", type: BookType.audio))
        try store.insert(Book(bookUrl: "u3", type: BookType.text))
        XCTAssertEqual(try store.localBooks().map(\.bookUrl), ["u1"])
        XCTAssertEqual(try store.audioBooks().map(\.bookUrl), ["u2"])
    }

    func testDeleteBookAlsoDeletesItsChapters() throws {
        let store = try makeStore()
        try store.insert(Book(bookUrl: "u1"))
        try store.insert([
            BookChapter(url: "c1", title: "One", bookUrl: "u1", index: 0),
            BookChapter(url: "c2", title: "Two", bookUrl: "u1", index: 1)
        ])
        try store.delete(bookUrl: "u1")
        XCTAssertNil(try store.book(url: "u1"))
        XCTAssertEqual(try store.chapters(bookUrl: "u1").count, 0)
    }

    func testChaptersAreOrderedByIndex() throws {
        let store = try makeStore()
        try store.insert(Book(bookUrl: "u1"))
        try store.insert([
            BookChapter(url: "c2", title: "Two", bookUrl: "u1", index: 1),
            BookChapter(url: "c1", title: "One", bookUrl: "u1", index: 0)
        ])
        let chapters = try store.chapters(bookUrl: "u1")
        XCTAssertEqual(chapters.map(\.title), ["One", "Two"])
    }

    func testSourcesEnabledAndDeleted() throws {
        let store = try makeStore()
        var source = BookSource(bookSourceUrl: "https://s1", bookSourceName: "S1", enabled: true)
        try store.insert(source)
        source = BookSource(bookSourceUrl: "https://s2", bookSourceName: "S2", enabled: false)
        try store.insert(source)
        XCTAssertEqual(try store.allSources().count, 2)
        XCTAssertEqual(try store.enabledSources().map(\.bookSourceUrl), ["https://s1"])
        try store.setSourcesEnabled(false, urls: ["https://s1"])
        XCTAssertTrue(try store.enabledSources().isEmpty)
        try store.deleteSources(urls: ["https://s1"])
        XCTAssertEqual(try store.allSources().map(\.bookSourceUrl), ["https://s2"])
    }

    func testSearchBooksAndExpiry() throws {
        let store = try makeStore()
        try store.insert([
            SearchBook(bookUrl: "b1", origin: "https://s1", name: "N", time: 100),
            SearchBook(bookUrl: "b2", origin: "https://s1", name: "M", time: 200)
        ])
        XCTAssertEqual(try store.searchBooks(origin: "https://s1").count, 2)
        try store.clearExpiredSearchBooks(before: 150)
        let remaining = try store.searchBooks(origin: "https://s1")
        XCTAssertEqual(remaining.map(\.bookUrl), ["b2"])
    }

    func testCacheHonoursTheDeadline() throws {
        let store = try makeStore()
        try store.putCache("k", value: "v", deadline: 100)
        XCTAssertEqual(try store.cache("k", now: 50), "v")
        XCTAssertNil(try store.cache("k", now: 150))
    }

    func testCacheWithZeroDeadlineNeverExpires() throws {
        let store = try makeStore()
        try store.putCache("k", value: "v", deadline: 0)
        XCTAssertEqual(try store.cache("k", now: Int64.max), "v")
    }

    func testClearExpiredCaches() throws {
        let store = try makeStore()
        try store.putCache("old", value: "v", deadline: 10)
        try store.putCache("new", value: "v", deadline: 1_000)
        try store.clearExpiredCaches(now: 100)
        XCTAssertNil(try store.cache("old", now: 100))
        XCTAssertEqual(try store.cache("new", now: 100), "v")
    }

    func testDeleteSourceVariablesWipesEveryPrefix() throws {
        let store = try makeStore()
        try store.putCache("v_abc_1", value: "1", deadline: 0)
        try store.putCache("userInfo_abc", value: "2", deadline: 0)
        try store.putCache("loginHeader_abc", value: "3", deadline: 0)
        try store.putCache("sourceVariable_abc", value: "4", deadline: 0)
        try store.putCache("keep", value: "5", deadline: 0)
        try store.deleteSourceVariables(key: "abc")
        XCTAssertNil(try store.cache("v_abc_1", now: 0))
        XCTAssertNil(try store.cache("userInfo_abc", now: 0))
        XCTAssertNil(try store.cache("loginHeader_abc", now: 0))
        XCTAssertNil(try store.cache("sourceVariable_abc", now: 0))
        XCTAssertEqual(try store.cache("keep", now: 0), "5")
    }

    func testCookiesAndReplaceRulesAndBookmarks() throws {
        let store = try makeStore()
        try store.insert(Cookie(url: "https://a", cookie: "n=v"))
        XCTAssertEqual(try store.cookie(url: "https://a"), "n=v")

        try store.insert(ReplaceRule(id: 1, name: "r", pattern: "p", replacement: "x"))
        XCTAssertEqual(try store.allReplaceRules().count, 1)
        try store.deleteReplaceRule(id: 1)
        XCTAssertTrue(try store.allReplaceRules().isEmpty)

        try store.insert(Bookmark(time: 0, bookName: "N", bookAuthor: "A", chapterIndex: 1))
        XCTAssertEqual(try store.bookmarks(bookName: "N", bookAuthor: "A").count, 1)
    }

    func testReadRecord() throws {
        let store = try makeStore()
        try store.insert(ReadRecord(deviceId: "d1", bookName: "N", readTime: 10, lastRead: 20))
        let record = try store.readRecord(deviceId: "d1", bookName: "N")
        XCTAssertEqual(record?.readTime, 10)
        XCTAssertEqual(record?.lastRead, 20)
    }

    func testRssTables() throws {
        let store = try makeStore()
        try store.insert(RssSource(sourceUrl: "https://r", sourceName: "R"))
        XCTAssertEqual(try store.allRssSources().count, 1)
        try store.insert([RssArticle(origin: "https://r", sort: "s", title: "T", link: "https://r/1")])
        XCTAssertEqual(try store.rssArticles(origin: "https://r").count, 1)
        try store.insert(RssStar(origin: "https://r", sort: "s", title: "T", link: "https://r/1"))
        XCTAssertEqual(try store.allRssStars().count, 1)
    }

    // MARK: - The replace rule scope queries

    func testTheContentScopeQueryMatchesTheBookName() throws {
        let store = try makeStore()
        try store.insert(ReplaceRule(name: "按书名", pattern: "a", scope: "书名"))
        try store.insert(ReplaceRule(name: "按来源", pattern: "b", scope: "https://origin"))
        try store.insert(ReplaceRule(name: "其它", pattern: "c", scope: "别的书"))
        let rules = try store.replaceRulesForContent(name: "书名", origin: "https://other")
        XCTAssertEqual(rules.map(\.name), ["按书名"])
    }

    func testTheContentScopeQueryMatchesTheOrigin() throws {
        let store = try makeStore()
        try store.insert(ReplaceRule(name: "按来源", pattern: "b", scope: "https://origin"))
        let rules = try store.replaceRulesForContent(name: "别的书", origin: "https://origin")
        XCTAssertEqual(rules.map(\.name), ["按来源"])
    }

    func testAnEmptyScopeAppliesToEveryBook() throws {
        let store = try makeStore()
        try store.insert(ReplaceRule(name: "全局", pattern: "a"))
        let rules = try store.replaceRulesForContent(name: "任意", origin: "任意")
        XCTAssertEqual(rules.map(\.name), ["全局"])
    }

    func testTheExcludeScopeRemovesAMatchingRule() throws {
        let store = try makeStore()
        try store.insert(ReplaceRule(name: "排除", pattern: "a", scope: "书名", excludeScope: "书名"))
        let rules = try store.replaceRulesForContent(name: "书名", origin: "")
        XCTAssertTrue(rules.isEmpty)
    }

    func testTheTitleScopeQueryOnlyReturnsTitleRules() throws {
        let store = try makeStore()
        try store.insert(ReplaceRule(name: "标题规则", pattern: "a", scopeTitle: true, scopeContent: false))
        try store.insert(ReplaceRule(name: "正文规则", pattern: "b", scopeTitle: false, scopeContent: true))
        XCTAssertEqual(try store.replaceRulesForTitle(name: "书名", origin: "").map(\.name), ["标题规则"])
        XCTAssertEqual(try store.replaceRulesForContent(name: "书名", origin: "").map(\.name), ["正文规则"])
    }

    func testDisabledRulesAreNotReturned() throws {
        let store = try makeStore()
        try store.insert(ReplaceRule(name: "关闭", pattern: "a", isEnabled: false))
        XCTAssertTrue(try store.replaceRulesForContent(name: "书名", origin: "").isEmpty)
    }
}

// MARK: - Models

final class ModelTests: XCTestCase {

    func testBookTypeBitMask() {
        XCTAssertTrue(BookType.contains(BookType.allBookType, BookType.text))
        XCTAssertTrue(BookType.contains(BookType.allBookType, BookType.audio))
        XCTAssertFalse(BookType.contains(BookType.allBookType, BookType.local))
        XCTAssertTrue(BookType.contains(BookType.text | BookType.local, BookType.local))
    }

    func testBookRowMappingRoundTrip() {
        let book = Book(
            bookUrl: "u1",
            name: "N",
            author: "A",
            type: BookType.text | BookType.local,
            group: 0b0011,
            durChapterIndex: 7
        )
        let restored = Book(row: book.row)
        XCTAssertEqual(restored.bookUrl, "u1")
        XCTAssertEqual(restored.name, "N")
        XCTAssertEqual(restored.type, book.type)
        XCTAssertEqual(restored.group, 0b0011)
        XCTAssertEqual(restored.durChapterIndex, 7)
    }

    func testBookIsOnShelfUsesTheNotShelfBit() {
        var book = Book(bookUrl: "u1")
        XCTAssertTrue(book.isOnShelf)
        book.type = BookType.text | BookType.notShelf
        XCTAssertFalse(book.isOnShelf)
    }

    func testBookDisplayCoverUrlPrefersTheCustomCover() {
        var book = Book(bookUrl: "u1", coverUrl: "http://origin/cover.png")
        XCTAssertEqual(book.displayCoverUrl, "http://origin/cover.png")
        book.customCoverUrl = "http://custom/cover.png"
        XCTAssertEqual(book.displayCoverUrl, "http://custom/cover.png")
    }

    func testBookSourceGroupHelpers() {
        var source = BookSource(bookSourceUrl: "https://s", bookSourceName: "S", bookSourceGroup: "A,B")
        XCTAssertEqual(source.groups, ["A", "B"])
        XCTAssertTrue(source.hasGroup("A"))
        XCTAssertFalse(source.hasGroup("C"))
        source.addGroup("C")
        XCTAssertEqual(source.groups, ["A", "B", "C"])
        source.addGroup("C")
        XCTAssertEqual(source.groups, ["A", "B", "C"])
        source.removeGroup("B")
        XCTAssertEqual(source.groups, ["A", "C"])
    }

    func testBookSourceInvalidGroups() {
        var source = BookSource(
            bookSourceUrl: "https://s",
            bookSourceName: "S",
            bookSourceGroup: "Good,失效源,超时校验超时"
        )
        XCTAssertEqual(source.invalidGroupNames.count, 2)
        source.removeInvalidGroups()
        XCTAssertEqual(source.groups, ["Good"])
    }

    func testBookSourceDecodesTheRuleColumns() {
        let searchJSON = """
        {"bookList":"div.item@href","name":"h3@text","author":"span@text"}
        """
        let source = BookSource(
            bookSourceUrl: "https://s",
            bookSourceName: "S",
            ruleSearch: searchJSON
        )
        XCTAssertEqual(source.searchRule?.bookList, "div.item@href")
        XCTAssertEqual(source.searchRule?.name, "h3@text")
        XCTAssertNil(source.tocRule)
    }

    func testBookSourceIgnoresTheNullRuleColumn() {
        let source = BookSource(
            bookSourceUrl: "https://s",
            bookSourceName: "S",
            ruleContent: "null"
        )
        XCTAssertNil(source.contentRule)
    }

    func testBookChapterRowMapping() {
        let chapter = BookChapter(url: "c1", title: "T", isVolume: true, bookUrl: "u1", index: 3)
        let restored = BookChapter(row: chapter.row)
        XCTAssertEqual(restored.url, "c1")
        XCTAssertEqual(restored.title, "T")
        XCTAssertEqual(restored.bookUrl, "u1")
        XCTAssertEqual(restored.index, 3)
        XCTAssertTrue(restored.isVolume)
    }
}
