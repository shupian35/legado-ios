//
//  ImportOldData.swift
//  LegadoCore
//
//  Port of `app/src/main/java/io/legado/app/help/storage/ImportOldData.kt`.
//
//  The upstream can import the data of the old Legado (the "阅读 2.x" format):
//  a folder with `myBookShelf.json`, `myBookSource.json` and
//  `myBookReplaceRule.json`.  The rules of that format use another syntax
//  (`#` for a replacement, `|` for a separator, `&` for a reference and the
//  `searchKey` / `searchPage` placeholders), so they have to be converted
//  before they can be used by the current rule engine.
//
//  The upstream's action key `import_old` (`ui/config/BackupConfigFragment.kt:238`)
//  opens the file picker of that import.
//

import Foundation

// MARK: - The errors

/// The errors of the old-data import.
public enum ImportOldDataError: Error, Equatable {
    /// The JSON is broken.
    case brokenJson
    /// The JSON is valid but it does not have the expected shape.
    case wrongFormat
}

// MARK: - The importer

/// The importer of the old Legado data.
public enum ImportOldData {

    // MARK: The bookshelf

    /// Imports the old bookshelf — upstream `importOldBookshelf`.
    ///
    /// - Parameters:
    ///   - json: the content of `myBookShelf.json`.
    ///   - existingBookUrls: the books that are already on the shelf; they
    ///     are skipped (upstream `appDb.bookDao.allBookUrls`).
    /// - Returns: the imported books.
    public static func importOldBooks(
        _ json: String,
        existingBookUrls: Set<String> = []
    ) throws -> [Book] {
        let root = try parse(json)
        let items: [JSONValue]
        switch root {
        case .array(let values):
            items = values
        case .object:
            items = [root]
        default:
            throw ImportOldDataError.wrongFormat
        }
        var books: [Book] = []
        for item in items {
            guard let book = fromOldBook(item, existingBookUrls: existingBookUrls) else { continue }
            books.append(book)
        }
        return books
    }

    /// Converts one old book — upstream `fromOldBooks`.
    private static func fromOldBook(
        _ item: JSONValue,
        existingBookUrls: Set<String>
    ) -> Book? {
        let bookUrl = readString("$.noteUrl", in: item) ?? ""
        if bookUrl.isEmpty { return nil }
        let name = readString("$.bookInfoBean.name", in: item) ?? ""
        if existingBookUrls.contains(bookUrl) { return nil }
        let origin = readString("$.tag", in: item) ?? ""
        let originName = readString("$.bookInfoBean.origin", in: item) ?? ""
        let author = readString("$.bookInfoBean.author", in: item) ?? ""
        let isLocal = origin == BookType.localTag
        let isAudio = readString("$.bookInfoBean.bookSourceType", in: item) == "AUDIO"
        // The upstream: `book.type = local or if (isAudio) audio else text`.
        var type: Int64 = isLocal ? BookType.local : 0
        type = type | (isAudio ? BookType.audio : BookType.text)
        let tocUrl = readString("$.bookInfoBean.chapterUrl", in: item) ?? bookUrl
        let coverUrl = readString("$.bookInfoBean.coverUrl", in: item)
        let customCoverUrl = readString("$.customCoverPath", in: item)
        let lastCheckTime = readLong("$.bookInfoBean.finalRefreshData", in: item) ?? 0
        let canUpdate = readBool("$.allowUpdate", in: item) == true
        let totalChapterNum = readInt("$.chapterListSize", in: item) ?? 0
        let durChapterIndex = readInt("$.durChapter", in: item) ?? 0
        let durChapterTitle = readString("$.durChapterName", in: item)
        let durChapterPos = readInt("$.durChapterPage", in: item) ?? 0
        let durChapterTime = readLong("$.finalDate", in: item) ?? 0
        let intro = readString("$.bookInfoBean.introduce", in: item)
        let latestChapterTitle = readString("$.lastChapterName", in: item)
        let lastCheckCount = readInt("$.newChapters", in: item) ?? 0
        let order = readInt("$.serialNumber", in: item) ?? 0
        let variable = readString("$.variable", in: item)
        var book = Book(
            bookUrl: bookUrl,
            tocUrl: tocUrl,
            origin: origin,
            originName: originName,
            name: name,
            author: author,
            coverUrl: coverUrl,
            customCoverUrl: customCoverUrl,
            intro: intro,
            type: type,
            latestChapterTitle: latestChapterTitle,
            lastCheckTime: lastCheckTime,
            lastCheckCount: lastCheckCount,
            totalChapterNum: totalChapterNum,
            durChapterTitle: durChapterTitle,
            durChapterIndex: durChapterIndex,
            durChapterPos: durChapterPos,
            durChapterTime: durChapterTime,
            canUpdate: canUpdate,
            order: order,
            variable: variable
        )
        book.useReplaceRule = readBool("$.useReplaceRule", in: item) == true
        return book
    }

    // MARK: The sources

    /// Imports the old sources — upstream `importOldSource`.
    public static func importOldSources(_ json: String) throws -> [BookSource] {
        let root = try parse(json)
        let items: [JSONValue]
        switch root {
        case .array(let values):
            items = values
        case .object:
            items = [root]
        default:
            throw ImportOldDataError.wrongFormat
        }
        var sources: [BookSource] = []
        for item in items {
            // The upstream throws "wrong format" when the URL is missing.
            if (readString("bookSourceUrl", in: item) ?? "").isEmpty {
                throw ImportOldDataError.wrongFormat
            }
            sources.append(fromOldBookSource(item))
        }
        return sources
    }

    /// Converts one old source — upstream `fromOldBookSource`.
    public static func fromOldBookSource(_ item: JSONValue) -> BookSource {
        let bookSourceUrl = readString("bookSourceUrl", in: item) ?? ""
        let bookSourceName = readString("bookSourceName", in: item) ?? ""
        let bookSourceGroup = readString("bookSourceGroup", in: item)
        let loginUrl = readString("loginUrl", in: item)
        let loginUi = readString("loginUi", in: item)
        let loginCheckJs = readString("loginCheckJs", in: item)
        let coverDecodeJs = readString("coverDecodeJs", in: item)
        let bookSourceComment = readString("bookSourceComment", in: item) ?? ""
        let bookUrlPattern = readString("ruleBookUrlPattern", in: item)
        let customOrder = readInt("serialNumber", in: item) ?? 0
        let header = userAgentToHeader(readString("httpUserAgent", in: item))
        let searchUrl = toNewUrl(readString("ruleSearchUrl", in: item))
        let exploreUrl = toNewUrls(readString("ruleFindUrl", in: item))
        let bookSourceType: Int64 = readString("bookSourceType", in: item) == "AUDIO"
            ? BookSourceType.audio
            : BookSourceType.default
        let enabled = readBool("enable", in: item) ?? true
        var source = BookSource(
            bookSourceUrl: bookSourceUrl,
            bookSourceName: bookSourceName,
            bookSourceGroup: bookSourceGroup,
            bookSourceType: bookSourceType,
            bookUrlPattern: bookUrlPattern,
            customOrder: customOrder,
            enabled: enabled,
            enabledExplore: !(exploreUrl ?? "").isEmpty,
            header: header,
            loginUrl: loginUrl,
            loginUi: loginUi,
            loginCheckJs: loginCheckJs,
            coverDecodeJs: coverDecodeJs,
            bookSourceComment: bookSourceComment,
            exploreUrl: exploreUrl,
            searchUrl: searchUrl
        )
        source.ruleSearch = encode(SearchRule(
            bookList: toNewRule(readString("ruleSearchList", in: item)),
            name: toNewRule(readString("ruleSearchName", in: item)),
            author: toNewRule(readString("ruleSearchAuthor", in: item)),
            intro: toNewRule(readString("ruleSearchIntroduce", in: item)),
            kind: toNewRule(readString("ruleSearchKind", in: item)),
            lastChapter: toNewRule(readString("ruleSearchLastChapter", in: item)),
            bookUrl: toNewRule(readString("ruleSearchNoteUrl", in: item)),
            coverUrl: toNewRule(readString("ruleSearchCoverUrl", in: item))
        ))
        source.ruleExplore = encode(ExploreRule(
            bookList: toNewRule(readString("ruleFindList", in: item)),
            name: toNewRule(readString("ruleFindName", in: item)),
            author: toNewRule(readString("ruleFindAuthor", in: item)),
            intro: toNewRule(readString("ruleFindIntroduce", in: item)),
            kind: toNewRule(readString("ruleFindKind", in: item)),
            lastChapter: toNewRule(readString("ruleFindLastChapter", in: item)),
            bookUrl: toNewRule(readString("ruleFindNoteUrl", in: item)),
            coverUrl: toNewRule(readString("ruleFindCoverUrl", in: item))
        ))
        source.ruleBookInfo = encode(BookInfoRule(
            initRule: toNewRule(readString("ruleBookInfoInit", in: item)),
            name: toNewRule(readString("ruleBookName", in: item)),
            author: toNewRule(readString("ruleBookAuthor", in: item)),
            intro: toNewRule(readString("ruleIntroduce", in: item)),
            kind: toNewRule(readString("ruleBookKind", in: item)),
            lastChapter: toNewRule(readString("ruleBookLastChapter", in: item)),
            coverUrl: toNewRule(readString("ruleCoverUrl", in: item)),
            tocUrl: toNewRule(readString("ruleChapterUrl", in: item))
        ))
        source.ruleToc = encode(TocRule(
            chapterList: toNewRule(readString("ruleChapterList", in: item)),
            chapterName: toNewRule(readString("ruleChapterName", in: item)),
            chapterUrl: toNewRule(readString("ruleContentUrl", in: item)),
            nextTocUrl: toNewRule(readString("ruleChapterUrlNext", in: item))
        ))
        var content = toNewRule(readString("ruleBookContent", in: item)) ?? ""
        if content.hasPrefix("$"), !content.hasPrefix("$.") {
            content = String(content.dropFirst())
        }
        source.ruleContent = encode(ContentRule(
            content: content,
            nextContentUrl: toNewRule(readString("ruleContentUrlNext", in: item)),
            replaceRegex: toNewRule(readString("ruleBookContentReplace", in: item))
        ))
        return source
    }

    // MARK: The replace rules

    /// Imports the old replace rules — upstream `importOldReplaceRule`.
    public static func importOldReplaceRules(_ json: String) throws -> [ReplaceRule] {
        do {
            return try ReplaceRuleEngine.jsonToReplaceRules(json)
        } catch {
            throw ImportOldDataError.brokenJson
        }
    }

    // MARK: The rule conversion

    /// Converts an old rule — upstream `toNewRule`.
    ///
    /// The old syntax uses `#` for a replacement, `|` for a separator and `&`
    /// for a reference; the current one uses `##`, `||` and `&&`.  A leading
    /// `-` marks a reversed rule and a leading `+` an "all in one" rule.
    public static func toNewRule(_ oldRule: String?) -> String? {
        guard let oldRule, !oldRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        var newRule = oldRule
        var reverse = false
        var allInOne = false
        if newRule.hasPrefix("-") {
            reverse = true
            newRule = String(newRule.dropFirst())
        }
        if newRule.hasPrefix("+") {
            allInOne = true
            newRule = String(newRule.dropFirst())
        }
        let lowercased = newRule.lowercased()
        let isNewSyntax = lowercased.hasPrefix("@css:")
            || lowercased.hasPrefix("@xpath:")
            || newRule.hasPrefix("//")
            || newRule.hasPrefix("##")
            || newRule.hasPrefix(":")
            || lowercased.contains("@js:")
            || lowercased.contains("<js>")
        if !isNewSyntax {
            if newRule.contains("#"), !newRule.contains("##") {
                newRule = oldRule.replacingOccurrences(of: "#", with: "##")
            }
            if newRule.contains("|"), !newRule.contains("||") {
                if newRule.contains("##") {
                    let list = newRule.components(separatedBy: "##")
                    if let first = list.first, first.contains("|") {
                        newRule = list[0].replacingOccurrences(of: "|", with: "||")
                        for item in list.dropFirst() {
                            newRule += "##" + item
                        }
                    }
                } else {
                    newRule = newRule.replacingOccurrences(of: "|", with: "||")
                }
            }
            if newRule.contains("&"),
                !newRule.contains("&&"),
                !newRule.contains("http"),
                !newRule.hasPrefix("/") {
                newRule = newRule.replacingOccurrences(of: "&", with: "&&")
            }
        }
        if allInOne { newRule = "+" + newRule }
        if reverse { newRule = "-" + newRule }
        return newRule
    }

    /// Converts a list of old URLs — upstream `toNewUrls`.
    public static func toNewUrls(_ oldUrls: String?) -> String? {
        guard let oldUrls, !oldUrls.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        if oldUrls.hasPrefix("@js:") || oldUrls.hasPrefix("<js>") {
            return oldUrls
        }
        if !oldUrls.contains("\n"), !oldUrls.contains("&&") {
            return toNewUrl(oldUrls)
        }
        // The upstream splits on the regular expression `(&&|\r?\n)+`.
        let list = splitOldUrls(oldUrls)
        return list
            .compactMap { toNewUrl($0).map { replaceRegex("\n\\s*", with: "", in: $0) } }
            .joined(separator: "\n")
    }

    /// Replaces the matches of a regular expression.
    ///
    /// `String.replacingOccurrences(of:with:options:.regularExpression)` is
    /// broken on Linux (it silently empties the string), so the replacement
    /// uses `NSRegularExpression` directly.
    private static func replaceRegex(_ pattern: String, with template: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    /// Splits the old URL list on `&&` and the new lines.
    private static func splitOldUrls(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "&", text.index(after: index) < text.endIndex,
                text[text.index(after: index)] == "&" {
                result.append(current)
                current = ""
                index = text.index(index, offsetBy: 2)
                continue
            }
            if character == "\n" || character == "\r" {
                result.append(current)
                current = ""
                index = text.index(after: index)
                // a "\r\n" is one separator
                if character == "\r", index < text.endIndex, text[index] == "\n" {
                    index = text.index(after: index)
                }
                continue
            }
            current.append(character)
            index = text.index(after: index)
        }
        result.append(current)
        return result.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Converts one old URL — upstream `toNewUrl`.
    public static func toNewUrl(_ oldUrl: String?) -> String? {
        guard let oldUrl, !oldUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        var url = oldUrl
        if oldUrl.lowercased().hasPrefix("<js>") {
            url = url
                .replacingOccurrences(of: "=searchKey", with: "={{key}}")
                .replacingOccurrences(of: "=searchPage", with: "={{page}}")
            return url
        }
        var options: [String: String] = [:]
        if let header = firstHeader(in: url) {
            url = url.replacingOccurrences(of: header, with: "")
            // The upstream keeps the braces: `header.substring(8)` drops the
            // "@Header:" only, so the value is a JSON object as a string.
            options["headers"] = String(header.dropFirst("@Header:".count))
        }
        var urlList = url.components(separatedBy: "|")
        url = urlList[0]
        if urlList.count > 1 {
            let charset = urlList[1].components(separatedBy: "=")
            if charset.count > 1 {
                options["charset"] = charset[1]
            }
        }
        let jsList = javascriptBlocks(in: url)
        for (index, block) in jsList.enumerated() {
            url = url.replacingOccurrences(of: block, with: "$\(index)")
        }
        url = url.replacingOccurrences(of: "{", with: "<")
        url = url.replacingOccurrences(of: "}", with: ">")
        url = url.replacingOccurrences(of: "searchKey", with: "{{key}}")
        url = replaceRegex("<searchPage([-+]1)>", with: "{{page$1}}", in: url)
        url = replaceRegex("searchPage([-+]1)", with: "{{page$1}}", in: url)
        url = url.replacingOccurrences(of: "searchPage", with: "{{page}}")
        for (index, block) in jsList.enumerated() {
            url = url.replacingOccurrences(
                of: "$\(index)",
                with: block
                    .replacingOccurrences(of: "searchKey", with: "key")
                    .replacingOccurrences(of: "searchPage", with: "page")
            )
        }
        urlList = url.components(separatedBy: "@")
        url = urlList[0]
        if urlList.count > 1 {
            options["method"] = "POST"
            options["body"] = urlList[1]
        }
        if !options.isEmpty {
            url += "," + encodeOptions(options)
        }
        return url
    }

    /// The `@Header:{...}` block of an old URL.
    private static func firstHeader(in url: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "@Header:\\{.+?\\}", options: [.caseInsensitive]) else {
            return nil
        }
        let ns = url as NSString
        guard let match = regex.firstMatch(in: url, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ns.substring(with: match.range)
    }

    /// The `{{...}}` blocks of an old URL.
    private static func javascriptBlocks(in url: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "\\{\\{.+?\\}\\}", options: [.caseInsensitive]) else {
            return []
        }
        let ns = url as NSString
        let range = NSRange(location: 0, length: ns.length)
        return regex.matches(in: url, range: range).map { ns.substring(with: $0.range) }
    }

    /// The header of the old user agent — upstream `uaToHeader`.
    private static func userAgentToHeader(_ userAgent: String?) -> String? {
        guard let userAgent, !userAgent.isEmpty else { return nil }
        return "{\"User-Agent\":\"\(userAgent)\"}"
    }

    // MARK: The helpers

    /// Parses a JSON document.
    private static func parse(_ json: String) throws -> JSONValue {
        guard let value = try? JSONValue.parse(json) else {
            throw ImportOldDataError.brokenJson
        }
        return value
    }

    /// Reads a string — upstream `readString`.
    private static func readString(_ path: String, in root: JSONValue) -> String? {
        guard let value = JSONPath.read(path, in: root) else { return nil }
        if case .string(let text) = value { return text }
        return nil
    }

    /// Reads a long — upstream `readLong`.
    private static func readLong(_ path: String, in root: JSONValue) -> Int64? {
        guard let value = JSONPath.read(path, in: root) else { return nil }
        return value.intValue
    }

    /// Reads an int — upstream `readInt`.
    private static func readInt(_ path: String, in root: JSONValue) -> Int64? {
        readLong(path, in: root)
    }

    /// Reads a boolean — upstream `readBool`.
    private static func readBool(_ path: String, in root: JSONValue) -> Bool? {
        guard let value = JSONPath.read(path, in: root) else { return nil }
        return value.boolValue
    }

    /// Encodes a rule entity as the JSON string the database stores.
    private static func encode<T: Encodable>(_ value: T) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Encodes the option block of an old URL.
    private static func encodeOptions(_ options: [String: String]) -> String {
        var parts: [String] = []
        for key in options.keys.sorted() {
            guard let value = options[key] else { continue }
            parts.append("\"\(key)\":\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\"")
        }
        return "{" + parts.joined(separator: ",") + "}"
    }
}
