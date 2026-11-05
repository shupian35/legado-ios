//
//  LegadoStore.swift
//  LegadoCore
//
//  The repository layer — the Swift counterpart of the upstream Room DAOs in
//  `data/dao/`.
//
//  Upstream calls the DAOs directly from the view models; the port keeps the
//  same data but goes through one store so the repositories can be tested
//  against the in-memory table store.
//

import Foundation

/// The data access layer of the app.
public final class LegadoStore {
    private let tables: TableStore

    public init(tables: TableStore) {
        self.tables = tables
    }

    /// The underlying table store.
    public var tableStore: TableStore { tables }

    /// The raw rows of the `book_groups` table.
    public func groupRows() throws -> [StorageRow] {
        try tables.allRows(in: "book_groups")
    }

    /// Creates the schema and seeds the default groups — upstream
    /// `AppDatabase.dbCallback.onCreate` / `onOpen`.
    public func createSchema() throws {
        try tables.createSchema()
        try seedDefaultGroups()
    }

    /// Inserts the default book groups when they are missing.
    public func seedDefaultGroups() throws {
        for group in LegadoSchema.defaultGroups {
            let existing = try tables.firstRow(in: "book_groups", where: .equals(column: "groupId", value: .integer(group.id)))
            guard existing == nil else { continue }
            let row = BookGroup(
                groupId: group.id,
                groupName: group.name,
                order: group.order,
                enableRefresh: group.enableRefresh,
                show: group.show
            ).row
            try tables.insert(row, into: "book_groups")
        }
    }

    // MARK: - Books

    /// Every book — upstream `BookDao.all`.
    public func allBooks() throws -> [Book] {
        try tables.allRows(in: "books").map { Book(row: $0) }
    }

    /// A single book — upstream `BookDao.getByUrl`.
    public func book(url: String) throws -> Book? {
        guard let row = try tables.firstRow(in: "books", where: .equals(column: "bookUrl", value: .text(url))) else { return nil }
        return Book(row: row)
    }

    /// A single book by the name of its file — upstream
    /// `BookDao.getBookByFileName` (`select * from books where originName = ?`).
    ///
    /// The remote-book browser uses it to find the book that belongs to a
    /// file on the WebDAV server.
    public func book(originName: String) throws -> Book? {
        guard let row = try tables.firstRow(
            in: "books",
            where: .equals(column: "originName", value: .text(originName))
        ) else { return nil }
        return Book(row: row)
    }

    /// Inserts or replaces a book.
    public func insert(_ book: Book) throws {
        try tables.insert(book.row, into: "books")
    }

    /// Inserts or replaces many books.
    public func insert(_ books: [Book]) throws {
        try tables.insert(books.map { $0.row }, into: "books")
    }

    /// Updates a book.
    public func update(_ book: Book) throws {
        try tables.update(
            "books",
            set: book.row,
            where: .equals(column: "bookUrl", value: .text(book.bookUrl))
        )
    }

    /// Deletes a book — upstream `BookDao.deleteByPath`.
    public func delete(bookUrl: String) throws {
        try tables.delete(from: "books", where: .equals(column: "bookUrl", value: .text(bookUrl)))
        try tables.delete(from: "chapters", where: .equals(column: "bookUrl", value: .text(bookUrl)))
    }

    /// The books of a group — upstream `BookDao.flowByGroup`.
    ///
    /// The well known group ids dispatch to their own query, every other id
    /// is a user group whose id is a bit of the `group` column.
    /// Upstream filters the books that are not on the shelf out of every
    /// branch.
    public func books(inGroup groupId: Int64) throws -> [Book] {
        let books: [Book]
        switch groupId {
        case BookGroup.Id.root:
            books = try rootBooks()
        case BookGroup.Id.all:
            books = try allBooks()
        case BookGroup.Id.local:
            books = try localBooks()
        case BookGroup.Id.audio:
            books = try audioBooks()
        case BookGroup.Id.netNoGroup:
            books = try booksWithoutGroup()
        case BookGroup.Id.localNoGroup:
            let mask = try userGroupMask()
            books = try localBooks().filter { ($0.group & mask) == 0 }
        case BookGroup.Id.updateError:
            books = try booksWithUpdateError()
        default:
            books = try tables.rows(in: "books", where: .bitwiseAndNotZero(column: "group", mask: groupId), orderBy: [])
                .map { Book(row: $0) }
        }
        return books.filter { $0.isOnShelf }
    }

    /// The bit mask of the user groups — upstream `BookGroupDao.idsSum`.
    ///
    /// Upstream sums the group ids of every group with a positive id; because
    /// the ids are powers of two the sum is the bit mask of all groups.
    public func userGroupMask() throws -> Int64 {
        try groupRows().compactMap { $0["groupId"]?.intValue }.filter { $0 > 0 }.reduce(0, +)
    }

    /// The books of the discovery page — upstream `BookDao.flowRoot`.
    ///
    /// Only text books that are neither local nor in a user group, and only
    /// when the "网络未分组" group is hidden.
    public func rootBooks() throws -> [Book] {
        let netNoneShown = try groupRows().first { $0["groupId"]?.intValue == BookGroup.Id.netNoGroup }?["show"]?.boolValue ?? false
        let mask = try userGroupMask()
        let books = try tables.rows(in: "books", where: .all, orderBy: [])
        return books.map { Book(row: $0) }.filter {
            BookType.contains($0.type, BookType.text)
                && !BookType.contains($0.type, BookType.local)
                && ($0.group & mask) == 0
                && !netNoneShown
        }
    }

    /// The groups the bookshelf shows — upstream `BookGroupDao.show`.
    ///
    /// Only the groups that have at least one book are listed; the well known
    /// groups are always listed except for the "本地未分组" group, which is
    /// hidden by default.
    public func visibleGroups() throws -> [BookGroup] {
        let mask = try userGroupMask()
        let books = try tables.rows(in: "books", where: .all, orderBy: []).map { Book(row: $0) }
        let shelfBooks = books.filter { $0.isOnShelf }
        let groups = try allGroups()
        return groups.filter { group in
            guard group.show else { return false }
            switch group.groupId {
            case BookGroup.Id.all:
                return true
            case BookGroup.Id.local:
                return shelfBooks.contains { BookType.contains($0.type, BookType.local) }
            case BookGroup.Id.audio:
                return shelfBooks.contains { BookType.contains($0.type, BookType.audio) }
            case BookGroup.Id.updateError:
                return shelfBooks.contains { BookType.contains($0.type, BookType.updateError) }
            case BookGroup.Id.netNoGroup:
                return shelfBooks.contains {
                    !BookType.contains($0.type, BookType.audio)
                        && !BookType.contains($0.type, BookType.local)
                        && ($0.group & mask) == 0
                }
            case BookGroup.Id.localNoGroup:
                return shelfBooks.contains {
                    !BookType.contains($0.type, BookType.audio)
                        && BookType.contains($0.type, BookType.local)
                        && ($0.group & mask) == 0
                }
            default:
                return shelfBooks.contains { ($0.group & group.groupId) > 0 }
            }
        }
    }

    /// The next free group id — upstream `BookGroupDao.getUnusedId`.
    ///
    /// The ids are powers of two so that they can be used as a bit mask in the
    /// `group` column of the books.
    public func unusedGroupId() throws -> Int64 {
        let mask = try userGroupMask()
        var id: Int64 = 1
        while (id & mask) != 0 {
            id <<= 1
        }
        return id
    }

    /// `true` when another group can be added — upstream
    /// `BookGroupDao.canAddGroup` (at most 64 groups).
    public func canAddGroup() throws -> Bool {
        let count = try groupRows().filter { ($0["groupId"]?.intValue ?? 0) >= 0 }.count
        return count < 64
    }

    /// The books that are not in any user group — upstream
    /// `BookDao.flowNetNoGroup` uses the `sum(groupId)` trick.
    ///
    /// Upstream also excludes the audio and the local books.
    public func booksWithoutGroup() throws -> [Book] {
        let sum = try userGroupMask()
        let books = try tables.allRows(in: "books")
        return books
            .map { Book(row: $0) }
            .filter {
                $0.isOnShelf
                    && !BookType.contains($0.type, BookType.audio)
                    && !BookType.contains($0.type, BookType.local)
                    && (($0.group & sum) == 0)
            }
    }

    /// The books whose last update failed — upstream `BookDao.flowUpdateError`.
    public func booksWithUpdateError() throws -> [Book] {
        let books = try tables.rows(in: "books", where: .bitwiseAndNotZero(column: "type", mask: BookType.updateError), orderBy: [])
        return books.map { Book(row: $0) }.filter { $0.isOnShelf }
    }

    /// The local books — upstream `BookDao.flowLocal`.
    public func localBooks() throws -> [Book] {
        let books = try tables.rows(in: "books", where: .bitwiseAndNotZero(column: "type", mask: BookType.local), orderBy: [])
        return books.map { Book(row: $0) }.filter { $0.isOnShelf }
    }

    /// The local book of a file — upstream `BookDao.getBookByFileName`
    /// (`select * from books where originName = :fileName`).
    public func localBook(fileName: String) throws -> Book? {
        let books = try tables.rows(in: "books", where: .all, orderBy: [])
        return books
            .map { Book(row: $0) }
            .first { $0.originName == fileName }
    }

    /// Whether a file is already on the shelf — upstream `BookDao.hasFile`:
    /// the book is a local one and its `originName` is the name of the file
    /// (or its `origin` ends with the name of the file).
    public func hasLocalFile(fileName: String) throws -> Bool {
        let books = try tables.rows(in: "books", where: .bitwiseAndNotZero(column: "type", mask: BookType.local), orderBy: [])
        return books.contains { row in
            let originName = row["originName"]?.stringValue ?? ""
            if originName == fileName { return true }
            let origin = row["origin"]?.stringValue ?? ""
            return origin != BookType.localTag && origin.hasSuffix(fileName)
        }
    }

    /// The audio books — upstream `BookDao.flowAudio`.
    public func audioBooks() throws -> [Book] {
        let books = try tables.rows(in: "books", where: .bitwiseAndNotZero(column: "type", mask: BookType.audio), orderBy: [])
        return books.map { Book(row: $0) }.filter { $0.isOnShelf }
    }

    /// The last read book — upstream `BookDao.lastReadBook`.
    public func lastReadBook() throws -> Book? {
        let books = try allBooks()
        return books.max { $0.durChapterTime < $1.durChapterTime }
    }

    /// Updates the reading progress of a book — upstream `BookDao.update`.
    public func updateProgress(book: Book) throws {
        try update(book)
    }

    // MARK: - Book groups

    /// Every group — upstream `BookGroupDao.all`.
    public func allGroups() throws -> [BookGroup] {
        let rows = try tables.rows(in: "book_groups", where: .all, orderBy: [OrderTerm(column: "order")])
        return rows.map { BookGroup(row: $0) }
    }

    /// Inserts or replaces a group.
    public func insert(_ group: BookGroup) throws {
        try tables.insert(group.row, into: "book_groups")
    }

    /// Deletes a group.
    public func delete(groupId: Int64) throws {
        try tables.delete(from: "book_groups", where: .equals(column: "groupId", value: .integer(groupId)))
    }

    // MARK: - Chapters

    /// The chapters of a book — upstream `BookChapterDao.getChapterList`.
    public func chapters(bookUrl: String) throws -> [BookChapter] {
        let rows = try tables.rows(
            in: "chapters",
            where: .equals(column: "bookUrl", value: .text(bookUrl)),
            orderBy: [OrderTerm(column: "index")]
        )
        return rows.map { BookChapter(row: $0) }
    }

    /// Inserts or replaces chapters.
    public func insert(_ chapters: [BookChapter]) throws {
        try tables.insert(chapters.map { $0.row }, into: "chapters")
    }

    /// Updates a chapter — upstream `BookChapterDao.update` (the content
    /// editor changes the title of a chapter).
    public func update(_ chapter: BookChapter) throws {
        try tables.update(
            "chapters",
            set: ["title": .text(chapter.title)],
            where: .equals(column: "url", value: .text(chapter.url))
        )
    }

    /// Deletes the chapters of a book.
    public func deleteChapters(bookUrl: String) throws {
        try tables.delete(from: "chapters", where: .equals(column: "bookUrl", value: .text(bookUrl)))
    }

    // MARK: - Sources

    /// Every source — upstream `BookSourceDao.all`.
    public func allSources() throws -> [BookSource] {
        try tables.allRows(in: "book_sources").map { BookSource(row: $0) }
    }

    /// The enabled sources — upstream `BookSourceDao.allEnabled`.
    public func enabledSources() throws -> [BookSource] {
        try tables
            .rows(in: "book_sources", where: .equals(column: "enabled", value: .integer(1)), orderBy: [])
            .map { BookSource(row: $0) }
    }

    /// A single source — upstream `BookSourceDao.getBySourceUrl`.
    public func source(url: String) throws -> BookSource? {
        guard let row = try tables.firstRow(in: "book_sources", where: .equals(column: "bookSourceUrl", value: .text(url))) else {
            return nil
        }
        return BookSource(row: row)
    }

    /// Inserts or replaces a source.
    public func insert(_ source: BookSource) throws {
        try tables.insert(source.row, into: "book_sources")
    }

    /// Inserts or replaces many sources.
    public func insert(_ sources: [BookSource]) throws {
        try tables.insert(sources.map { $0.row }, into: "book_sources")
    }

    /// Deletes sources — upstream `BookSourceDao.deleteSources`.
    public func deleteSources(urls: [String]) throws {
        for url in urls {
            try tables.delete(from: "book_sources", where: .equals(column: "bookSourceUrl", value: .text(url)))
        }
    }

    /// Enables or disables sources — upstream `BookSourceDao.enable`.
    public func setSourcesEnabled(_ enabled: Bool, urls: [String]) throws {
        for url in urls {
            try tables.update(
                "book_sources",
                set: ["enabled": .integer(enabled ? 1 : 0)],
                where: .equals(column: "bookSourceUrl", value: .text(url))
            )
        }
    }

    // MARK: - Search results

    /// Inserts or replaces search results.
    public func insert(_ books: [SearchBook]) throws {
        try tables.insert(books.map { $0.row }, into: "searchBooks")
    }

    /// The cached search results of a source — upstream `SearchBookDao.getByOrigin`.
    public func searchBooks(origin: String) throws -> [SearchBook] {
        try tables
            .rows(in: "searchBooks", where: .equals(column: "origin", value: .text(origin)), orderBy: [])
            .map { SearchBook(row: $0) }
    }

    /// Removes the expired search results — upstream `SearchBookDao.clearExpired`
    /// (`delete from searchBooks where time < :time`).
    public func clearExpiredSearchBooks(before: Int64) throws {
        try tables.delete(from: "searchBooks", where: .lessThan(column: "time", value: before))
    }

    /// The search keywords — upstream `SearchKeywordDao.all`.
    public func allSearchKeywords() throws -> [SearchKeyword] {
        try tables
            .rows(in: "search_keywords", where: .all, orderBy: [OrderTerm(column: "lastUseTime", descending: true)])
            .map { SearchKeyword(row: $0) }
    }

    /// Inserts or replaces a search keyword.
    public func insert(_ keyword: SearchKeyword) throws {
        try tables.insert(keyword.row, into: "search_keywords")
    }

    // MARK: - Caches

    /// A cached value — upstream `CacheDao.get`.
    public func cache(_ key: String, now: Int64) throws -> String? {
        guard let row = try tables.firstRow(in: "caches", where: .equals(column: "key", value: .text(key))) else { return nil }
        let deadline = row["deadline"]?.intValue ?? 0
        guard deadline == 0 || deadline > now else { return nil }
        return row["value"]?.stringValue
    }

    /// Stores a cached value — upstream `CacheDao.insert`.
    public func putCache(_ key: String, value: String?, deadline: Int64) throws {
        try tables.insert(CacheEntry(key: key, value: value, deadline: deadline).row, into: "caches")
    }

    /// Removes a cached value — upstream `CacheDao.delete`.
    public func deleteCache(_ key: String) throws {
        try tables.delete(from: "caches", where: .equals(column: "key", value: .text(key)))
    }

    /// Removes the expired cache entries — upstream `CacheDao.clearDeadline`.
    public func clearExpiredCaches(now: Int64) throws {
        let rows = try tables.allRows(in: "caches")
        for row in rows {
            let deadline = row["deadline"]?.intValue ?? 0
            guard deadline != 0, deadline <= now else { continue }
            try tables.delete(from: "caches", where: .equals(column: "key", value: row["key"] ?? .null))
        }
    }

    /// Removes the variables of a source — upstream `CacheDao.deleteSourceVariables`.
    public func deleteSourceVariables(key: String) throws {
        let prefixes = ["v_\(key)_", "userInfo_\(key)", "loginHeader_\(key)", "sourceVariable_\(key)"]
        let rows = try tables.allRows(in: "caches")
        for row in rows {
            guard let cacheKey = row["key"]?.stringValue else { continue }
            guard prefixes.contains(where: { cacheKey.hasPrefix($0) }) else { continue }
            try tables.delete(from: "caches", where: .equals(column: "key", value: .text(cacheKey)))
        }
    }

    // MARK: - Cookies

    /// The stored cookie of a domain — upstream `CookieDao.getByUrl`.
    public func cookie(url: String) throws -> String? {
        try tables.firstRow(in: "cookies", where: .equals(column: "url", value: .text(url)))?["cookie"]?.stringValue
    }

    /// Stores a cookie.
    public func insert(_ cookie: Cookie) throws {
        try tables.insert(cookie.row, into: "cookies")
    }

    // MARK: - Replace rules

    /// The enabled replace rules — upstream `ReplaceRuleDao.all`.
    public func allReplaceRules() throws -> [ReplaceRule] {
        try tables
            .rows(in: "replace_rules", where: .all, orderBy: [OrderTerm(column: "sortOrder")])
            .map { ReplaceRule(row: $0) }
    }

    /// Inserts or replaces a replace rule.
    ///
    /// Upstream `ReplaceRule.id` is an auto-generated primary key, so a rule
    /// without an id gets a fresh one here. The generator never returns the
    /// same value twice, even inside one millisecond.
    public func insert(_ rule: ReplaceRule) throws {
        var rule = rule
        if rule.id == 0 {
            rule.id = nextGeneratedId()
        }
        try tables.insert(rule.row, into: "replace_rules")
    }

    private var lastGeneratedId: Int64 = 0

    private func nextGeneratedId() -> Int64 {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        lastGeneratedId = max(now, lastGeneratedId + 1)
        return lastGeneratedId
    }

    /// The highest order of the replace rules — upstream
    /// `ReplaceRuleDao.maxOrder`.
    ///
    /// The upstream API appends a new rule with `maxOrder + 1`, so it lands
    /// at the end of the list.
    public func maxReplaceRuleOrder() throws -> Int64 {
        try tables
            .rows(in: "replace_rules", where: .all, orderBy: [])
            .compactMap { $0["sortOrder"]?.intValue }
            .max() ?? 0
    }

    /// Deletes a replace rule.
    public func deleteReplaceRule(id: Int64) throws {
        try tables.delete(from: "replace_rules", where: .equals(column: "id", value: .integer(id)))
    }

    /// The enabled replace rules that apply to the CONTENT of a book.
    ///
    /// Upstream `ReplaceRuleDao.findEnabledByContentScope`:
    /// ```sql
    /// SELECT * FROM replace_rules WHERE isEnabled = 1 and scopeContent = 1
    ///   AND (scope LIKE '%' || :name || '%' or scope LIKE '%' || :origin || '%'
    ///        or scope is null or scope = '')
    ///   AND (excludeScope is null or (excludeScope not LIKE '%' || :name || '%'
    ///        and excludeScope not LIKE '%' || :origin || '%'))
    ///   order by sortOrder
    /// ```
    public func replaceRulesForContent(name: String, origin: String) throws -> [ReplaceRule] {
        try replaceRules(scopeColumn: "scopeContent", name: name, origin: origin)
    }

    /// The enabled replace rules that apply to the TITLE of a book.
    ///
    /// Upstream `ReplaceRuleDao.findEnabledByTitleScope` — the same query with
    /// `scopeTitle = 1` instead of `scopeContent = 1`.
    public func replaceRulesForTitle(name: String, origin: String) throws -> [ReplaceRule] {
        try replaceRules(scopeColumn: "scopeTitle", name: name, origin: origin)
    }

    private func replaceRules(scopeColumn: String, name: String, origin: String) throws -> [ReplaceRule] {
        let scopeMatches: RowPredicate = .anyOf([
            .contains(column: "scope", value: name),
            .contains(column: "scope", value: origin),
            .isNull(column: "scope"),
            .equals(column: "scope", value: .text("")),
        ])
        let notExcluded: RowPredicate = .anyOf([
            .isNull(column: "excludeScope"),
            .allOf([
                .notContains(column: "excludeScope", value: name),
                .notContains(column: "excludeScope", value: origin),
            ]),
        ])
        return try tables
            .rows(
                in: "replace_rules",
                where: .allOf([
                    .equals(column: "isEnabled", value: .integer(1)),
                    .equals(column: scopeColumn, value: .integer(1)),
                    scopeMatches,
                    notExcluded,
                ]),
                orderBy: [OrderTerm(column: "sortOrder")]
            )
            .map { ReplaceRule(row: $0) }
    }

    // MARK: - Bookmarks

    /// The bookmarks of a book — upstream `BookmarkDao.getByBookName`.
    public func bookmarks(bookName: String, bookAuthor: String) throws -> [Bookmark] {
        try tables
            .rows(
                in: "bookmarks",
                where: .allOf([
                    .equals(column: "bookName", value: .text(bookName)),
                    .equals(column: "bookAuthor", value: .text(bookAuthor))
                ]),
                orderBy: []
            )
            .map { Bookmark(row: $0) }
    }

    /// Inserts or replaces a bookmark.
    public func insert(_ bookmark: Bookmark) throws {
        try tables.insert(bookmark.row, into: "bookmarks")
    }

    /// Every bookmark — upstream `BookmarkDao.all`.
    public func allBookmarks() throws -> [Bookmark] {
        try tables
            .rows(in: "bookmarks", where: .all, orderBy: [OrderTerm(column: "time")])
            .map { Bookmark(row: $0) }
    }

    /// Deletes a bookmark — upstream `BookmarkDao.delete`.
    ///
    /// The upstream deletes by the book name and the author, because the
    /// table has no id.
    public func deleteBookmark(_ bookmark: Bookmark) throws {
        try tables.delete(
            from: "bookmarks",
            where: .allOf([
                .equals(column: "bookName", value: .text(bookmark.bookName)),
                .equals(column: "bookAuthor", value: .text(bookmark.bookAuthor))
            ])
        )
    }

    // MARK: - Read history

    /// The read record of a book — upstream `ReadRecordDao.getByDeviceId`.
    public func readRecord(deviceId: String, bookName: String) throws -> ReadRecord? {
        guard let row = try tables.firstRow(
            in: "readRecord",
            where: .allOf([
                .equals(column: "deviceId", value: .text(deviceId)),
                .equals(column: "bookName", value: .text(bookName))
            ])
        ) else { return nil }
        return ReadRecord(row: row)
    }

    /// Inserts or replaces a read record.
    public func insert(_ record: ReadRecord) throws {
        try tables.insert(record.row, into: "readRecord")
    }

    // MARK: - RSS

    /// Every RSS source — upstream `RssSourceDao.all`.
    public func allRssSources() throws -> [RssSource] {
        try tables.allRows(in: "rssSources").map { RssSource(row: $0) }
    }

    /// Inserts or replaces an RSS source.
    public func insert(_ source: RssSource) throws {
        try tables.insert(source.row, into: "rssSources")
    }

    /// Deletes RSS sources.
    public func deleteRssSources(urls: [String]) throws {
        for url in urls {
            try tables.delete(from: "rssSources", where: .equals(column: "sourceUrl", value: .text(url)))
        }
    }

    /// The articles of an RSS source — upstream `RssArticleDao.getByOrigin`.
    public func rssArticles(origin: String) throws -> [RssArticle] {
        try tables
            .rows(in: "rssArticles", where: .equals(column: "origin", value: .text(origin)), orderBy: [])
            .map { RssArticle(row: $0) }
    }

    /// Inserts or replaces RSS articles.
    public func insert(_ articles: [RssArticle]) throws {
        try tables.insert(articles.map { $0.row }, into: "rssArticles")
    }

    /// Deletes the articles of an RSS source — upstream `RssArticleDao.delete`.
    public func deleteRssArticles(origin: String) throws {
        try tables.delete(from: "rssArticles", where: .equals(column: "origin", value: .text(origin)))
    }

    /// Inserts or replaces a starred article.
    public func insert(_ star: RssStar) throws {
        try tables.insert(star.row, into: "rssStars")
    }

    /// The starred articles.
    public func allRssStars() throws -> [RssStar] {
        try tables.allRows(in: "rssStars").map { RssStar(row: $0) }
    }

    /// The starred articles of a group — upstream `RssStarDao.flowByGroup`.
    public func rssStars(group: String) throws -> [RssStar] {
        try tables
            .rows(in: "rssStars", where: .equals(column: "group", value: .text(group)), orderBy: [])
            .map { RssStar(row: $0) }
    }

    /// Deletes the starred articles of a group — upstream
    /// `RssStarDao.deleteByGroup`.
    public func deleteRssStars(group: String) throws {
        try tables.delete(from: "rssStars", where: .equals(column: "group", value: .text(group)))
    }

    /// Deletes the favourite of an article — the link is the key.
    public func deleteRssStar(link: String) throws {
        try tables.delete(from: "rssStars", where: .equals(column: "link", value: .text(link)))
    }

    /// Inserts or replaces an RSS read record.
    public func insert(_ record: RssReadRecord) throws {
        try tables.insert(record.row, into: "rssReadRecords")
    }

    /// The RSS read records.
    public func allRssReadRecords() throws -> [RssReadRecord] {
        try tables.allRows(in: "rssReadRecords").map { RssReadRecord(row: $0) }
    }

    /// The read record of an article — the record key is the article link.
    public func rssReadRecord(record: String) throws -> RssReadRecord? {
        try tables
            .rows(in: "rssReadRecords", where: .equals(column: "record", value: .text(record)), orderBy: [])
            .first
            .map { RssReadRecord(row: $0) }
    }

    /// Deletes every RSS read record — upstream `RssReadRecordDao.deleteAllRecord`.
    public func deleteAllRssReadRecords() throws {
        try tables.deleteAll(from: "rssReadRecords")
    }

    // MARK: - Misc

    /// The enabled TXT table of contents rules — upstream `TxtTocRuleDao.getAllEnable`.
    ///
    /// Upstream orders them by `serialNumber`; the detection of the table of
    /// contents walks the rules in the reverse order.
    public func enabledTxtTocRules() throws -> [TxtTocRule] {
        try tables
            .rows(
                in: "txtTocRules",
                where: .equals(column: "enable", value: .integer(1)),
                orderBy: [OrderTerm(column: "serialNumber")]
            )
            .map { TxtTocRule(row: $0) }
    }

    /// Every TXT table of contents rule — upstream `TxtTocRuleDao.all`.
    public func allTxtTocRules() throws -> [TxtTocRule] {
        try tables.allRows(in: "txtTocRules").map { TxtTocRule(row: $0) }
    }

    /// Every reading record — upstream `ReadRecordDao.all`.
    public func allReadRecords() throws -> [ReadRecord] {
        try tables.allRows(in: "readRecord").map { ReadRecord(row: $0) }
    }

    /// The reading records whose name contains `key` — upstream
    /// `ReadRecordDao.search` (`bookName like '%' || :searchKey || '%'`).
    public func readRecords(matching key: String) throws -> [ReadRecord] {
        try tables.rows(
            in: "readRecord",
            where: .contains(column: "bookName", value: key),
            orderBy: []
        ).map { ReadRecord(row: $0) }
    }

    /// Deletes the reading records of a book — upstream
    /// `ReadRecordDao.deleteByName`.
    public func deleteReadRecords(bookName: String) throws {
        try tables.delete(
            from: "readRecord",
            where: .equals(column: "bookName", value: .text(bookName))
        )
    }

    /// Deletes every reading record — upstream `ReadRecordDao.clear`.
    public func clearReadRecords() throws {
        try tables.deleteAll(from: "readRecord")
    }

    /// Compacts the database file — upstream
    /// `ConfigViewModel.shrinkDatabase()` → `execSQL("VACUUM")`.
    public func shrinkDatabase() throws {
        try tables.vacuum()
    }

    /// Inserts or replaces a TXT table of contents rule.
    ///
    /// Upstream `TxtTocRule` has an auto-generated primary key, so a rule
    /// without an id gets a fresh one here. The negative ids of the upstream
    /// defaults are kept as they are.
    public func insert(_ rule: TxtTocRule) throws {
        var rule = rule
        if rule.id == 0 {
            rule.id = nextGeneratedId()
        }
        try tables.insert(rule.row, into: "txtTocRules")
    }

    /// Deletes the default TXT table of contents rules — upstream
    /// `TxtTocRuleDao.deleteDefault` (`delete from txtTocRules where id < 0`).
    public func deleteDefaultTxtTocRules() throws {
        try tables.delete(from: "txtTocRules", where: .lessThan(column: "id", value: 0))
    }

    /// Deletes a TXT table of contents rule — upstream `TxtTocRuleDao.delete`.
    public func deleteTxtTocRule(_ rule: TxtTocRule) throws {
        try tables.delete(from: "txtTocRules", where: .equals(column: "id", value: .integer(rule.id)))
    }

    /// Imports the TXT table of contents rules of a JSON document — upstream
    /// `TxtTocRuleActivity.importTxtTocRule` (the online / local / QR import).
    ///
    /// The document is either an array of rules or a single rule.
    @discardableResult
    public func importTxtTocRules(json: String) throws -> Int {
        let value: JSONValue
        do {
            value = try JSONValue.parse(json)
        } catch {
            throw DeepLinkError.invalidData(.txtRule)
        }
        var rules: [TxtTocRule] = []
        switch value {
        case .array(let items):
            rules = items.compactMap { TxtTocRuleJSONBridge.decode($0) }
        case .object:
            if let rule = TxtTocRuleJSONBridge.decode(value) {
                rules = [rule]
            }
        default:
            break
        }
        guard !rules.isEmpty else { throw DeepLinkError.invalidData(.txtRule) }
        for rule in rules {
            try insert(rule)
        }
        return rules.count
    }

    /// Moves the rules to the top or to the bottom — upstream
    /// `TxtTocRuleViewModel.toTop` / `toBottom`.
    public func moveTxtTocRules(_ rules: [TxtTocRule], toTop: Bool) throws {
        guard !rules.isEmpty else { return }
        let all = try allTxtTocRules()
        let orders = all.map { $0.serialNumber }
        let minOrder = (orders.min() ?? 0) - 1
        let maxOrder = (orders.max() ?? 0) + 1
        for (index, rule) in rules.enumerated() {
            var changed = rule
            changed.serialNumber = toTop ? minOrder - Int64(index) : maxOrder + Int64(index)
            try tables.insert(changed.row, into: "txtTocRules")
        }
    }

    /// Renumbers the rules after a drag — upstream `TxtTocRuleViewModel.upOrder`.
    public func updateTxtTocRuleOrder() throws {
        let all = try allTxtTocRules()
        for (index, rule) in all.enumerated() {
            var changed = rule
            changed.serialNumber = Int64(index + 1)
            try tables.insert(changed.row, into: "txtTocRules")
        }
    }

    /// Every HTTP TTS engine — upstream `HttpTTSDao.all`.
    public func allHttpTTS() throws -> [HttpTTS] {
        try tables.allRows(in: "httpTTS").map { HttpTTS(row: $0) }
    }

    /// One HTTP TTS engine — upstream `HttpTTSDao.get(id)`.
    public func httpTTS(id: Int64) throws -> HttpTTS? {
        try tables.firstRow(in: "httpTTS", where: .equals(column: "id", value: .integer(id)))
            .map { HttpTTS(row: $0) }
    }

    /// Inserts or replaces an HTTP TTS engine.
    ///
    /// Upstream `HttpTTS` has an auto-generated primary key, so an engine
    /// without an id gets a fresh one here.
    public func insert(_ engine: HttpTTS) throws {
        var engine = engine
        if engine.id == 0 {
            engine.id = nextGeneratedId()
        }
        try tables.insert(engine.row, into: "httpTTS")
    }

    /// Deletes the default HTTP TTS engines — upstream
    /// `HttpTTSDao.deleteDefault` (`delete from httpTTS where id < 0`).
    public func deleteDefaultHttpTTS() throws {
        try tables.delete(from: "httpTTS", where: .lessThan(column: "id", value: 0))
    }

    /// Deletes an HTTP TTS engine — upstream `HttpTTSDao.delete`.
    @discardableResult
    public func deleteHttpTTS(_ engine: HttpTTS) throws -> Int {
        try tables.delete(from: "httpTTS", where: .equals(column: "id", value: .integer(engine.id)))
    }

    /// Deletes the default RSS sources — upstream `RssSourceDao.deleteDefault`
    /// (`delete from rssSources where sourceGroup like 'legado'`).
    public func deleteDefaultRssSources() throws {
        try tables.delete(from: "rssSources", where: .contains(column: "sourceGroup", value: "legado"))
    }

    /// Every dictionary rule.
    public func allDictRules() throws -> [DictRule] {
        try tables.allRows(in: "dictRules").map { DictRule(row: $0) }
    }

    /// Inserts or replaces a dictionary rule.
    public func insert(_ rule: DictRule) throws {
        try tables.insert(rule.row, into: "dictRules")
    }

    /// Deletes a dictionary rule — upstream `DictRuleDao.delete`.
    @discardableResult
    public func deleteDictRule(_ rule: DictRule) throws -> Int {
        try tables.delete(from: "dictRules", where: .equals(column: "name", value: .text(rule.name)))
    }

    /// Deletes several dictionary rules — upstream
    /// `DictRuleViewModel.delete(vararg dictRule)`.
    @discardableResult
    public func deleteDictRules(_ rules: [DictRule]) throws -> Int {
        var count = 0
        for rule in rules { count += try deleteDictRule(rule) }
        return count
    }

    /// Writes several dictionary rules — upstream
    /// `DictRuleDao.insert(*array)` (used by the enable / disable selection
    /// and by the renumbering).
    public func updateDictRules(_ rules: [DictRule]) throws {
        for rule in rules { try insert(rule) }
    }

    /// Every keyboard assist.
    public func allKeyboardAssists() throws -> [KeyboardAssist] {
        try tables.allRows(in: "keyboardAssists").map { KeyboardAssist(row: $0) }
    }

    /// Inserts or replaces a keyboard assist.
    public func insert(_ assist: KeyboardAssist) throws {
        try tables.insert(assist.row, into: "keyboardAssists")
    }

    /// Every synchronisation server.
    public func allServers() throws -> [Server] {
        try tables.allRows(in: "servers").map { Server(row: $0) }
    }

    /// Inserts or replaces a synchronisation server.
    public func insert(_ server: Server) throws {
        try tables.insert(server.row, into: "servers")
    }

    /// The WebDAV server of the app — upstream `AppWebDav`'s default server.
    ///
    /// The first row of the kind `webDav` is the one the upstream uses.
    public func webDavServer() throws -> Server? {
        try allServers().first { $0.type == Server.Kind.webDav }
    }

    /// The credentials of the WebDAV server — upstream
    /// `Server.getWebDavConfig`.
    public func webDavCredentials() throws -> WebDavCredentials? {
        guard let server = try webDavServer() else { return nil }
        return WebDavCredentials.parse(server.config)
    }

    /// Stores the credentials of the WebDAV server — upstream
    /// `AppWebDav.putConfig` / the server manager.
    public func saveWebDavCredentials(_ credentials: WebDavCredentials) throws {
        if var server = try webDavServer() {
            server.config = credentials.json
            try insert(server)
        } else {
            try insert(
                Server(
                    id: 0,
                    name: "WebDAV",
                    type: Server.Kind.webDav,
                    config: credentials.json
                )
            )
        }
    }

    /// A synchronisation server by its id — upstream `serverDao.get(id)`.
    public func server(id: Int64) throws -> Server? {
        try allServers().first { $0.id == id }
    }

    /// Deletes a synchronisation server — upstream `ServersViewModel.delete`.
    @discardableResult
    public func deleteServer(_ server: Server) throws -> Int {
        try tables.delete(from: "servers", where: .equals(column: "id", value: .integer(server.id)))
    }

    /// Every rule subscription.
    public func allRuleSubs() throws -> [RuleSub] {
        try tables.allRows(in: "ruleSubs").map { RuleSub(row: $0) }
    }

    /// Inserts or replaces a rule subscription.
    public func insert(_ sub: RuleSub) throws {
        try tables.insert(sub.row, into: "ruleSubs")
    }

    /// Deletes a rule subscription — upstream `RuleSubDao.delete`.
    public func deleteRuleSub(id: Int64) throws {
        try tables.delete(from: "ruleSubs", where: .equals(column: "id", value: .integer(id)))
    }
}
