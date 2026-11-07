//
//  BookSource.swift
//  LegadoCore
//
//  Port of `data/entities/BookSource.kt` and the rule entities in
//  `data/entities/rule/`.
//
//  The rules are stored as JSON strings in the `ruleSearch`, `ruleBookInfo`,
//  `ruleToc`, `ruleContent` and `ruleExplore` columns, exactly like upstream.
//

import Foundation

// MARK: - Rule entities

/// The fields shared by the search and explore rules.
public struct BookListRule: Codable, Equatable {
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?

    public init(
        bookList: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        bookUrl: String? = nil,
        coverUrl: String? = nil,
        wordCount: String? = nil
    ) {
        self.bookList = bookList
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.bookUrl = bookUrl
        self.coverUrl = coverUrl
        self.wordCount = wordCount
    }

    /// Build a list rule from a search rule — upstream `getSearchRule()`.
    public init(searchRule: SearchRule) {
        self.init(
            bookList: searchRule.bookList, name: searchRule.name, author: searchRule.author,
            intro: searchRule.intro, kind: searchRule.kind, lastChapter: searchRule.lastChapter,
            updateTime: searchRule.updateTime, bookUrl: searchRule.bookUrl,
            coverUrl: searchRule.coverUrl, wordCount: searchRule.wordCount
        )
    }

    /// Build a list rule from an explore rule — upstream `getExploreRule()`.
    public init(exploreRule: ExploreRule) {
        self.init(
            bookList: exploreRule.bookList, name: exploreRule.name, author: exploreRule.author,
            intro: exploreRule.intro, kind: exploreRule.kind, lastChapter: exploreRule.lastChapter,
            updateTime: exploreRule.updateTime, bookUrl: exploreRule.bookUrl,
            coverUrl: exploreRule.coverUrl, wordCount: exploreRule.wordCount
        )
    }
}

/// The search rule — upstream `SearchRule.kt`.
public struct SearchRule: Codable, Equatable {
    /// The keyword the rule verifies — upstream `checkKeyWord`.
    public var checkKeyWord: String?
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?

    public init(
        checkKeyWord: String? = nil,
        bookList: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        bookUrl: String? = nil,
        coverUrl: String? = nil,
        wordCount: String? = nil
    ) {
        self.checkKeyWord = checkKeyWord
        self.bookList = bookList
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.bookUrl = bookUrl
        self.coverUrl = coverUrl
        self.wordCount = wordCount
    }
}

/// The explore rule — upstream `ExploreRule.kt`.
public struct ExploreRule: Codable, Equatable {
    public var bookList: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var bookUrl: String?
    public var coverUrl: String?
    public var wordCount: String?

    public init(
        bookList: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        bookUrl: String? = nil,
        coverUrl: String? = nil,
        wordCount: String? = nil
    ) {
        self.bookList = bookList
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.bookUrl = bookUrl
        self.coverUrl = coverUrl
        self.wordCount = wordCount
    }
}

/// The book info rule — upstream `BookInfoRule.kt`.
public struct BookInfoRule: Codable, Equatable {
    /// Upstream names this field `init`; the backticks keep it usable in Swift.
    public var `init`: String?
    public var name: String?
    public var author: String?
    public var intro: String?
    public var kind: String?
    public var lastChapter: String?
    public var updateTime: String?
    public var coverUrl: String?
    public var tocUrl: String?
    public var wordCount: String?
    public var canReName: String?
    public var downloadUrls: String?

    public init(
        initRule: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        coverUrl: String? = nil,
        tocUrl: String? = nil,
        wordCount: String? = nil,
        canReName: String? = nil,
        downloadUrls: String? = nil
    ) {
        self.`init` = initRule
        self.name = name
        self.author = author
        self.intro = intro
        self.kind = kind
        self.lastChapter = lastChapter
        self.updateTime = updateTime
        self.coverUrl = coverUrl
        self.tocUrl = tocUrl
        self.wordCount = wordCount
        self.canReName = canReName
        self.downloadUrls = downloadUrls
    }
}

/// The table of contents rule — upstream `TocRule.kt`.
public struct TocRule: Codable, Equatable {
    public var preUpdateJs: String?
    public var chapterList: String?
    public var chapterName: String?
    public var chapterUrl: String?
    public var formatJs: String?
    public var isVolume: String?
    public var isVip: String?
    public var isPay: String?
    public var updateTime: String?
    public var nextTocUrl: String?

    public init(
        preUpdateJs: String? = nil,
        chapterList: String? = nil,
        chapterName: String? = nil,
        chapterUrl: String? = nil,
        formatJs: String? = nil,
        isVolume: String? = nil,
        isVip: String? = nil,
        isPay: String? = nil,
        updateTime: String? = nil,
        nextTocUrl: String? = nil
    ) {
        self.preUpdateJs = preUpdateJs
        self.chapterList = chapterList
        self.chapterName = chapterName
        self.chapterUrl = chapterUrl
        self.formatJs = formatJs
        self.isVolume = isVolume
        self.isVip = isVip
        self.isPay = isPay
        self.updateTime = updateTime
        self.nextTocUrl = nextTocUrl
    }
}

/// The chapter content rule — upstream `ContentRule.kt`.
public struct ContentRule: Codable, Equatable {
    public var content: String?
    public var title: String?
    public var nextContentUrl: String?
    public var webJs: String?
    public var sourceRegex: String?
    public var replaceRegex: String?
    public var imageStyle: String?
    public var imageDecode: String?
    public var payAction: String?

    public init(
        content: String? = nil,
        title: String? = nil,
        nextContentUrl: String? = nil,
        webJs: String? = nil,
        sourceRegex: String? = nil,
        replaceRegex: String? = nil,
        imageStyle: String? = nil,
        imageDecode: String? = nil,
        payAction: String? = nil
    ) {
        self.content = content
        self.title = title
        self.nextContentUrl = nextContentUrl
        self.webJs = webJs
        self.sourceRegex = sourceRegex
        self.replaceRegex = replaceRegex
        self.imageStyle = imageStyle
        self.imageDecode = imageDecode
        self.payAction = payAction
    }
}

/// The layout of a row of a login UI — upstream `FlexChildStyle.kt`.
public struct FlexChildStyle: Codable, Equatable {
    public var layout_flexGrow: Float
    public var layout_flexShrink: Float
    public var layout_alignSelf: String
    public var layout_flexBasisPercent: Float
    public var layout_wrapBefore: Bool

    public init(
        layout_flexGrow: Float = 0,
        layout_flexShrink: Float = 1,
        layout_alignSelf: String = "auto",
        layout_flexBasisPercent: Float = -1,
        layout_wrapBefore: Bool = false
    ) {
        self.layout_flexGrow = layout_flexGrow
        self.layout_flexShrink = layout_flexShrink
        self.layout_alignSelf = layout_alignSelf
        self.layout_flexBasisPercent = layout_flexBasisPercent
        self.layout_wrapBefore = layout_wrapBefore
    }

    /// The upstream default style.
    public static let defaultStyle = FlexChildStyle()
}

/// A row of a login UI — upstream `RowUi.kt`.
public struct RowUi: Codable, Equatable {
    public enum Kind {
        public static let text = "text"
        public static let password = "password"
        public static let button = "button"
    }

    public var name: String
    public var type: String
    public var action: String?
    public var style: FlexChildStyle?

    public init(
        name: String = "",
        type: String = Kind.text,
        action: String? = nil,
        style: FlexChildStyle? = nil
    ) {
        self.name = name
        self.type = type
        self.action = action
        self.style = style
    }

    /// The effective style — upstream `RowUi.style()`.
    public var effectiveStyle: FlexChildStyle { style ?? .defaultStyle }
}

/// A category of the explore page — upstream `ExploreKind.kt`.
public struct ExploreKind: Codable, Equatable {
    public var title: String
    public var url: String?
    public var style: FlexChildStyle?

    public init(title: String = "", url: String? = nil, style: FlexChildStyle? = nil) {
        self.title = title
        self.url = url
        self.style = style
    }

    /// The effective style — upstream `ExploreKind.style()`.
    public var effectiveStyle: FlexChildStyle { style ?? .defaultStyle }
}

// MARK: - The source

/// A book source — upstream `data/entities/BookSource.kt`.
public struct BookSource: Equatable {
    public var bookSourceUrl: String
    public var bookSourceName: String
    public var bookSourceGroup: String?
    public var bookSourceType: Int64
    public var bookUrlPattern: String?
    public var customOrder: Int64
    public var enabled: Bool
    public var enabledExplore: Bool
    public var jsLib: String?
    public var enabledCookieJar: Bool
    public var concurrentRate: String?
    public var header: String?
    public var loginUrl: String?
    public var loginUi: String?
    public var loginCheckJs: String?
    public var coverDecodeJs: String?
    public var bookSourceComment: String?
    public var variableComment: String?
    public var lastUpdateTime: Int64
    public var respondTime: Int64
    public var weight: Int64
    public var exploreUrl: String?
    public var exploreScreen: String?
    public var ruleExplore: String?
    public var searchUrl: String?
    public var ruleSearch: String?
    public var ruleBookInfo: String?
    public var ruleToc: String?
    public var ruleContent: String?
    public var ruleReview: String?

    public init(
        bookSourceUrl: String,
        bookSourceName: String = "",
        bookSourceGroup: String? = nil,
        bookSourceType: Int64 = BookSourceType.default,
        bookUrlPattern: String? = nil,
        customOrder: Int64 = 0,
        enabled: Bool = true,
        enabledExplore: Bool = true,
        jsLib: String? = nil,
        enabledCookieJar: Bool = false,
        concurrentRate: String? = nil,
        header: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        loginCheckJs: String? = nil,
        coverDecodeJs: String? = nil,
        bookSourceComment: String? = nil,
        variableComment: String? = nil,
        lastUpdateTime: Int64 = 0,
        respondTime: Int64 = 180_000,
        weight: Int64 = 0,
        exploreUrl: String? = nil,
        exploreScreen: String? = nil,
        ruleExplore: String? = nil,
        searchUrl: String? = nil,
        ruleSearch: String? = nil,
        ruleBookInfo: String? = nil,
        ruleToc: String? = nil,
        ruleContent: String? = nil,
        ruleReview: String? = nil
    ) {
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceName = bookSourceName
        self.bookSourceGroup = bookSourceGroup
        self.bookSourceType = bookSourceType
        self.bookUrlPattern = bookUrlPattern
        self.customOrder = customOrder
        self.enabled = enabled
        self.enabledExplore = enabledExplore
        self.jsLib = jsLib
        self.enabledCookieJar = enabledCookieJar
        self.concurrentRate = concurrentRate
        self.header = header
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.loginCheckJs = loginCheckJs
        self.coverDecodeJs = coverDecodeJs
        self.bookSourceComment = bookSourceComment
        self.variableComment = variableComment
        self.lastUpdateTime = lastUpdateTime
        self.respondTime = respondTime
        self.weight = weight
        self.exploreUrl = exploreUrl
        self.exploreScreen = exploreScreen
        self.ruleExplore = ruleExplore
        self.searchUrl = searchUrl
        self.ruleSearch = ruleSearch
        self.ruleBookInfo = ruleBookInfo
        self.ruleToc = ruleToc
        self.ruleContent = ruleContent
        self.ruleReview = ruleReview
    }

    public init(row: StorageRow) {
        bookSourceUrl = row["bookSourceUrl"]?.stringValue ?? ""
        bookSourceName = row["bookSourceName"]?.stringValue ?? ""
        bookSourceGroup = row["bookSourceGroup"]?.stringValue
        bookSourceType = row["bookSourceType"]?.intValue ?? BookSourceType.default
        bookUrlPattern = row["bookUrlPattern"]?.stringValue
        customOrder = row["customOrder"]?.intValue ?? 0
        enabled = row["enabled"]?.boolValue ?? true
        enabledExplore = row["enabledExplore"]?.boolValue ?? true
        jsLib = row["jsLib"]?.stringValue
        enabledCookieJar = row["enabledCookieJar"]?.boolValue ?? false
        concurrentRate = row["concurrentRate"]?.stringValue
        header = row["header"]?.stringValue
        loginUrl = row["loginUrl"]?.stringValue
        loginUi = row["loginUi"]?.stringValue
        loginCheckJs = row["loginCheckJs"]?.stringValue
        coverDecodeJs = row["coverDecodeJs"]?.stringValue
        bookSourceComment = row["bookSourceComment"]?.stringValue
        variableComment = row["variableComment"]?.stringValue
        lastUpdateTime = row["lastUpdateTime"]?.intValue ?? 0
        respondTime = row["respondTime"]?.intValue ?? 180_000
        weight = row["weight"]?.intValue ?? 0
        exploreUrl = row["exploreUrl"]?.stringValue
        exploreScreen = row["exploreScreen"]?.stringValue
        ruleExplore = row["ruleExplore"]?.stringValue
        searchUrl = row["searchUrl"]?.stringValue
        ruleSearch = row["ruleSearch"]?.stringValue
        ruleBookInfo = row["ruleBookInfo"]?.stringValue
        ruleToc = row["ruleToc"]?.stringValue
        ruleContent = row["ruleContent"]?.stringValue
        ruleReview = row["ruleReview"]?.stringValue
    }

    public var row: StorageRow {
        [
            "bookSourceUrl": .text(bookSourceUrl),
            "bookSourceName": .text(bookSourceName),
            "bookSourceGroup": bookSourceGroup.map { StorageValue.text($0) } ?? .null,
            "bookSourceType": .integer(bookSourceType),
            "bookUrlPattern": bookUrlPattern.map { StorageValue.text($0) } ?? .null,
            "customOrder": .integer(customOrder),
            "enabled": .integer(enabled ? 1 : 0),
            "enabledExplore": .integer(enabledExplore ? 1 : 0),
            "jsLib": jsLib.map { StorageValue.text($0) } ?? .null,
            "enabledCookieJar": .integer(enabledCookieJar ? 1 : 0),
            "concurrentRate": concurrentRate.map { StorageValue.text($0) } ?? .null,
            "header": header.map { StorageValue.text($0) } ?? .null,
            "loginUrl": loginUrl.map { StorageValue.text($0) } ?? .null,
            "loginUi": loginUi.map { StorageValue.text($0) } ?? .null,
            "loginCheckJs": loginCheckJs.map { StorageValue.text($0) } ?? .null,
            "coverDecodeJs": coverDecodeJs.map { StorageValue.text($0) } ?? .null,
            "bookSourceComment": bookSourceComment.map { StorageValue.text($0) } ?? .null,
            "variableComment": variableComment.map { StorageValue.text($0) } ?? .null,
            "lastUpdateTime": .integer(lastUpdateTime),
            "respondTime": .integer(respondTime),
            "weight": .integer(weight),
            "exploreUrl": exploreUrl.map { StorageValue.text($0) } ?? .null,
            "exploreScreen": exploreScreen.map { StorageValue.text($0) } ?? .null,
            "ruleExplore": ruleExplore.map { StorageValue.text($0) } ?? .null,
            "searchUrl": searchUrl.map { StorageValue.text($0) } ?? .null,
            "ruleSearch": ruleSearch.map { StorageValue.text($0) } ?? .null,
            "ruleBookInfo": ruleBookInfo.map { StorageValue.text($0) } ?? .null,
            "ruleToc": ruleToc.map { StorageValue.text($0) } ?? .null,
            "ruleContent": ruleContent.map { StorageValue.text($0) } ?? .null,
            "ruleReview": ruleReview.map { StorageValue.text($0) } ?? .null
        ]
    }

    // MARK: - Groups

    /// The groups of the source, split on the upstream separator.
    public var groups: [String] {
        guard let bookSourceGroup, !bookSourceGroup.isEmpty else { return [] }
        return bookSourceGroup
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Upstream `BookSource.addGroup`.
    public mutating func addGroup(_ group: String) {
        let trimmed = group.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var current = groups
        if !current.contains(trimmed) { current.append(trimmed) }
        bookSourceGroup = current.joined(separator: ",")
    }

    /// Upstream `BookSource.removeGroup`.
    public mutating func removeGroup(_ group: String) {
        let trimmed = group.trimmingCharacters(in: .whitespaces)
        let current = groups.filter { $0 != trimmed }
        bookSourceGroup = current.isEmpty ? nil : current.joined(separator: ",")
    }

    /// Upstream `BookSource.hasGroup`.
    public func hasGroup(_ group: String) -> Bool {
        groups.contains(group.trimmingCharacters(in: .whitespaces))
    }

    /// Upstream `BookSource.getInvalidGroupNames` — groups that mark the source
    /// as broken ("失效") or as timed out ("校验超时").
    public var invalidGroupNames: [String] {
        groups.filter { $0.contains("失效") || $0.contains("校验超时") }
    }

    /// Removes the invalid groups — upstream `removeInvalidGroups`.
    public mutating func removeInvalidGroups() {
        let invalid = invalidGroupNames
        guard !invalid.isEmpty else { return }
        let remaining = groups.filter { !invalid.contains($0) }
        bookSourceGroup = remaining.isEmpty ? nil : remaining.joined(separator: ",")
    }

    // MARK: - Rules

    /// The search rule — upstream `getSearchRule()`.
    public var searchRule: SearchRule? { BookSource.decode(ruleSearch) }
    /// The explore rule — upstream `getExploreRule()`.
    public var exploreRule: ExploreRule? { BookSource.decode(ruleExplore) }
    /// The book info rule — upstream `getBookInfoRule()`.
    public var bookInfoRule: BookInfoRule? { BookSource.decode(ruleBookInfo) }
    /// The table of contents rule — upstream `getTocRule()`.
    public var tocRule: TocRule? { BookSource.decode(ruleToc) }
    /// The content rule — upstream `getContentRule()`.
    public var contentRule: ContentRule? { BookSource.decode(ruleContent) }

    /// Decodes a rule from its JSON column.
    static func decode<T: Decodable>(_ text: String?, as type: T.Type = T.self) -> T? {
        guard let text, !text.isEmpty, text != "null" else { return nil }
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// Encodes a rule into its JSON column.
    static func encode<T: Encodable>(_ value: T?) -> String? {
        guard let value else { return nil }
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Helpers

    /// Upstream `BookSource.getBookType()`.
    public var bookType: Int64 {
        switch bookSourceType {
        case BookSourceType.file: return BookType.text | BookType.webFile
        case BookSourceType.image: return BookType.image
        case BookSourceType.audio: return BookType.audio
        default: return BookType.text
        }
    }

    /// The variable store of the source — upstream `BaseSource.getVariable/putVariable`
    /// keeps the variables in the cache manager, keyed by the source key. The box
    /// writes through to that store so the variables survive the evaluation.
    public var variableBox: RuleDataBox {
        let sourceKey = key
        return RuleDataBox(
            json: BookSourceVariables.sourceVariables(sourceKey),
            sourceKey: sourceKey,
            sourceName: bookSourceName,
            bookSource: self
        ) { variables in
            BookSourceVariables.setVariables(variables, for: sourceKey)
        }
    }
}

extension BookSource: Identifiable {
    /// The identity of a source — its address.
    public var id: String { bookSourceUrl }
}

/// The variables a source has written — upstream `BaseSource.putVariable/getVariable`
/// stores them in the cache manager under `v_<key>_<name>`.
public enum BookSourceVariables {
    private static var storage: [String: [String: String]] = [:]
    private static let lock = NSLock()

    public static func sourceVariables(_ key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let variables = storage[key], !variables.isEmpty else { return nil }
        return RuleDataBox(variables: variables).json
    }

    public static func setSourceVariable(_ key: String, _ name: String, _ value: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key, default: [:]][name] = value
    }

    /// Replace the whole variable set of a source.
    public static func setVariables(_ variables: [String: String], for key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = variables
    }

    public static func clearSourceVariables(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = nil
    }
}
