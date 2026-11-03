//
//  AppShellTests.swift
//  LegadoCoreTests
//
//  Tests for the app-shell logic: the preference layer (`AppSettings`, the
//  counterpart of upstream `AppConfig`) and the bookshelf (the upstream
//  `BookDao.flowByGroup`, `BookGroupDao.show` and the sort of
//  `BooksFragment.upRecyclerData`).
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/constant/PreferKey.kt
//  app/src/main/java/io/legado/app/help/config/AppConfig.kt
//  app/src/main/java/io/legado/app/data/dao/BookDao.kt
//  app/src/main/java/io/legado/app/data/dao/BookGroupDao.kt
//  app/src/main/java/io/legado/app/ui/main/bookshelf/style1/books/BooksFragment.kt
//

import XCTest
@testable import LegadoCore

// MARK: - Groups

final class BookGroupTests: XCTestCase {

    func testWellKnownIdsMatchTheUpstreamCompanionObject() {
        // Upstream `BookGroup.Companion`.
        XCTAssertEqual(BookGroup.Id.root, -100)
        XCTAssertEqual(BookGroup.Id.all, -1)
        XCTAssertEqual(BookGroup.Id.local, -2)
        XCTAssertEqual(BookGroup.Id.audio, -3)
        XCTAssertEqual(BookGroup.Id.netNoGroup, -4)
        XCTAssertEqual(BookGroup.Id.localNoGroup, -5)
        XCTAssertEqual(BookGroup.Id.updateError, -11)
    }

    func testDefaultsMatchTheUpstreamEntity() {
        let group = BookGroup(groupId: 1, groupName: "Mine")
        XCTAssertTrue(group.enableRefresh)
        XCTAssertTrue(group.show)
        XCTAssertEqual(group.bookSort, -1)
        XCTAssertEqual(group.order, 0)
    }

    func testRealBookSortUsesTheFallbackWhenNegative() {
        // Upstream `BookGroup.getRealBookSort()`.
        let group = BookGroup(groupId: 1, groupName: "Mine", bookSort: -1)
        XCTAssertEqual(group.realBookSort(fallback: 3), 3)
        var fixed = group
        fixed.bookSort = 2
        XCTAssertEqual(fixed.realBookSort(fallback: 3), 2)
    }

    func testManageNameAppendsTheKind() {
        // Upstream `BookGroup.getManageName(context)` — the well known groups
        // show their kind in brackets, which is why upstream shows "全部(全部)".
        let group = BookGroup(groupId: BookGroup.Id.all, groupName: "全部")
        XCTAssertEqual(group.manageName(), "全部(全部)")
        let user = BookGroup(groupId: 1, groupName: "Mine")
        XCTAssertEqual(user.manageName(), "Mine")
    }

    func testWellKnownFlag() {
        XCTAssertTrue(BookGroup(groupId: BookGroup.Id.audio, groupName: "音频").isWellKnown)
        XCTAssertFalse(BookGroup(groupId: 4, groupName: "Mine").isWellKnown)
    }
}

// MARK: - The bookshelf queries

final class BookshelfQueryTests: XCTestCase {

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        try store.seedDefaultGroups()
        return store
    }

    func testAllGroupReturnsEveryShelfBook() throws {
        let store = try makeStore()
        try store.insert(Book(bookUrl: "u1", name: "A"))
        try store.insert(Book(bookUrl: "u2", name: "B"))
        let books = try store.books(inGroup: BookGroup.Id.all)
        XCTAssertEqual(Set(books.map(\.bookUrl)), ["u1", "u2"])
    }

    func testBooksThatAreNotOnTheShelfAreFilteredOut() throws {
        let store = try makeStore()
        try store.insert(Book(bookUrl: "u1"))
        try store.insert(Book(bookUrl: "u2", type: BookType.text | BookType.notShelf))
        let books = try store.books(inGroup: BookGroup.Id.all)
        XCTAssertEqual(books.map(\.bookUrl), ["u1"])
    }

    func testLocalAndAudioGroups() throws {
        let store = try makeStore()
        try store.insert(Book(bookUrl: "text", type: BookType.text))
        try store.insert(Book(bookUrl: "local", type: BookType.text | BookType.local))
        try store.insert(Book(bookUrl: "audio", type: BookType.audio))
        XCTAssertEqual(try store.books(inGroup: BookGroup.Id.local).map(\.bookUrl), ["local"])
        XCTAssertEqual(try store.books(inGroup: BookGroup.Id.audio).map(\.bookUrl), ["audio"])
    }

    func testUpdateErrorGroup() throws {
        let store = try makeStore()
        try store.insert(Book(bookUrl: "ok"))
        try store.insert(Book(bookUrl: "broken", type: BookType.text | BookType.updateError))
        XCTAssertEqual(try store.books(inGroup: BookGroup.Id.updateError).map(\.bookUrl), ["broken"])
    }

    func testNetNoGroupExcludesTheLocalAndAudioBooks() throws {
        // Upstream `BookDao.flowNetNoGroup`.
        let store = try makeStore()
        try store.insert(Book(bookUrl: "net"))
        try store.insert(Book(bookUrl: "local", type: BookType.text | BookType.local))
        try store.insert(Book(bookUrl: "audio", type: BookType.audio))
        XCTAssertEqual(try store.books(inGroup: BookGroup.Id.netNoGroup).map(\.bookUrl), ["net"])
    }

    func testLocalNoGroupExcludesTheGroupedBooks() throws {
        // Upstream `BookDao.flowLocalNoGroup`.
        let store = try makeStore()
        try store.insert(BookGroup(groupId: 2, groupName: "Mine"))
        try store.insert(Book(bookUrl: "free", type: BookType.text | BookType.local))
        try store.insert(Book(bookUrl: "grouped", type: BookType.text | BookType.local, group: 0b10))
        XCTAssertEqual(try store.books(inGroup: BookGroup.Id.localNoGroup).map(\.bookUrl), ["free"])
    }

    func testUserGroupUsesTheBitmask() throws {
        let store = try makeStore()
        try store.insert(BookGroup(groupId: 2, groupName: "Mine"))
        try store.insert(Book(bookUrl: "in", group: 0b10))
        try store.insert(Book(bookUrl: "out", group: 0b01))
        XCTAssertEqual(try store.books(inGroup: 2).map(\.bookUrl), ["in"])
    }

    func testRootGroupOnlyHoldsTheUngroupedTextBooks() throws {
        // Upstream `BookDao.flowRoot`.
        let store = try makeStore()
        try store.insert(Book(bookUrl: "text"))
        try store.insert(Book(bookUrl: "local", type: BookType.text | BookType.local))
        try store.insert(Book(bookUrl: "audio", type: BookType.audio))
        try store.insert(BookGroup(groupId: 2, groupName: "Mine"))
        try store.insert(Book(bookUrl: "grouped", group: 0b10))
        // The "网络未分组" group is visible by default, which hides the root
        // list — upstream `flowRoot` requires its `show` flag to be 0.
        try store.insert(BookGroup(groupId: BookGroup.Id.netNoGroup, groupName: "网络未分组", show: false))
        XCTAssertEqual(try store.books(inGroup: BookGroup.Id.root).map(\.bookUrl), ["text"])
    }

    func testRootGroupIsEmptyWhenTheNetNoGroupGroupIsShown() throws {
        // Upstream `flowRoot` requires the "网络未分组" group to be hidden.
        let store = try makeStore()
        try store.insert(Book(bookUrl: "text"))
        // The "网络未分组" group is shown by default.
        XCTAssertTrue(try store.books(inGroup: BookGroup.Id.root).isEmpty)
        try store.insert(BookGroup(groupId: BookGroup.Id.netNoGroup, groupName: "网络未分组", show: false))
        XCTAssertEqual(try store.books(inGroup: BookGroup.Id.root).map(\.bookUrl), ["text"])
    }

    func testVisibleGroupsOnlyListsTheGroupsWithBooks() throws {
        // Upstream `BookGroupDao.show`.
        let store = try makeStore()
        try store.insert(Book(bookUrl: "text"))
        let groups = try store.visibleGroups()
        XCTAssertTrue(groups.contains { $0.groupId == BookGroup.Id.all })
        XCTAssertFalse(groups.contains { $0.groupId == BookGroup.Id.audio })
        XCTAssertFalse(groups.contains { $0.groupId == BookGroup.Id.local })
    }

    func testVisibleGroupsHidesTheLocalNoGroupGroupByDefault() throws {
        let store = try makeStore()
        try store.insert(Book(bookUrl: "local", type: BookType.text | BookType.local))
        let groups = try store.visibleGroups()
        XCTAssertFalse(groups.contains { $0.groupId == BookGroup.Id.localNoGroup })
    }

    func testUnusedGroupIdIsAPowerOfTwo() throws {
        // Upstream `BookGroupDao.getUnusedId`.
        let store = try makeStore()
        XCTAssertEqual(try store.unusedGroupId(), 1)
        try store.insert(BookGroup(groupId: 1, groupName: "First"))
        XCTAssertEqual(try store.unusedGroupId(), 2)
        try store.insert(BookGroup(groupId: 2, groupName: "Second"))
        XCTAssertEqual(try store.unusedGroupId(), 4)
    }

    func testCanAddGroup() throws {
        let store = try makeStore()
        XCTAssertTrue(try store.canAddGroup())
    }
}

// MARK: - The sort of the bookshelf

final class BookshelfSortTests: XCTestCase {

    private func makeBooks() -> [Book] {
        [
            Book(bookUrl: "a", name: "Beta", author: "Zoe", latestChapterTime: 5, durChapterTime: 10, order: 3),
            Book(bookUrl: "b", name: "Alpha", author: "Adam", latestChapterTime: 1, durChapterTime: 30, order: 1),
            Book(bookUrl: "c", name: "Gamma", author: "Mia", latestChapterTime: 9, durChapterTime: 20, order: 2)
        ]
    }

    func testByDurationSortsByTheLastReadTime() {
        let books = BookshelfSort.byDuration.sort(makeBooks())
        XCTAssertEqual(books.map(\.bookUrl), ["b", "c", "a"])
    }

    func testByLatestSortsByTheNewestChapter() {
        let books = BookshelfSort.byLatest.sort(makeBooks())
        XCTAssertEqual(books.map(\.bookUrl), ["c", "a", "b"])
    }

    func testByNameSortsByName() {
        let books = BookshelfSort.byName.sort(makeBooks())
        XCTAssertEqual(books.map(\.bookUrl), ["b", "a", "c"])
    }

    func testByOrderSortsByTheManualOrder() {
        let books = BookshelfSort.byOrder.sort(makeBooks())
        XCTAssertEqual(books.map(\.bookUrl), ["b", "c", "a"])
    }

    func testByMixedUsesTheNewestOfBothTimes() {
        // Upstream issue #3192 — `max(latestChapterTime, durChapterTime)`.
        let books = BookshelfSort.byMixed.sort(makeBooks())
        XCTAssertEqual(books.map(\.bookUrl), ["b", "c", "a"])
    }

    func testByAuthorSortsByAuthor() {
        let books = BookshelfSort.byAuthor.sort(makeBooks())
        XCTAssertEqual(books.map(\.bookUrl), ["b", "c", "a"])
    }

    func testTheRawValuesMatchTheUpstreamBookSort() {
        XCTAssertEqual(BookshelfSort.byDuration.rawValue, 0)
        XCTAssertEqual(BookshelfSort.byLatest.rawValue, 1)
        XCTAssertEqual(BookshelfSort.byName.rawValue, 2)
        XCTAssertEqual(BookshelfSort.byOrder.rawValue, 3)
        XCTAssertEqual(BookshelfSort.byMixed.rawValue, 4)
        XCTAssertEqual(BookshelfSort.byAuthor.rawValue, 5)
    }
}

// MARK: - The bookshelf model

final class BookshelfModelTests: XCTestCase {

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        try store.seedDefaultGroups()
        return store
    }

    func testTheGroupSortOverridesTheGlobalSort() throws {
        let store = try makeStore()
        let settings = AppSettings(store: InMemorySettingsStore())
        settings.bookshelfSort = 2
        try store.insert(BookGroup(groupId: 4, groupName: "Mine", bookSort: 5))
        let model = BookshelfModel(store: store)
        XCTAssertEqual(try model.groupSort(for: 4, settings: settings), 5)
        XCTAssertEqual(try model.groupSort(for: 8, settings: settings), 2)
    }

    func testTheBooksOfAGroupAreSorted() throws {
        let store = try makeStore()
        try store.insert(Book(bookUrl: "a", name: "Beta", durChapterTime: 10))
        try store.insert(Book(bookUrl: "b", name: "Alpha", durChapterTime: 30))
        let model = BookshelfModel(store: store)
        let books = try model.books(inGroup: BookGroup.Id.all, sort: .byDuration)
        XCTAssertEqual(books.map(\.bookUrl), ["b", "a"])
    }

    func testSearchMatchesTheNameAndTheAuthor() throws {
        let store = try makeStore()
        try store.insert(Book(bookUrl: "a", name: "Legend", author: "Someone"))
        try store.insert(Book(bookUrl: "b", name: "Other", author: "Legend"))
        try store.insert(Book(bookUrl: "c", name: "Third", author: "Else"))
        let model = BookshelfModel(store: store)
        let books = try model.search("legend")
        XCTAssertEqual(Set(books.map(\.bookUrl)), ["a", "b"])
        XCTAssertTrue(try model.search("").isEmpty)
    }
}

// MARK: - The settings

final class AppSettingsTests: XCTestCase {

    private func makeSettings() -> (AppSettings, InMemorySettingsStore) {
        let store = InMemorySettingsStore()
        return (AppSettings(store: store), store)
    }

    func testTheDefaultsMatchTheUpstreamAppConfig() {
        let (settings, _) = makeSettings()
        XCTAssertEqual(settings.themeMode, "0")
        XCTAssertFalse(settings.isEInkMode)
        XCTAssertFalse(settings.isDarkTheme)
        XCTAssertEqual(settings.threadCount, 16)
        XCTAssertEqual(settings.bookshelfSort, 0)
        XCTAssertEqual(settings.bookshelfLayout, 0)
        XCTAssertEqual(settings.webPort, 1122)
        XCTAssertEqual(settings.exportCharset, "UTF-8")
        XCTAssertEqual(settings.exportType, 0)
        XCTAssertTrue(settings.exportUseReplace)
        XCTAssertFalse(settings.exportNoChapterName)
        XCTAssertFalse(settings.exportPictureFile)
        XCTAssertTrue(settings.onlyLatestBackup)
        XCTAssertTrue(settings.syncBookProgress)
        XCTAssertFalse(settings.syncBookProgressPlus)
        XCTAssertTrue(settings.showUnread)
        XCTAssertTrue(settings.showDiscovery)
        XCTAssertTrue(settings.showRSS)
        XCTAssertFalse(settings.enableReview)
        XCTAssertFalse(settings.useDefaultCover)
        XCTAssertFalse(settings.loadCoverOnlyWifi)
        XCTAssertFalse(settings.autoRefreshBook)
        XCTAssertFalse(settings.recordLog)
        XCTAssertTrue(settings.enableReadRecord)
        XCTAssertEqual(settings.preDownloadNumber, 10)
        XCTAssertEqual(settings.chineseConverterType, 0)
        XCTAssertTrue(settings.ttsFollowSys)
        XCTAssertEqual(settings.ttsSpeechRate, 5)
        XCTAssertFalse(settings.readAloudByPage)
        XCTAssertFalse(settings.webServiceEnabled)
        XCTAssertEqual(settings.brightness, 100)
        XCTAssertEqual(settings.nightBrightness, 100)
    }

    func testTheUserAgentFallsBackToTheDefault() {
        let (settings, _) = makeSettings()
        XCTAssertTrue(settings.userAgent.contains("Mozilla/5.0"))
        settings.userAgent = ""
        XCTAssertTrue(settings.userAgent.contains("Mozilla/5.0"))
        settings.userAgent = "Custom/1.0"
        XCTAssertEqual(settings.userAgent, "Custom/1.0")
    }

    func testTheValuesAreStored() {
        let (settings, store) = makeSettings()
        settings.bookshelfSort = 4
        XCTAssertEqual(store.int(forKey: SettingsKey.bookshelfSort.rawValue), 4)
        settings.showRSS = false
        XCTAssertEqual(store.bool(forKey: SettingsKey.showRss.rawValue), false)
        settings.webDavUrl = "https://dav.example.com/dav/"
        XCTAssertEqual(store.string(forKey: SettingsKey.webDavUrl.rawValue), "https://dav.example.com/dav/")
    }

    func testThePreferenceKeysMatchTheUpstreamOnes() {
        // A few keys whose upstream string differs from the Kotlin name.
        XCTAssertEqual(SettingsKey.backupPath.rawValue, "backupUri")
        XCTAssertEqual(SettingsKey.ttsEngine.rawValue, "appTtsEngine")
        XCTAssertEqual(SettingsKey.prevKeys.rawValue, "prevKeyCodes")
        XCTAssertEqual(SettingsKey.nextKeys.rawValue, "nextKeyCodes")
        XCTAssertEqual(SettingsKey.exportToWebDav.rawValue, "webDavCacheBackup")
        XCTAssertEqual(SettingsKey.textSelectAble.rawValue, "selectText")
        XCTAssertEqual(SettingsKey.systemTypefaces.rawValue, "system_typefaces")
        XCTAssertEqual(SettingsKey.doublePageHorizontal.rawValue, "doubleHorizontalPage")
        XCTAssertEqual(SettingsKey.keepLight.rawValue, "keep_light")
        XCTAssertEqual(SettingsKey.autoRefresh.rawValue, "auto_refresh")
        XCTAssertEqual(SettingsKey.webDavUrl.rawValue, "web_dav_url")
        XCTAssertEqual(SettingsKey.clickActionTL.rawValue, "clickActionTopLeft")
        XCTAssertEqual(SettingsKey.clickActionBR.rawValue, "clickActionBottomRight")
    }

    func testTheClickActionDefaults() {
        // Upstream `AppConfig`.
        let (settings, _) = makeSettings()
        XCTAssertEqual(settings.clickAction(.topLeft), 2)
        XCTAssertEqual(settings.clickAction(.topCenter), 2)
        XCTAssertEqual(settings.clickAction(.topRight), 1)
        XCTAssertEqual(settings.clickAction(.middleLeft), 2)
        XCTAssertEqual(settings.clickAction(.middleCenter), 0)
        XCTAssertEqual(settings.clickAction(.middleRight), 1)
        XCTAssertEqual(settings.clickAction(.bottomLeft), 2)
        XCTAssertEqual(settings.clickAction(.bottomCenter), 1)
        XCTAssertEqual(settings.clickAction(.bottomRight), 1)
    }

    func testTheFontScaleFallsBackToTheSystemScale() {
        // Upstream `AppContextWrapper.getFontScale`.
        let (settings, _) = makeSettings()
        XCTAssertEqual(settings.fontScale(systemScale: 1.25), 1.25)
        settings.fontScalePreference = 12
        XCTAssertEqual(settings.fontScale(systemScale: 1.25), 1.2)
        settings.fontScalePreference = 20
        XCTAssertEqual(settings.fontScale(systemScale: 1.25), 1.25)
    }

    func testTheGroupSortUsesTheGroupValue() {
        let (settings, _) = makeSettings()
        settings.bookshelfSort = 1
        let group = BookGroup(groupId: 2, groupName: "Mine", bookSort: 3)
        XCTAssertEqual(settings.bookSort(forGroup: group), 3)
        let inherited = BookGroup(groupId: 2, groupName: "Mine", bookSort: -1)
        XCTAssertEqual(settings.bookSort(forGroup: inherited), 1)
    }
}
