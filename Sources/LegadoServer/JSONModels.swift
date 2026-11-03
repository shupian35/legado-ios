import Foundation
import LegadoCore

/// JSON ↔ model adapters for the local API.
///
/// The Android app serialises entities with GSON, so the web frontend expects
/// the Kotlin property names. The port mirrors those names here rather than
/// exposing `StorageRow` keys — that keeps `modules/web` working unchanged.
enum JSONHelper {

    static func string(_ object: [String: JSONValue], _ key: String) -> String? {
        if case let .string(value)? = object[key] { return value }
        return nil
    }

    static func int(_ object: [String: JSONValue], _ key: String) -> Int64? {
        switch object[key] {
        case let .number(value)?: return Int64(value)
        case let .string(value)?: return Int64(value)
        case let .bool(value)?: return value ? 1 : 0
        default: return nil
        }
    }

    static func double(_ object: [String: JSONValue], _ key: String) -> Double? {
        switch object[key] {
        case let .number(value)?: return value
        case let .string(value)?: return Double(value)
        default: return nil
        }
    }

    static func bool(_ object: [String: JSONValue], _ key: String) -> Bool? {
        switch object[key] {
        case let .bool(value)?: return value
        case let .number(value)?: return value != 0
        case let .string(value)?: return value == "true" || value == "1"
        default: return nil
        }
    }
}

/// Encodes and decodes `Book` — upstream `data/entities/Book.kt`.
enum BookJSON {

    static func decode(_ json: JSONValue) -> Book? {
        guard case let .object(object) = json else { return nil }
        guard let bookUrl = JSONHelper.string(object, "bookUrl"), !bookUrl.isEmpty else { return nil }
        var book = Book(bookUrl: bookUrl)
        book.tocUrl = JSONHelper.string(object, "tocUrl") ?? book.tocUrl
        book.origin = JSONHelper.string(object, "origin") ?? book.origin
        book.originName = JSONHelper.string(object, "originName") ?? book.originName
        book.name = JSONHelper.string(object, "name") ?? book.name
        book.author = JSONHelper.string(object, "author") ?? book.author
        book.kind = JSONHelper.string(object, "kind")
        book.customTag = JSONHelper.string(object, "customTag")
        book.coverUrl = JSONHelper.string(object, "coverUrl")
        book.customCoverUrl = JSONHelper.string(object, "customCoverUrl")
        book.intro = JSONHelper.string(object, "intro")
        book.customIntro = JSONHelper.string(object, "customIntro")
        book.charset = JSONHelper.string(object, "charset")
        if let type = JSONHelper.int(object, "type") { book.type = type }
        if let group = JSONHelper.int(object, "group") { book.group = group }
        book.latestChapterTitle = JSONHelper.string(object, "latestChapterTitle")
        if let value = JSONHelper.int(object, "latestChapterTime") { book.latestChapterTime = value }
        if let value = JSONHelper.int(object, "lastCheckTime") { book.lastCheckTime = value }
        if let value = JSONHelper.int(object, "lastCheckCount") { book.lastCheckCount = value }
        if let value = JSONHelper.int(object, "totalChapterNum") { book.totalChapterNum = value }
        book.durChapterTitle = JSONHelper.string(object, "durChapterTitle")
        if let value = JSONHelper.int(object, "durChapterIndex") { book.durChapterIndex = value }
        if let value = JSONHelper.int(object, "durChapterPos") { book.durChapterPos = value }
        if let value = JSONHelper.int(object, "durChapterTime") { book.durChapterTime = value }
        book.wordCount = JSONHelper.string(object, "wordCount")
        if let value = JSONHelper.bool(object, "canUpdate") { book.canUpdate = value }
        if let value = JSONHelper.int(object, "order") { book.order = value }
        if let value = JSONHelper.int(object, "originOrder") { book.originOrder = value }
        book.variable = JSONHelper.string(object, "variable")
        book.readConfig = JSONHelper.string(object, "readConfig")
        if let value = JSONHelper.int(object, "syncTime") { book.syncTime = value }
        book.infoHtml = JSONHelper.string(object, "infoHtml")
        book.tocHtml = JSONHelper.string(object, "tocHtml")
        if let value = JSONHelper.bool(object, "reverseToc") { book.reverseToc = value }
        if case let .array(urls)? = object["downloadUrls"] {
            book.downloadUrls = urls.compactMap { value in
                if case let .string(text) = value { return text }
                return nil
            }
        }
        return book
    }
}

/// Encodes and decodes `BookSource` — upstream `data/entities/BookSource.kt`.
enum BookSourceJSON {

    static func encode(_ source: BookSource) -> JSONValue {
        var object: [String: JSONValue] = [:]
        object["bookSourceUrl"] = .string(source.bookSourceUrl)
        object["bookSourceName"] = .string(source.bookSourceName)
        object["bookSourceGroup"] = source.bookSourceGroup.map(JSONValue.string) ?? .null
        object["bookSourceType"] = .number(Double(source.bookSourceType))
        object["bookUrlPattern"] = source.bookUrlPattern.map(JSONValue.string) ?? .null
        object["customOrder"] = .number(Double(source.customOrder))
        object["enabled"] = .bool(source.enabled)
        object["enabledExplore"] = .bool(source.enabledExplore)
        object["jsLib"] = source.jsLib.map(JSONValue.string) ?? .null
        object["enabledCookieJar"] = .bool(source.enabledCookieJar)
        object["concurrentRate"] = source.concurrentRate.map(JSONValue.string) ?? .null
        object["header"] = source.header.map(JSONValue.string) ?? .null
        object["loginUrl"] = source.loginUrl.map(JSONValue.string) ?? .null
        object["loginUi"] = source.loginUi.map(JSONValue.string) ?? .null
        object["loginCheckJs"] = source.loginCheckJs.map(JSONValue.string) ?? .null
        object["coverDecodeJs"] = source.coverDecodeJs.map(JSONValue.string) ?? .null
        object["bookSourceComment"] = source.bookSourceComment.map(JSONValue.string) ?? .null
        object["variableComment"] = source.variableComment.map(JSONValue.string) ?? .null
        object["lastUpdateTime"] = .number(Double(source.lastUpdateTime))
        object["respondTime"] = .number(Double(source.respondTime))
        object["weight"] = .number(Double(source.weight))
        object["exploreUrl"] = source.exploreUrl.map(JSONValue.string) ?? .null
        object["exploreScreen"] = source.exploreScreen.map(JSONValue.string) ?? .null
        object["ruleExplore"] = source.ruleExplore.map(JSONValue.string) ?? .null
        object["searchUrl"] = source.searchUrl.map(JSONValue.string) ?? .null
        object["ruleSearch"] = source.ruleSearch.map(JSONValue.string) ?? .null
        object["ruleBookInfo"] = source.ruleBookInfo.map(JSONValue.string) ?? .null
        object["ruleToc"] = source.ruleToc.map(JSONValue.string) ?? .null
        object["ruleContent"] = source.ruleContent.map(JSONValue.string) ?? .null
        object["ruleReview"] = source.ruleReview.map(JSONValue.string) ?? .null
        return .object(object)
    }

    static func decode(_ json: JSONValue) -> BookSource? {
        guard case let .object(object) = json else { return nil }
        guard let url = JSONHelper.string(object, "bookSourceUrl"), !url.isEmpty else { return nil }
        var source = BookSource(
            bookSourceUrl: url,
            bookSourceName: JSONHelper.string(object, "bookSourceName") ?? ""
        )
        source.bookSourceGroup = JSONHelper.string(object, "bookSourceGroup")
        if let value = JSONHelper.int(object, "bookSourceType") { source.bookSourceType = value }
        source.bookUrlPattern = JSONHelper.string(object, "bookUrlPattern")
        if let value = JSONHelper.int(object, "customOrder") { source.customOrder = value }
        if let value = JSONHelper.bool(object, "enabled") { source.enabled = value }
        if let value = JSONHelper.bool(object, "enabledExplore") { source.enabledExplore = value }
        source.jsLib = JSONHelper.string(object, "jsLib")
        if let value = JSONHelper.bool(object, "enabledCookieJar") { source.enabledCookieJar = value }
        source.concurrentRate = JSONHelper.string(object, "concurrentRate")
        source.header = JSONHelper.string(object, "header")
        source.loginUrl = JSONHelper.string(object, "loginUrl")
        source.loginUi = JSONHelper.string(object, "loginUi")
        source.loginCheckJs = JSONHelper.string(object, "loginCheckJs")
        source.coverDecodeJs = JSONHelper.string(object, "coverDecodeJs")
        source.bookSourceComment = JSONHelper.string(object, "bookSourceComment")
        source.variableComment = JSONHelper.string(object, "variableComment")
        if let value = JSONHelper.int(object, "lastUpdateTime") { source.lastUpdateTime = value }
        if let value = JSONHelper.int(object, "respondTime") { source.respondTime = value }
        if let value = JSONHelper.int(object, "weight") { source.weight = value }
        source.exploreUrl = JSONHelper.string(object, "exploreUrl")
        source.exploreScreen = JSONHelper.string(object, "exploreScreen")
        source.ruleExplore = JSONHelper.string(object, "ruleExplore")
        source.searchUrl = JSONHelper.string(object, "searchUrl")
        source.ruleSearch = JSONHelper.string(object, "ruleSearch")
        source.ruleBookInfo = JSONHelper.string(object, "ruleBookInfo")
        source.ruleToc = JSONHelper.string(object, "ruleToc")
        source.ruleContent = JSONHelper.string(object, "ruleContent")
        source.ruleReview = JSONHelper.string(object, "ruleReview")
        return source
    }
}
