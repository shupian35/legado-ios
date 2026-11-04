//
//  Book.swift
//  LegadoCore
//
//  Port of the upstream book entities:
//  `data/entities/Book.kt`, `BookGroup.kt`, `BookChapter.kt`,
//  `data/entities/BaseBook.kt` and `data/entities/rule/*` helpers.
//
//  The column names match the upstream Room schema exactly so a backup can be
//  moved between the two apps.
//

import Foundation

/// The book types — upstream `constant/BookType.kt`.
///
/// A book can have several types at once, every type is one bit of the
/// `type` column.
public enum BookType {
    /// 8 — a text book.
    public static let text: Int64 = 0b1000
    /// 16 — the last update failed.
    public static let updateError: Int64 = 0b10000
    /// 32 — an audio book.
    public static let audio: Int64 = 0b100000
    /// 64 — an image (comic) book.
    public static let image: Int64 = 0b1000000
    /// 128 — a site that only offers downloads.
    public static let webFile: Int64 = 0b10000000
    /// 256 — a local book.
    public static let local: Int64 = 0b100000000
    /// 512 — the book file was extracted from an archive.
    public static let archive: Int64 = 0b1000000000
    /// 1024 — a temporary book that is not on the shelf yet.
    public static let notShelf: Int64 = 0b100_0000_0000

    /// Every type a book source can produce.
    public static let allBookType: Int64 = text | image | audio | webFile

    /// Upstream `BookType.allBookTypeLocal`.
    public static let allBookTypeLocal: Int64 = text | image | audio | webFile | local

    /// Upstream `BookType.localTag` — the origin prefix of a local book.
    public static let localTag = "loc_book"

    /// Upstream `BookType.webDavTag` — the origin prefix of a WebDAV book.
    public static let webDavTag = "webDav::"

    /// `true` when the mask contains the type.
    public static func contains(_ mask: Int64, _ type: Int64) -> Bool {
        (mask & type) != 0
    }
}

/// The book source types — upstream `constant/BookSourceType.kt`.
public enum BookSourceType {
    /// 0 — text.
    public static let `default`: Int64 = 0
    /// 1 — audio.
    public static let audio: Int64 = 1
    /// 2 — image.
    public static let image: Int64 = 2
    /// 3 — download only.
    public static let file: Int64 = 3
}

/// The source kinds — upstream `constant/SourceType.kt`.
public enum SourceType {
    /// 0 — a book source.
    public static let book: Int64 = 0
    /// 1 — an RSS source.
    public static let rss: Int64 = 1
}

/// A book group — upstream `data/entities/BookGroup.kt`.
public struct BookGroup: Equatable {
    /// The upstream well known group ids — upstream
    /// `data/entities/BookGroup.kt` companion object.
    ///
    /// The negative ids are the "virtual" groups the bookshelf shows on top of
    /// the user groups; the user groups use positive ids so that the `group`
    /// column of `books` can hold them as a bit mask.
    public enum Id {
        /// -100 — the root group of the discovery page.
        public static let root: Int64 = -100
        /// -1 — 全部.
        public static let all: Int64 = -1
        /// -2 — 本地.
        public static let local: Int64 = -2
        /// -3 — 音频.
        public static let audio: Int64 = -3
        /// -4 — 网络未分组.
        public static let netNoGroup: Int64 = -4
        /// -5 — 本地未分组.
        public static let localNoGroup: Int64 = -5
        /// -11 — 更新失败.
        public static let updateError: Int64 = -11

        /// Every well known group id.
        public static let allIds: [Int64] = [root, all, local, audio, netNoGroup, localNoGroup, updateError]
    }

    public var groupId: Int64
    public var groupName: String
    public var cover: String?
    public var order: Int64
    public var enableRefresh: Bool
    public var show: Bool
    public var bookSort: Int64

    public init(
        groupId: Int64,
        groupName: String,
        cover: String? = nil,
        order: Int64 = 0,
        enableRefresh: Bool = true,
        show: Bool = true,
        bookSort: Int64 = -1
    ) {
        self.groupId = groupId
        self.groupName = groupName
        self.cover = cover
        self.order = order
        self.enableRefresh = enableRefresh
        self.show = show
        self.bookSort = bookSort
    }

    public init(row: StorageRow) {
        groupId = row["groupId"]?.intValue ?? 0
        groupName = row["groupName"]?.stringValue ?? ""
        cover = row["cover"]?.stringValue
        order = row["order"]?.intValue ?? 0
        enableRefresh = row["enableRefresh"]?.boolValue ?? true
        show = row["show"]?.boolValue ?? true
        bookSort = row["bookSort"]?.intValue ?? -1
    }

    public var row: StorageRow {
        [
            "groupId": .integer(groupId),
            "groupName": .text(groupName),
            "cover": cover.map { StorageValue.text($0) } ?? .null,
            "order": .integer(order),
            "enableRefresh": .integer(enableRefresh ? 1 : 0),
            "show": .integer(show ? 1 : 0),
            "bookSort": .integer(bookSort)
        ]
    }

    /// The sort order to use for this group — upstream
    /// `BookGroup.getRealBookSort()`.
    ///
    /// A negative `bookSort` means "use the global bookshelf sort".
    public func realBookSort(fallback: Int64) -> Int64 {
        bookSort < 0 ? fallback : bookSort
    }

    /// The name shown in the group manager — upstream
    /// `BookGroup.getManageName(context)`.
    ///
    /// The well known groups get their kind appended, which is why upstream
    /// shows "全部(全部)". The quirk is reproduced on purpose.
    public func manageName(kindName: String? = nil) -> String {
        let suffix: String
        switch groupId {
        case Id.all: suffix = kindName ?? "全部"
        case Id.local: suffix = kindName ?? "本地"
        case Id.audio: suffix = kindName ?? "音频"
        case Id.netNoGroup: suffix = kindName ?? "网络未分组"
        case Id.localNoGroup: suffix = kindName ?? "本地未分组"
        case Id.updateError: suffix = kindName ?? "更新失败"
        default: return groupName
        }
        return "\(groupName)(\(suffix))"
    }

    /// `true` for the well known groups.
    public var isWellKnown: Bool {
        Id.allIds.contains(groupId)
    }
}

/// A book — upstream `data/entities/Book.kt`.
public struct Book: Equatable, Hashable {
    public var bookUrl: String
    public var tocUrl: String
    public var origin: String
    public var originName: String
    public var name: String
    public var author: String
    public var kind: String?
    public var customTag: String?
    public var coverUrl: String?
    public var customCoverUrl: String?
    public var intro: String?
    public var customIntro: String?
    public var charset: String?
    public var type: Int64
    /// The bit mask of the groups the book belongs to.
    public var group: Int64
    public var latestChapterTitle: String?
    public var latestChapterTime: Int64
    public var lastCheckTime: Int64
    public var lastCheckCount: Int64
    public var totalChapterNum: Int64
    public var durChapterTitle: String?
    public var durChapterIndex: Int64
    public var durChapterPos: Int64
    public var durChapterTime: Int64
    public var wordCount: String?
    public var canUpdate: Bool
    public var order: Int64
    public var originOrder: Int64
    public var variable: String?
    public var readConfig: String?
    public var syncTime: Int64

    // Transient — not stored in the database (upstream `BaseBook`).
    /// The cached detail page.
    public var infoHtml: String?
    /// The cached table-of-contents page.
    public var tocHtml: String?
    /// The download links of a "file" book source.
    public var downloadUrls: [String]?
    /// Whether the chapter list is stored in reverse order.
    public var reverseToc: Bool = false

    /// The per-book read configuration — upstream `Book.ReadConfig`.
    ///
    /// It is stored as JSON in the `readConfig` column.
    public var readConfigBox: BookReadConfig {
        get {
            guard let readConfig, let value = try? JSONValue.parse(readConfig), case .object(let object) = value else {
                return BookReadConfig()
            }
            var config = BookReadConfig()
            if let reverseToc = object["reverseToc"]?.boolValue { config.reverseToc = reverseToc }
            if let pageAnim = object["pageAnim"]?.intValue { config.pageAnim = Int(pageAnim) }
            if let reSegment = object["reSegment"]?.boolValue { config.reSegment = reSegment }
            if let imageStyle = object["imageStyle"]?.textValue { config.imageStyle = imageStyle }
            if let useReplaceRule = object["useReplaceRule"]?.boolValue { config.useReplaceRule = useReplaceRule }
            if let delTag = object["delTag"]?.intValue { config.delTag = delTag }
            if let ttsEngine = object["ttsEngine"]?.textValue { config.ttsEngine = ttsEngine }
            if let splitLongChapter = object["splitLongChapter"]?.boolValue { config.splitLongChapter = splitLongChapter }
            if let readSimulating = object["readSimulating"]?.boolValue { config.readSimulating = readSimulating }
            if let startDate = object["startDate"]?.textValue { config.startDate = startDate }
            if let startChapter = object["startChapter"]?.intValue { config.startChapter = Int(startChapter) }
            if let dailyChapters = object["dailyChapters"]?.intValue { config.dailyChapters = Int(dailyChapters) }
            return config
        }
        set {
            var object: [String: JSONValue] = [:]
            object["reverseToc"] = .bool(newValue.reverseToc)
            if let pageAnim = newValue.pageAnim { object["pageAnim"] = .number(Double(pageAnim)) }
            object["reSegment"] = .bool(newValue.reSegment)
            if let imageStyle = newValue.imageStyle { object["imageStyle"] = .string(imageStyle) }
            if let useReplaceRule = newValue.useReplaceRule { object["useReplaceRule"] = .bool(useReplaceRule) }
            object["delTag"] = .number(Double(newValue.delTag))
            if let ttsEngine = newValue.ttsEngine { object["ttsEngine"] = .string(ttsEngine) }
            object["splitLongChapter"] = .bool(newValue.splitLongChapter)
            object["readSimulating"] = .bool(newValue.readSimulating)
            if let startDate = newValue.startDate { object["startDate"] = .string(startDate) }
            if let startChapter = newValue.startChapter { object["startChapter"] = .number(Double(startChapter)) }
            object["dailyChapters"] = .number(Double(newValue.dailyChapters))
            readConfig = JSONValue.object(object).jsonString
        }
    }

    /// Whether the replace / purify rules are applied to the content.
    ///
    /// Upstream `Book.getUseReplaceRule()`: the per-book flag wins, image and
    /// EPUB books default to off, everything else uses the app default.
    public var useReplaceRule: Bool {
        get {
            if let configured = readConfigBox.useReplaceRule { return configured }
            if isImage || isEpub { return false }
            return true
        }
        set {
            var config = readConfigBox
            config.useReplaceRule = newValue
            readConfigBox = config
        }
    }

    /// Whether the book is a comic — upstream `BookExtensions.isImage`.
    public var isImage: Bool {
        BookType.contains(type, BookType.image)
    }

    /// Whether the book is a local book — upstream `BookExtensions.isLocal`.
    public var isLocal: Bool {
        if type == 0 {
            return origin == BookType.localTag || origin.hasPrefix(BookType.webDavTag)
        }
        return BookType.contains(type, BookType.local)
    }

    /// Whether the book is a local EPUB — upstream `BookExtensions.isEpub`.
    public var isEpub: Bool {
        isLocal && originName.lowercased().hasSuffix(".epub")
    }

    /// Whether the book is a local TXT — upstream `BookExtensions.isLocalTxt`
    /// (`BookExtensions.kt:53-54`).
    public var isLocalTxt: Bool {
        isLocal && originName.lowercased().hasSuffix(".txt")
    }

    /// Whether the book is a local UMD — upstream `BookExtensions.isUmd`.
    public var isUmd: Bool {
        isLocal && originName.lowercased().hasSuffix(".umd")
    }

    /// Whether the book is a local PDF — upstream `BookExtensions.isPdf`.
    public var isPdf: Bool {
        isLocal && originName.lowercased().hasSuffix(".pdf")
    }

    /// Whether the book is an online TXT — upstream `BookExtensions.isOnLineTxt`
    /// (`BookExtensions.kt:70-71`).
    public var isOnLineTxt: Bool {
        !isLocal && BookType.contains(type, BookType.text)
    }

    /// Whether the paragraphs are re-segmented — upstream `Book.getReSegment()`.
    public var reSegment: Bool {
        get { readConfigBox.reSegment }
        set {
            var config = readConfigBox
            config.reSegment = newValue
            readConfigBox = config
        }
    }

    /// Whether the given tag is removed from the content — upstream
    /// `Book.getDelTag(tag)`.
    public func hasDelTag(_ tag: Int64) -> Bool {
        readConfigBox.delTag & tag == tag
    }

    /// The bit mask of the removed tags with `tag` added — upstream
    /// `Book.addDelTag(tag)`.
    ///
    /// The upstream writes `config.delTag = config.delTag and tag`, which can
    /// never switch a tag on (the mask starts at zero). The port uses the
    /// intended `or` so that the feature works; see the parity matrix.
    public func addingDelTag(_ tag: Int64) -> Int64 {
        readConfigBox.delTag | tag
    }

    /// The bit mask of the removed tags with `tag` cleared — upstream
    /// `Book.removeDelTag(tag)`.
    public func removingDelTag(_ tag: Int64) -> Int64 {
        readConfigBox.delTag & ~tag
    }

    public init(
        bookUrl: String = "",
        tocUrl: String = "",
        origin: String = "",
        originName: String = "",
        name: String = "",
        author: String = "",
        kind: String? = nil,
        customTag: String? = nil,
        coverUrl: String? = nil,
        customCoverUrl: String? = nil,
        intro: String? = nil,
        customIntro: String? = nil,
        charset: String? = nil,
        type: Int64 = BookType.text,
        group: Int64 = 0,
        latestChapterTitle: String? = nil,
        latestChapterTime: Int64 = 0,
        lastCheckTime: Int64 = 0,
        lastCheckCount: Int64 = 0,
        totalChapterNum: Int64 = 0,
        durChapterTitle: String? = nil,
        durChapterIndex: Int64 = 0,
        durChapterPos: Int64 = 0,
        durChapterTime: Int64 = 0,
        wordCount: String? = nil,
        canUpdate: Bool = true,
        order: Int64 = 0,
        originOrder: Int64 = 0,
        variable: String? = nil,
        readConfig: String? = nil,
        syncTime: Int64 = 0,
        infoHtml: String? = nil,
        tocHtml: String? = nil,
        downloadUrls: [String]? = nil,
        reverseToc: Bool = false
    ) {
        self.bookUrl = bookUrl
        self.tocUrl = tocUrl
        self.origin = origin
        self.originName = originName
        self.name = name
        self.author = author
        self.kind = kind
        self.customTag = customTag
        self.coverUrl = coverUrl
        self.customCoverUrl = customCoverUrl
        self.intro = intro
        self.customIntro = customIntro
        self.charset = charset
        self.type = type
        self.group = group
        self.latestChapterTitle = latestChapterTitle
        self.latestChapterTime = latestChapterTime
        self.lastCheckTime = lastCheckTime
        self.lastCheckCount = lastCheckCount
        self.totalChapterNum = totalChapterNum
        self.durChapterTitle = durChapterTitle
        self.durChapterIndex = durChapterIndex
        self.durChapterPos = durChapterPos
        self.durChapterTime = durChapterTime
        self.wordCount = wordCount
        self.canUpdate = canUpdate
        self.order = order
        self.originOrder = originOrder
        self.variable = variable
        self.readConfig = readConfig
        self.syncTime = syncTime
        self.infoHtml = infoHtml
        self.tocHtml = tocHtml
        self.downloadUrls = downloadUrls
        self.reverseToc = reverseToc
    }

    public init(row: StorageRow) {
        bookUrl = row["bookUrl"]?.stringValue ?? ""
        tocUrl = row["tocUrl"]?.stringValue ?? ""
        origin = row["origin"]?.stringValue ?? ""
        originName = row["originName"]?.stringValue ?? ""
        name = row["name"]?.stringValue ?? ""
        author = row["author"]?.stringValue ?? ""
        kind = row["kind"]?.stringValue
        customTag = row["customTag"]?.stringValue
        coverUrl = row["coverUrl"]?.stringValue
        customCoverUrl = row["customCoverUrl"]?.stringValue
        intro = row["intro"]?.stringValue
        customIntro = row["customIntro"]?.stringValue
        charset = row["charset"]?.stringValue
        type = row["type"]?.intValue ?? BookType.text
        group = row["group"]?.intValue ?? 0
        latestChapterTitle = row["latestChapterTitle"]?.stringValue
        latestChapterTime = row["latestChapterTime"]?.intValue ?? 0
        lastCheckTime = row["lastCheckTime"]?.intValue ?? 0
        lastCheckCount = row["lastCheckCount"]?.intValue ?? 0
        totalChapterNum = row["totalChapterNum"]?.intValue ?? 0
        durChapterTitle = row["durChapterTitle"]?.stringValue
        durChapterIndex = row["durChapterIndex"]?.intValue ?? 0
        durChapterPos = row["durChapterPos"]?.intValue ?? 0
        durChapterTime = row["durChapterTime"]?.intValue ?? 0
        wordCount = row["wordCount"]?.stringValue
        canUpdate = row["canUpdate"]?.boolValue ?? true
        order = row["order"]?.intValue ?? 0
        originOrder = row["originOrder"]?.intValue ?? 0
        variable = row["variable"]?.stringValue
        readConfig = row["readConfig"]?.stringValue
        syncTime = row["syncTime"]?.intValue ?? 0
    }

    public var row: StorageRow {
        [
            "bookUrl": .text(bookUrl),
            "tocUrl": .text(tocUrl),
            "origin": .text(origin),
            "originName": .text(originName),
            "name": .text(name),
            "author": .text(author),
            "kind": kind.map { StorageValue.text($0) } ?? .null,
            "customTag": customTag.map { StorageValue.text($0) } ?? .null,
            "coverUrl": coverUrl.map { StorageValue.text($0) } ?? .null,
            "customCoverUrl": customCoverUrl.map { StorageValue.text($0) } ?? .null,
            "intro": intro.map { StorageValue.text($0) } ?? .null,
            "customIntro": customIntro.map { StorageValue.text($0) } ?? .null,
            "charset": charset.map { StorageValue.text($0) } ?? .null,
            "type": .integer(type),
            "group": .integer(group),
            "latestChapterTitle": latestChapterTitle.map { StorageValue.text($0) } ?? .null,
            "latestChapterTime": .integer(latestChapterTime),
            "lastCheckTime": .integer(lastCheckTime),
            "lastCheckCount": .integer(lastCheckCount),
            "totalChapterNum": .integer(totalChapterNum),
            "durChapterTitle": durChapterTitle.map { StorageValue.text($0) } ?? .null,
            "durChapterIndex": .integer(durChapterIndex),
            "durChapterPos": .integer(durChapterPos),
            "durChapterTime": .integer(durChapterTime),
            "wordCount": wordCount.map { StorageValue.text($0) } ?? .null,
            "canUpdate": .integer(canUpdate ? 1 : 0),
            "order": .integer(order),
            "originOrder": .integer(originOrder),
            "variable": variable.map { StorageValue.text($0) } ?? .null,
            "readConfig": readConfig.map { StorageValue.text($0) } ?? .null,
            "syncTime": .integer(syncTime)
        ]
    }

    /// `true` when the book is on the shelf.
    ///
    /// Upstream stores the "not on the shelf" state in the `group` bit mask
    /// (`BookType.notShelf`), not in a separate column.
    public var isOnShelf: Bool {
        !BookType.contains(type, BookType.notShelf)
    }

    /// `true` when the book is downloaded as a file (a "file" book source).
    public var isWebFile: Bool {
        BookType.contains(type, BookType.webFile)
    }

    /// The cover the UI shows — the custom cover wins.
    public var displayCoverUrl: String? {
        if let customCoverUrl, !customCoverUrl.isEmpty { return customCoverUrl }
        guard let coverUrl, !coverUrl.isEmpty else { return nil }
        return coverUrl
    }

    /// The introduction the UI shows — the custom introduction wins.
    /// Upstream `Book.getDisplayIntro()` (`Book.kt:167`).
    public var displayIntro: String? {
        if let customIntro, !customIntro.isEmpty { return customIntro }
        guard let intro, !intro.isEmpty else { return nil }
        return intro
    }
}

/// A chapter — upstream `data/entities/BookChapter.kt`.
public struct BookChapter: Equatable, Hashable {
    public var url: String
    public var title: String
    public var isVolume: Bool
    public var baseUrl: String
    public var bookUrl: String
    public var index: Int64
    public var isVip: Bool
    public var isPay: Bool
    public var resourceUrl: String?
    public var tag: String?
    public var wordCount: String?
    public var start: Int64?
    public var end: Int64?
    public var startFragmentId: String?
    public var endFragmentId: String?

    /// The MD5 of the title — upstream `BookChapter.titleMD5`.
    public var titleMD5: String?

    /// The variable store of the chapter — upstream `BookChapter` implements
    /// `RuleDataInterface` and keeps its variables in the `variable` column.
    ///
    /// The box is STORED, not computed: upstream the `variableMap` is a shared
    /// mutable map, so a rule that writes `@put` must be able to see its own
    /// writes. A computed box would throw every write away.
    public var variableBox: RuleDataBox

    /// The `variable` column — the JSON form of the variable store.
    public var variable: String? {
        get { variableBox.json }
        set { variableBox = RuleDataBox(json: newValue) }
    }

    public init(
        url: String = "",
        title: String = "",
        isVolume: Bool = false,
        baseUrl: String = "",
        bookUrl: String = "",
        index: Int64 = 0,
        isVip: Bool = false,
        isPay: Bool = false,
        resourceUrl: String? = nil,
        tag: String? = nil,
        wordCount: String? = nil,
        start: Int64? = nil,
        end: Int64? = nil,
        startFragmentId: String? = nil,
        endFragmentId: String? = nil,
        variable: String? = nil
    ) {
        self.variableBox = RuleDataBox(json: variable)
        self.url = url
        self.title = title
        self.isVolume = isVolume
        self.baseUrl = baseUrl
        self.bookUrl = bookUrl
        self.index = index
        self.isVip = isVip
        self.isPay = isPay
        self.resourceUrl = resourceUrl
        self.tag = tag
        self.wordCount = wordCount
        self.start = start
        self.end = end
        self.startFragmentId = startFragmentId
        self.endFragmentId = endFragmentId
    }

    public init(row: StorageRow) {
        variableBox = RuleDataBox(json: row["variable"]?.stringValue)
        url = row["url"]?.stringValue ?? ""
        title = row["title"]?.stringValue ?? ""
        isVolume = row["isVolume"]?.boolValue ?? false
        baseUrl = row["baseUrl"]?.stringValue ?? ""
        bookUrl = row["bookUrl"]?.stringValue ?? ""
        index = row["index"]?.intValue ?? 0
        isVip = row["isVip"]?.boolValue ?? false
        isPay = row["isPay"]?.boolValue ?? false
        resourceUrl = row["resourceUrl"]?.stringValue
        tag = row["tag"]?.stringValue
        wordCount = row["wordCount"]?.stringValue
        start = row["start"]?.intValue
        end = row["end"]?.intValue
        startFragmentId = row["startFragmentId"]?.stringValue
        endFragmentId = row["endFragmentId"]?.stringValue
    }

    public var row: StorageRow {
        [
            "url": .text(url),
            "title": .text(title),
            "isVolume": .integer(isVolume ? 1 : 0),
            "baseUrl": .text(baseUrl),
            "bookUrl": .text(bookUrl),
            "index": .integer(index),
            "isVip": .integer(isVip ? 1 : 0),
            "isPay": .integer(isPay ? 1 : 0),
            "resourceUrl": resourceUrl.map { StorageValue.text($0) } ?? .null,
            "tag": tag.map { StorageValue.text($0) } ?? .null,
            "wordCount": wordCount.map { StorageValue.text($0) } ?? .null,
            "start": start.map { StorageValue.integer($0) } ?? .null,
            "end": end.map { StorageValue.integer($0) } ?? .null,
            "startFragmentId": startFragmentId.map { StorageValue.text($0) } ?? .null,
            "endFragmentId": endFragmentId.map { StorageValue.text($0) } ?? .null,
            "variable": variable.map { StorageValue.text($0) } ?? .null
        ]
    }
}

/// A search result — upstream `data/entities/SearchBook.kt`.
public struct SearchBook: Equatable, Hashable {
    public var bookUrl: String
    public var origin: String
    public var originName: String
    public var type: Int64
    public var name: String
    public var author: String
    public var kind: String?
    public var coverUrl: String?
    public var intro: String?
    public var wordCount: String?
    public var latestChapterTitle: String?
    public var tocUrl: String
    public var time: Int64
    public var variable: String?
    public var originOrder: Int64
    public var chapterWordCountText: String?
    public var chapterWordCount: Int64
    public var respondTime: Int64

    // Transient — not stored in the database (upstream `BaseBook`).
    /// The cached detail page.
    public var infoHtml: String?
    /// The cached table-of-contents page.
    public var tocHtml: String?
    /// The origins that found the book — upstream
    /// `SearchBook.origins`.
    ///
    /// The upstream keeps it in a transient `LinkedHashSet` that starts with
    /// the origin of the book and grows with `addOrigin` when another source
    /// finds a book with the same name and author (upstream
    /// `SearchModel.mergeItems`). The search row shows its size as a badge
    /// (upstream `SearchAdapter.bvOriginCount`).
    public var origins: [String]

    public init(
        bookUrl: String = "",
        origin: String = "",
        originName: String = "",
        type: Int64 = BookType.text,
        name: String = "",
        author: String = "",
        kind: String? = nil,
        coverUrl: String? = nil,
        intro: String? = nil,
        wordCount: String? = nil,
        latestChapterTitle: String? = nil,
        tocUrl: String = "",
        time: Int64 = 0,
        variable: String? = nil,
        originOrder: Int64 = 0,
        chapterWordCountText: String? = nil,
        chapterWordCount: Int64 = 0,
        respondTime: Int64 = 0,
        infoHtml: String? = nil,
        tocHtml: String? = nil,
        origins: [String] = []
    ) {
        self.bookUrl = bookUrl
        self.origin = origin
        self.originName = originName
        self.type = type
        self.name = name
        self.author = author
        self.kind = kind
        self.coverUrl = coverUrl
        self.intro = intro
        self.wordCount = wordCount
        self.latestChapterTitle = latestChapterTitle
        self.tocUrl = tocUrl
        self.time = time
        self.variable = variable
        self.originOrder = originOrder
        self.chapterWordCountText = chapterWordCountText
        self.chapterWordCount = chapterWordCount
        self.respondTime = respondTime
        self.infoHtml = infoHtml
        self.tocHtml = tocHtml
        self.origins = origins
    }

    public init(row: StorageRow) {
        bookUrl = row["bookUrl"]?.stringValue ?? ""
        origin = row["origin"]?.stringValue ?? ""
        originName = row["originName"]?.stringValue ?? ""
        type = row["type"]?.intValue ?? BookType.text
        name = row["name"]?.stringValue ?? ""
        author = row["author"]?.stringValue ?? ""
        kind = row["kind"]?.stringValue
        coverUrl = row["coverUrl"]?.stringValue
        intro = row["intro"]?.stringValue
        wordCount = row["wordCount"]?.stringValue
        latestChapterTitle = row["latestChapterTitle"]?.stringValue
        tocUrl = row["tocUrl"]?.stringValue ?? ""
        time = row["time"]?.intValue ?? 0
        variable = row["variable"]?.stringValue
        originOrder = row["originOrder"]?.intValue ?? 0
        chapterWordCountText = row["chapterWordCountText"]?.stringValue
        chapterWordCount = row["chapterWordCount"]?.intValue ?? 0
        respondTime = row["respondTime"]?.intValue ?? 0
        origins = []
    }

    /// The books are equal when their address is the same — upstream
    /// `SearchBook.equals` (`other is SearchBook && other.bookUrl == bookUrl`).
    public static func == (lhs: SearchBook, rhs: SearchBook) -> Bool {
        lhs.bookUrl == rhs.bookUrl
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(bookUrl)
    }

    /// The kinds of the book — upstream `SearchBook.getKindList`.
    ///
    /// The kinds are stored in one comma separated string.
    public var kindList: [String] {
        guard let kind, !kind.isEmpty else { return [] }
        return kind
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    public var row: StorageRow {
        [
            "bookUrl": .text(bookUrl),
            "origin": .text(origin),
            "originName": .text(originName),
            "type": .integer(type),
            "name": .text(name),
            "author": .text(author),
            "kind": kind.map { StorageValue.text($0) } ?? .null,
            "coverUrl": coverUrl.map { StorageValue.text($0) } ?? .null,
            "intro": intro.map { StorageValue.text($0) } ?? .null,
            "wordCount": wordCount.map { StorageValue.text($0) } ?? .null,
            "latestChapterTitle": latestChapterTitle.map { StorageValue.text($0) } ?? .null,
            "tocUrl": .text(tocUrl),
            "time": .integer(time),
            "variable": variable.map { StorageValue.text($0) } ?? .null,
            "originOrder": .integer(originOrder),
            "chapterWordCountText": chapterWordCountText.map { StorageValue.text($0) } ?? .null,
            "chapterWordCount": .integer(chapterWordCount),
            "respondTime": .integer(respondTime)
        ]
    }
}

/// A bookmark — upstream `data/entities/Bookmark.kt`.
public struct Bookmark: Equatable {
    public var time: Int64
    public var bookName: String
    public var bookAuthor: String
    public var chapterIndex: Int64
    public var chapterPos: Int64
    public var chapterName: String
    public var bookText: String
    public var content: String

    public init(
        time: Int64,
        bookName: String,
        bookAuthor: String,
        chapterIndex: Int64 = 0,
        chapterPos: Int64 = 0,
        chapterName: String = "",
        bookText: String = "",
        content: String = ""
    ) {
        self.time = time
        self.bookName = bookName
        self.bookAuthor = bookAuthor
        self.chapterIndex = chapterIndex
        self.chapterPos = chapterPos
        self.chapterName = chapterName
        self.bookText = bookText
        self.content = content
    }

    public init(row: StorageRow) {
        time = row["time"]?.intValue ?? 0
        bookName = row["bookName"]?.stringValue ?? ""
        bookAuthor = row["bookAuthor"]?.stringValue ?? ""
        chapterIndex = row["chapterIndex"]?.intValue ?? 0
        chapterPos = row["chapterPos"]?.intValue ?? 0
        chapterName = row["chapterName"]?.stringValue ?? ""
        bookText = row["bookText"]?.stringValue ?? ""
        content = row["content"]?.stringValue ?? ""
    }

    public var row: StorageRow {
        [
            "time": .integer(time),
            "bookName": .text(bookName),
            "bookAuthor": .text(bookAuthor),
            "chapterIndex": .integer(chapterIndex),
            "chapterPos": .integer(chapterPos),
            "chapterName": .text(chapterName),
            "bookText": .text(bookText),
            "content": .text(content)
        ]
    }
}

/// The read history — upstream `data/entities/ReadRecord.kt`.
public struct ReadRecord: Equatable {
    public var deviceId: String
    public var bookName: String
    public var readTime: Int64
    public var lastRead: Int64

    public init(deviceId: String, bookName: String, readTime: Int64 = 0, lastRead: Int64 = 0) {
        self.deviceId = deviceId
        self.bookName = bookName
        self.readTime = readTime
        self.lastRead = lastRead
    }

    public init(row: StorageRow) {
        deviceId = row["deviceId"]?.stringValue ?? ""
        bookName = row["bookName"]?.stringValue ?? ""
        readTime = row["readTime"]?.intValue ?? 0
        lastRead = row["lastRead"]?.intValue ?? 0
    }

    public var row: StorageRow {
        [
            "deviceId": .text(deviceId),
            "bookName": .text(bookName),
            "readTime": .integer(readTime),
            "lastRead": .integer(lastRead)
        ]
    }

    /// The reading duration in a human readable form (the upstream
    /// `ReadRecord.getReadTimeText`).
    public var readDurationText: String {
        let total = max(0, readTime)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        }
        if minutes > 0 {
            return "\(minutes)分钟"
        }
        return "\(total)秒"
    }

    /// The moment of the last reading (the upstream `ReadRecord.getLastReadText`).
    public var lastReadText: String {
        guard lastRead > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(lastRead) / 1000))
    }
}

// MARK: - The simulated reading

extension Book: Identifiable {
    /// The identity of a book — its address.
    public var id: String { bookUrl }
}

extension Book {

    /// The date format of the simulation — upstream
    /// `DateTimeFormatter.ofPattern("yyyy-MM-dd")`.
    static let simulationDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// Whether the reading progress is simulated — upstream
    /// `Book.readSimulating()`.
    public func readSimulating() -> Bool {
        readConfigBox.readSimulating
    }

    /// The number of chapters that are unlocked today — upstream
    /// `Book.simulatedTotalChapterNum()`.
    ///
    /// With the simulation on, the chapters unlock day by day
    /// (`startChapter` + the days since `startDate` × `dailyChapters`); the
    /// result never exceeds the real number of chapters.
    public func simulatedTotalChapterNum(now: Date = Date()) -> Int64 {
        guard readSimulating() else { return totalChapterNum }
        let config = readConfigBox
        let daysPassed = daysSinceStart(config.startDate, now: now) + 1
        let unlocked = Int64(config.startChapter ?? 0) + Int64(daysPassed * config.dailyChapters)
        return min(totalChapterNum, max(0, unlocked))
    }

    /// The number of chapters that are not read yet — upstream
    /// `Book.getUnreadChapterNum()`.
    public func unreadChapterNum(now: Date = Date()) -> Int64 {
        max(simulatedTotalChapterNum(now: now) - durChapterIndex - 1, 0)
    }

    /// The number of days between the start date of the simulation and today
    /// — upstream `between(config.startDate, currentDate).days`.
    private func daysSinceStart(_ startDate: String?, now: Date) -> Int {
        guard let startDate, let date = Book.simulationDateFormatter.date(from: startDate) else { return 0 }
        let calendar = Calendar(identifier: .gregorian)
        let from = calendar.startOfDay(for: date)
        let to = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }
}

/// The tags that can be removed from the content of a book — upstream
/// `Book.hTag` and `Book.rubyTag`.
public enum BookTag: Int64, CaseIterable, Sendable {
    /// The `<h>` heading tag.
    case hTag = 2
    /// The `<ruby>` annotation tag.
    case rubyTag = 4

    /// The name shown in the UI.
    public var displayName: String {
        switch self {
        case .hTag: return "h标签"
        case .rubyTag: return "ruby标签"
        }
    }
}

/// The image display style of a comic — upstream `Book.imgStyleDefault`,
/// `Book.imgStyleFull`, `Book.imgStyleText` and `Book.imgStyleSingle`.
public enum BookImageStyle: String, CaseIterable, Sendable, Identifiable {
    /// The default style — the images are scaled to the page.
    case standard = "DEFAULT"
    /// The images fill the whole page.
    case full = "FULL"
    /// The images are shown as text (no image rendering).
    case text = "TEXT"
    /// One image per page.
    case single = "SINGLE"

    public var id: String { rawValue }

    /// The name shown in the UI — the upstream shows the raw value.
    public var displayName: String { rawValue }
}

/// One category of the explore list of a source — upstream
/// `BookSource.ruleExplore`, whose keys are the category names and whose
/// values are the category URLs.
public struct ExploreCategory: Identifiable, Equatable, Hashable, Sendable {
    /// The name shown in the UI.
    public let name: String
    /// The URL of the category.
    public let url: String

    public var id: String { url }

    public init(name: String, url: String) {
        self.name = name
        self.url = url
    }
}
