//
//  Misc.swift
//  LegadoCore
//
//  The remaining upstream entities:
//  `data/entities/{ReplaceRule,SearchKeyword,Cookie,Cache,RssSource,RssArticle,
//  RssReadRecord,RssStar,TxtTocRule,HttpTTS,RuleSub,DictRule,KeyboardAssist,Server}.kt`
//

import Foundation

/// A replace rule — upstream `data/entities/ReplaceRule.kt`.
public struct ReplaceRule: Equatable {
    public var id: Int64
    public var name: String
    public var group: String?
    public var pattern: String
    public var replacement: String
    public var scope: String?
    public var scopeTitle: Bool
    public var scopeContent: Bool
    public var excludeScope: String?
    public var isEnabled: Bool
    public var isRegex: Bool
    public var timeoutMillisecond: Int64
    public var sortOrder: Int64

    public init(
        id: Int64 = 0,
        name: String = "",
        group: String? = nil,
        pattern: String = "",
        replacement: String = "",
        scope: String? = nil,
        scopeTitle: Bool = false,
        scopeContent: Bool = true,
        excludeScope: String? = nil,
        isEnabled: Bool = true,
        isRegex: Bool = false,
        timeoutMillisecond: Int64 = 0,
        sortOrder: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.pattern = pattern
        self.replacement = replacement
        self.scope = scope
        self.scopeTitle = scopeTitle
        self.scopeContent = scopeContent
        self.excludeScope = excludeScope
        self.isEnabled = isEnabled
        self.isRegex = isRegex
        self.timeoutMillisecond = timeoutMillisecond
        self.sortOrder = sortOrder
    }

    public init(row: StorageRow) {
        id = row["id"]?.intValue ?? 0
        name = row["name"]?.stringValue ?? ""
        group = row["group"]?.stringValue
        pattern = row["pattern"]?.stringValue ?? ""
        replacement = row["replacement"]?.stringValue ?? ""
        scope = row["scope"]?.stringValue
        scopeTitle = row["scopeTitle"]?.boolValue ?? false
        scopeContent = row["scopeContent"]?.boolValue ?? true
        excludeScope = row["excludeScope"]?.stringValue
        isEnabled = row["isEnabled"]?.boolValue ?? true
        isRegex = row["isRegex"]?.boolValue ?? false
        timeoutMillisecond = row["timeoutMillisecond"]?.intValue ?? 0
        sortOrder = row["sortOrder"]?.intValue ?? 0
    }

    public var row: StorageRow {
        [
            "id": .integer(id),
            "name": .text(name),
            "group": group.map { StorageValue.text($0) } ?? .null,
            "pattern": .text(pattern),
            "replacement": .text(replacement),
            "scope": scope.map { StorageValue.text($0) } ?? .null,
            "scopeTitle": .integer(scopeTitle ? 1 : 0),
            "scopeContent": .integer(scopeContent ? 1 : 0),
            "excludeScope": excludeScope.map { StorageValue.text($0) } ?? .null,
            "isEnabled": .integer(isEnabled ? 1 : 0),
            "isRegex": .integer(isRegex ? 1 : 0),
            "timeoutMillisecond": .integer(timeoutMillisecond),
            "sortOrder": .integer(sortOrder)
        ]
    }
}

/// A search keyword — upstream `data/entities/SearchKeyword.kt`.
public struct SearchKeyword: Equatable {
    public var word: String
    public var usage: Int64
    public var lastUseTime: Int64

    public init(word: String, usage: Int64 = 0, lastUseTime: Int64 = 0) {
        self.word = word
        self.usage = usage
        self.lastUseTime = lastUseTime
    }

    public init(row: StorageRow) {
        word = row["word"]?.stringValue ?? ""
        usage = row["usage"]?.intValue ?? 0
        lastUseTime = row["lastUseTime"]?.intValue ?? 0
    }

    public var row: StorageRow {
        [
            "word": .text(word),
            "usage": .integer(usage),
            "lastUseTime": .integer(lastUseTime)
        ]
    }
}

/// A stored cookie — upstream `data/entities/Cookie.kt`.
public struct Cookie: Equatable {
    public var url: String
    public var cookie: String

    public init(url: String, cookie: String) {
        self.url = url
        self.cookie = cookie
    }

    public init(row: StorageRow) {
        url = row["url"]?.stringValue ?? ""
        cookie = row["cookie"]?.stringValue ?? ""
    }

    public var row: StorageRow {
        ["url": .text(url), "cookie": .text(cookie)]
    }
}

/// A cached value — upstream `data/entities/Cache.kt`.
public struct CacheEntry: Equatable {
    public var key: String
    public var value: String?
    /// The absolute deadline in milliseconds; `0` means "never expires".
    public var deadline: Int64

    public init(key: String, value: String? = nil, deadline: Int64 = 0) {
        self.key = key
        self.value = value
        self.deadline = deadline
    }

    public init(row: StorageRow) {
        key = row["key"]?.stringValue ?? ""
        value = row["value"]?.stringValue
        deadline = row["deadline"]?.intValue ?? 0
    }

    public var row: StorageRow {
        [
            "key": .text(key),
            "value": value.map { StorageValue.text($0) } ?? .null,
            "deadline": .integer(deadline)
        ]
    }
}

/// A rule for the table of contents of a TXT book — upstream `TxtTocRule.kt`.
public struct TxtTocRule: Identifiable, Equatable {
    public var id: Int64
    public var name: String
    public var rule: String
    public var example: String?
    public var serialNumber: Int64
    public var enable: Bool

    public init(
        id: Int64,
        name: String,
        rule: String,
        example: String? = nil,
        serialNumber: Int64 = 0,
        enable: Bool = true
    ) {
        self.id = id
        self.name = name
        self.rule = rule
        self.example = example
        self.serialNumber = serialNumber
        self.enable = enable
    }

    public init(row: StorageRow) {
        id = row["id"]?.intValue ?? 0
        name = row["name"]?.stringValue ?? ""
        rule = row["rule"]?.stringValue ?? ""
        example = row["example"]?.stringValue
        serialNumber = row["serialNumber"]?.intValue ?? 0
        enable = row["enable"]?.boolValue ?? true
    }

    public var row: StorageRow {
        [
            "id": .integer(id),
            "name": .text(name),
            "rule": .text(rule),
            "example": example.map { StorageValue.text($0) } ?? .null,
            "serialNumber": .integer(serialNumber),
            "enable": .integer(enable ? 1 : 0)
        ]
    }
}

/// A HTTP text to speech engine — upstream `data/entities/HttpTTS.kt`.
public struct HttpTTS: Identifiable, Equatable {
    public var id: Int64
    public var name: String
    public var url: String
    public var contentType: String?
    public var concurrentRate: String?
    public var loginUrl: String?
    public var loginUi: String?
    public var header: String?
    public var jsLib: String?
    public var enabledCookieJar: Bool
    public var loginCheckJs: String?
    public var lastUpdateTime: Int64

    public init(
        id: Int64,
        name: String,
        url: String,
        contentType: String? = nil,
        concurrentRate: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        header: String? = nil,
        jsLib: String? = nil,
        enabledCookieJar: Bool = false,
        loginCheckJs: String? = nil,
        lastUpdateTime: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.contentType = contentType
        self.concurrentRate = concurrentRate
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.header = header
        self.jsLib = jsLib
        self.enabledCookieJar = enabledCookieJar
        self.loginCheckJs = loginCheckJs
        self.lastUpdateTime = lastUpdateTime
    }

    public init(row: StorageRow) {
        id = row["id"]?.intValue ?? 0
        name = row["name"]?.stringValue ?? ""
        url = row["url"]?.stringValue ?? ""
        contentType = row["contentType"]?.stringValue
        concurrentRate = row["concurrentRate"]?.stringValue
        loginUrl = row["loginUrl"]?.stringValue
        loginUi = row["loginUi"]?.stringValue
        header = row["header"]?.stringValue
        jsLib = row["jsLib"]?.stringValue
        enabledCookieJar = row["enabledCookieJar"]?.boolValue ?? false
        loginCheckJs = row["loginCheckJs"]?.stringValue
        lastUpdateTime = row["lastUpdateTime"]?.intValue ?? 0
    }

    public var row: StorageRow {
        [
            "id": .integer(id),
            "name": .text(name),
            "url": .text(url),
            "contentType": contentType.map { StorageValue.text($0) } ?? .null,
            "concurrentRate": concurrentRate.map { StorageValue.text($0) } ?? .null,
            "loginUrl": loginUrl.map { StorageValue.text($0) } ?? .null,
            "loginUi": loginUi.map { StorageValue.text($0) } ?? .null,
            "header": header.map { StorageValue.text($0) } ?? .null,
            "jsLib": jsLib.map { StorageValue.text($0) } ?? .null,
            "enabledCookieJar": .integer(enabledCookieJar ? 1 : 0),
            "loginCheckJs": loginCheckJs.map { StorageValue.text($0) } ?? .null,
            "lastUpdateTime": .integer(lastUpdateTime)
        ]
    }
}

/// A subscription of rule updates — upstream `data/entities/RuleSub.kt`.
public struct RuleSub: Equatable, Identifiable {
    public var id: Int64
    public var name: String
    public var url: String
    public var type: Int64
    public var customOrder: Int64
    public var autoUpdate: Bool
    public var update: Int64

    public init(
        id: Int64,
        name: String,
        url: String,
        type: Int64 = 0,
        customOrder: Int64 = 0,
        autoUpdate: Bool = false,
        update: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.type = type
        self.customOrder = customOrder
        self.autoUpdate = autoUpdate
        self.update = update
    }

    public init(row: StorageRow) {
        id = row["id"]?.intValue ?? 0
        name = row["name"]?.stringValue ?? ""
        url = row["url"]?.stringValue ?? ""
        type = row["type"]?.intValue ?? 0
        customOrder = row["customOrder"]?.intValue ?? 0
        autoUpdate = row["autoUpdate"]?.boolValue ?? false
        update = row["update"]?.intValue ?? 0
    }

    public var row: StorageRow {
        [
            "id": .integer(id),
            "name": .text(name),
            "url": .text(url),
            "type": .integer(type),
            "customOrder": .integer(customOrder),
            "autoUpdate": .integer(autoUpdate ? 1 : 0),
            "update": .integer(update)
        ]
    }
}

/// A dictionary rule — upstream `data/entities/DictRule.kt`.
public struct DictRule: Identifiable, Equatable {
    public var name: String
    public var urlRule: String
    public var showRule: String
    public var enabled: Bool
    public var sortNumber: Int64

    /// The name is the identity of a dictionary rule (the upstream table has
    /// no id column).
    public var id: String { name }

    public init(
        name: String,
        urlRule: String,
        showRule: String,
        enabled: Bool = true,
        sortNumber: Int64 = 0
    ) {
        self.name = name
        self.urlRule = urlRule
        self.showRule = showRule
        self.enabled = enabled
        self.sortNumber = sortNumber
    }

    public init(row: StorageRow) {
        name = row["name"]?.stringValue ?? ""
        urlRule = row["urlRule"]?.stringValue ?? ""
        showRule = row["showRule"]?.stringValue ?? ""
        enabled = row["enabled"]?.boolValue ?? true
        sortNumber = row["sortNumber"]?.intValue ?? 0
    }

    public var row: StorageRow {
        [
            "name": .text(name),
            "urlRule": .text(urlRule),
            "showRule": .text(showRule),
            "enabled": .integer(enabled ? 1 : 0),
            "sortNumber": .integer(sortNumber)
        ]
    }
}

/// A keyboard assist — upstream `data/entities/KeyboardAssist.kt`.
public struct KeyboardAssist: Equatable {
    public var type: Int64
    public var key: String
    public var value: String
    public var serialNo: Int64

    public init(type: Int64, key: String, value: String, serialNo: Int64 = 0) {
        self.type = type
        self.key = key
        self.value = value
        self.serialNo = serialNo
    }

    public init(row: StorageRow) {
        type = row["type"]?.intValue ?? 0
        key = row["key"]?.stringValue ?? ""
        value = row["value"]?.stringValue ?? ""
        serialNo = row["serialNo"]?.intValue ?? 0
    }

    public var row: StorageRow {
        [
            "type": .integer(type),
            "key": .text(key),
            "value": .text(value),
            "serialNo": .integer(serialNo)
        ]
    }
}

/// A synchronisation server — upstream `data/entities/Server.kt`.
public struct Server: Equatable, Identifiable {
    /// The upstream server kinds.
    public enum Kind {
        public static let webDav = "webDav"
    }

    public var id: Int64
    public var name: String
    public var type: String
    public var config: String?
    public var sortNumber: Int64

    public init(
        id: Int64,
        name: String,
        type: String = Kind.webDav,
        config: String? = nil,
        sortNumber: Int64 = 0
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.config = config
        self.sortNumber = sortNumber
    }

    public init(row: StorageRow) {
        id = row["id"]?.intValue ?? 0
        name = row["name"]?.stringValue ?? ""
        type = row["type"]?.stringValue ?? Kind.webDav
        config = row["config"]?.stringValue
        sortNumber = row["sortNumber"]?.intValue ?? 0
    }

    public var row: StorageRow {
        [
            "id": .integer(id),
            "name": .text(name),
            "type": .text(type),
            "config": config.map { StorageValue.text($0) } ?? .null,
            "sortNumber": .integer(sortNumber)
        ]
    }
}

/// An RSS source — upstream `data/entities/RssSource.kt`.
public struct RssSource: Equatable {
    public var sourceUrl: String
    public var sourceName: String
    public var sourceIcon: String
    public var sourceGroup: String?
    public var sourceComment: String?
    public var enabled: Bool
    public var variableComment: String?
    public var jsLib: String?
    public var enabledCookieJar: Bool
    public var concurrentRate: String?
    public var header: String?
    public var loginUrl: String?
    public var loginUi: String?
    public var loginCheckJs: String?
    public var coverDecodeJs: String?
    public var sortUrl: String?
    public var singleUrl: Bool
    public var articleStyle: Int64
    public var ruleArticles: String?
    public var ruleNextPage: String?
    public var ruleTitle: String?
    public var rulePubDate: String?
    public var ruleDescription: String?
    public var ruleImage: String?
    public var ruleLink: String?
    public var ruleContent: String?
    public var contentWhitelist: String?
    public var contentBlacklist: String?
    public var shouldOverrideUrlLoading: String?
    public var style: String?
    public var enableJs: Bool
    public var loadWithBaseUrl: Bool
    public var injectJs: String?
    public var lastUpdateTime: Int64
    public var customOrder: Int64

    public init(
        sourceUrl: String,
        sourceName: String = "",
        sourceIcon: String = "",
        sourceGroup: String? = nil,
        sourceComment: String? = nil,
        enabled: Bool = true,
        variableComment: String? = nil,
        jsLib: String? = nil,
        enabledCookieJar: Bool = false,
        concurrentRate: String? = nil,
        header: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        loginCheckJs: String? = nil,
        coverDecodeJs: String? = nil,
        sortUrl: String? = nil,
        singleUrl: Bool = false,
        articleStyle: Int64 = 0,
        ruleArticles: String? = nil,
        ruleNextPage: String? = nil,
        ruleTitle: String? = nil,
        rulePubDate: String? = nil,
        ruleDescription: String? = nil,
        ruleImage: String? = nil,
        ruleLink: String? = nil,
        ruleContent: String? = nil,
        contentWhitelist: String? = nil,
        contentBlacklist: String? = nil,
        shouldOverrideUrlLoading: String? = nil,
        style: String? = nil,
        enableJs: Bool = false,
        loadWithBaseUrl: Bool = true,
        injectJs: String? = nil,
        lastUpdateTime: Int64 = 0,
        customOrder: Int64 = 0
    ) {
        self.sourceUrl = sourceUrl
        self.sourceName = sourceName
        self.sourceIcon = sourceIcon
        self.sourceGroup = sourceGroup
        self.sourceComment = sourceComment
        self.enabled = enabled
        self.variableComment = variableComment
        self.jsLib = jsLib
        self.enabledCookieJar = enabledCookieJar
        self.concurrentRate = concurrentRate
        self.header = header
        self.loginUrl = loginUrl
        self.loginUi = loginUi
        self.loginCheckJs = loginCheckJs
        self.coverDecodeJs = coverDecodeJs
        self.sortUrl = sortUrl
        self.singleUrl = singleUrl
        self.articleStyle = articleStyle
        self.ruleArticles = ruleArticles
        self.ruleNextPage = ruleNextPage
        self.ruleTitle = ruleTitle
        self.rulePubDate = rulePubDate
        self.ruleDescription = ruleDescription
        self.ruleImage = ruleImage
        self.ruleLink = ruleLink
        self.ruleContent = ruleContent
        self.contentWhitelist = contentWhitelist
        self.contentBlacklist = contentBlacklist
        self.shouldOverrideUrlLoading = shouldOverrideUrlLoading
        self.style = style
        self.enableJs = enableJs
        self.loadWithBaseUrl = loadWithBaseUrl
        self.injectJs = injectJs
        self.lastUpdateTime = lastUpdateTime
        self.customOrder = customOrder
    }

    public init(row: StorageRow) {
        sourceUrl = row["sourceUrl"]?.stringValue ?? ""
        sourceName = row["sourceName"]?.stringValue ?? ""
        sourceIcon = row["sourceIcon"]?.stringValue ?? ""
        sourceGroup = row["sourceGroup"]?.stringValue
        sourceComment = row["sourceComment"]?.stringValue
        enabled = row["enabled"]?.boolValue ?? true
        variableComment = row["variableComment"]?.stringValue
        jsLib = row["jsLib"]?.stringValue
        enabledCookieJar = row["enabledCookieJar"]?.boolValue ?? false
        concurrentRate = row["concurrentRate"]?.stringValue
        header = row["header"]?.stringValue
        loginUrl = row["loginUrl"]?.stringValue
        loginUi = row["loginUi"]?.stringValue
        loginCheckJs = row["loginCheckJs"]?.stringValue
        coverDecodeJs = row["coverDecodeJs"]?.stringValue
        sortUrl = row["sortUrl"]?.stringValue
        singleUrl = row["singleUrl"]?.boolValue ?? false
        articleStyle = row["articleStyle"]?.intValue ?? 0
        ruleArticles = row["ruleArticles"]?.stringValue
        ruleNextPage = row["ruleNextPage"]?.stringValue
        ruleTitle = row["ruleTitle"]?.stringValue
        rulePubDate = row["rulePubDate"]?.stringValue
        ruleDescription = row["ruleDescription"]?.stringValue
        ruleImage = row["ruleImage"]?.stringValue
        ruleLink = row["ruleLink"]?.stringValue
        ruleContent = row["ruleContent"]?.stringValue
        contentWhitelist = row["contentWhitelist"]?.stringValue
        contentBlacklist = row["contentBlacklist"]?.stringValue
        shouldOverrideUrlLoading = row["shouldOverrideUrlLoading"]?.stringValue
        style = row["style"]?.stringValue
        enableJs = row["enableJs"]?.boolValue ?? false
        loadWithBaseUrl = row["loadWithBaseUrl"]?.boolValue ?? true
        injectJs = row["injectJs"]?.stringValue
        lastUpdateTime = row["lastUpdateTime"]?.intValue ?? 0
        customOrder = row["customOrder"]?.intValue ?? 0
    }

    public var row: StorageRow {
        [
            "sourceUrl": .text(sourceUrl),
            "sourceName": .text(sourceName),
            "sourceIcon": .text(sourceIcon),
            "sourceGroup": sourceGroup.map { StorageValue.text($0) } ?? .null,
            "sourceComment": sourceComment.map { StorageValue.text($0) } ?? .null,
            "enabled": .integer(enabled ? 1 : 0),
            "variableComment": variableComment.map { StorageValue.text($0) } ?? .null,
            "jsLib": jsLib.map { StorageValue.text($0) } ?? .null,
            "enabledCookieJar": .integer(enabledCookieJar ? 1 : 0),
            "concurrentRate": concurrentRate.map { StorageValue.text($0) } ?? .null,
            "header": header.map { StorageValue.text($0) } ?? .null,
            "loginUrl": loginUrl.map { StorageValue.text($0) } ?? .null,
            "loginUi": loginUi.map { StorageValue.text($0) } ?? .null,
            "loginCheckJs": loginCheckJs.map { StorageValue.text($0) } ?? .null,
            "coverDecodeJs": coverDecodeJs.map { StorageValue.text($0) } ?? .null,
            "sortUrl": sortUrl.map { StorageValue.text($0) } ?? .null,
            "singleUrl": .integer(singleUrl ? 1 : 0),
            "articleStyle": .integer(articleStyle),
            "ruleArticles": ruleArticles.map { StorageValue.text($0) } ?? .null,
            "ruleNextPage": ruleNextPage.map { StorageValue.text($0) } ?? .null,
            "ruleTitle": ruleTitle.map { StorageValue.text($0) } ?? .null,
            "rulePubDate": rulePubDate.map { StorageValue.text($0) } ?? .null,
            "ruleDescription": ruleDescription.map { StorageValue.text($0) } ?? .null,
            "ruleImage": ruleImage.map { StorageValue.text($0) } ?? .null,
            "ruleLink": ruleLink.map { StorageValue.text($0) } ?? .null,
            "ruleContent": ruleContent.map { StorageValue.text($0) } ?? .null,
            "contentWhitelist": contentWhitelist.map { StorageValue.text($0) } ?? .null,
            "contentBlacklist": contentBlacklist.map { StorageValue.text($0) } ?? .null,
            "shouldOverrideUrlLoading": shouldOverrideUrlLoading.map { StorageValue.text($0) } ?? .null,
            "style": style.map { StorageValue.text($0) } ?? .null,
            "enableJs": .integer(enableJs ? 1 : 0),
            "loadWithBaseUrl": .integer(loadWithBaseUrl ? 1 : 0),
            "injectJs": injectJs.map { StorageValue.text($0) } ?? .null,
            "lastUpdateTime": .integer(lastUpdateTime),
            "customOrder": .integer(customOrder)
        ]
    }
}

extension RssSource: Identifiable {
    /// The identity of an RSS source — its address.
    public var id: String { sourceUrl }
}

/// An RSS article — upstream `data/entities/RssArticle.kt`.
public struct RssArticle: Equatable {
    public var origin: String
    public var sort: String
    public var title: String
    public var order: Int64
    public var link: String
    public var pubDate: String?
    public var description: String?
    public var content: String?
    public var image: String?
    public var group: String
    public var read: Bool
    public var variable: String?

    public init(
        origin: String,
        sort: String,
        title: String,
        link: String,
        order: Int64 = 0,
        pubDate: String? = nil,
        description: String? = nil,
        content: String? = nil,
        image: String? = nil,
        group: String = "",
        read: Bool = false,
        variable: String? = nil
    ) {
        self.origin = origin
        self.sort = sort
        self.title = title
        self.link = link
        self.order = order
        self.pubDate = pubDate
        self.description = description
        self.content = content
        self.image = image
        self.group = group
        self.read = read
        self.variable = variable
    }

    public init(row: StorageRow) {
        origin = row["origin"]?.stringValue ?? ""
        sort = row["sort"]?.stringValue ?? ""
        title = row["title"]?.stringValue ?? ""
        order = row["order"]?.intValue ?? 0
        link = row["link"]?.stringValue ?? ""
        pubDate = row["pubDate"]?.stringValue
        description = row["description"]?.stringValue
        content = row["content"]?.stringValue
        image = row["image"]?.stringValue
        group = row["group"]?.stringValue ?? ""
        read = row["read"]?.boolValue ?? false
        variable = row["variable"]?.stringValue
    }

    public var row: StorageRow {
        [
            "origin": .text(origin),
            "sort": .text(sort),
            "title": .text(title),
            "order": .integer(order),
            "link": .text(link),
            "pubDate": pubDate.map { StorageValue.text($0) } ?? .null,
            "description": description.map { StorageValue.text($0) } ?? .null,
            "content": content.map { StorageValue.text($0) } ?? .null,
            "image": image.map { StorageValue.text($0) } ?? .null,
            "group": .text(group),
            "read": .integer(read ? 1 : 0),
            "variable": variable.map { StorageValue.text($0) } ?? .null
        ]
    }
}

/// The read state of an RSS article — upstream `RssReadRecord.kt`.
public struct RssReadRecord: Equatable {
    public var record: String
    public var title: String?
    public var readTime: Int64?
    public var read: Bool

    public init(record: String, title: String? = nil, readTime: Int64? = nil, read: Bool = false) {
        self.record = record
        self.title = title
        self.readTime = readTime
        self.read = read
    }

    public init(row: StorageRow) {
        record = row["record"]?.stringValue ?? ""
        title = row["title"]?.stringValue
        readTime = row["readTime"]?.intValue
        read = row["read"]?.boolValue ?? false
    }

    public var row: StorageRow {
        [
            "record": .text(record),
            "title": title.map { StorageValue.text($0) } ?? .null,
            "readTime": readTime.map { StorageValue.integer($0) } ?? .null,
            "read": .integer(read ? 1 : 0)
        ]
    }
}

/// A starred RSS article — upstream `RssStar.kt`.
public struct RssStar: Equatable {
    public var origin: String
    public var sort: String
    public var title: String
    public var starTime: Int64
    public var link: String
    public var pubDate: String?
    public var description: String?
    public var content: String?
    public var image: String?
    public var group: String
    public var variable: String?

    public init(
        origin: String,
        sort: String,
        title: String,
        link: String,
        starTime: Int64 = 0,
        pubDate: String? = nil,
        description: String? = nil,
        content: String? = nil,
        image: String? = nil,
        group: String = "",
        variable: String? = nil
    ) {
        self.origin = origin
        self.sort = sort
        self.title = title
        self.link = link
        self.starTime = starTime
        self.pubDate = pubDate
        self.description = description
        self.content = content
        self.image = image
        self.group = group
        self.variable = variable
    }

    public init(row: StorageRow) {
        origin = row["origin"]?.stringValue ?? ""
        sort = row["sort"]?.stringValue ?? ""
        title = row["title"]?.stringValue ?? ""
        starTime = row["starTime"]?.intValue ?? 0
        link = row["link"]?.stringValue ?? ""
        pubDate = row["pubDate"]?.stringValue
        description = row["description"]?.stringValue
        content = row["content"]?.stringValue
        image = row["image"]?.stringValue
        group = row["group"]?.stringValue ?? ""
        variable = row["variable"]?.stringValue
    }

    public var row: StorageRow {
        [
            "origin": .text(origin),
            "sort": .text(sort),
            "title": .text(title),
            "starTime": .integer(starTime),
            "link": .text(link),
            "pubDate": pubDate.map { StorageValue.text($0) } ?? .null,
            "description": description.map { StorageValue.text($0) } ?? .null,
            "content": content.map { StorageValue.text($0) } ?? .null,
            "image": image.map { StorageValue.text($0) } ?? .null,
            "group": .text(group),
            "variable": variable.map { StorageValue.text($0) } ?? .null
        ]
    }
}

// MARK: - Source variables

extension RssSource {
    /// The variables an RSS source has written — upstream `BaseSource.putVariable/getVariable`
    /// stores them in the cache manager under `v_<key>_<name>`, keyed by the source key.
    /// The box writes through to that store so the variables survive the evaluation.
    public var variableBox: RuleDataBox {
        let sourceKey = key
        return RuleDataBox(
            json: BookSourceVariables.sourceVariables(sourceKey),
            sourceKey: sourceKey,
            sourceName: sourceName
        ) { variables in
            BookSourceVariables.setVariables(variables, for: sourceKey)
        }
    }
}