import Foundation
import LegadoCore

/// The remaining routes of the local API.
///
/// Upstream `web/HttpServer.kt:55-89` registers 26 routes; the first batch
/// lives in `LegadoAPI.routes()` and this file completes the set:
///
/// | Route | Upstream |
/// |---|---|
/// | `GET /refreshToc` | `BookController.refreshToc` (`api/controller/BookController.kt:122-154`) |
/// | `GET /cover` | `BookController.getCover` (`:69-97`) |
/// | `GET /image` | `BookController.getImg` (`:99-117`) |
/// | `GET /getReadConfig` | `BookController.getWebReadConfig` (`:318-324`) |
/// | `GET /getRssSource` | `RssSourceController.getSource` |
/// | `GET /getRssSources` | `RssSourceController.sources` |
/// | `POST /saveReadConfig` | `BookController.saveWebReadConfig` (`:307-316`) |
/// | `POST /saveRssSource` | `RssSourceController.saveSource` |
/// | `POST /saveRssSources` | `RssSourceController.saveSources` |
/// | `POST /deleteRssSources` | `RssSourceController.deleteSources` |
/// | `POST /saveReplaceRule` | `ReplaceRuleController.saveRule` |
/// | `POST /deleteReplaceRule` | `ReplaceRuleController.delete` |
/// | `POST /testReplaceRule` | `ReplaceRuleController.testRule` |
/// | `POST /addLocalBook` | `BookController.addLocalBook` (`:283-302`) |
extension LegadoAPI {

    /// The routes of this file — appended to `LegadoAPI.routes()`.
    public static func extraRoutes() -> [Route] {
        [
            // MARK: - The table of contents

            Route(method: "GET", path: "/refreshToc") { request, context in
                await handle(request, context) { request in
                    guard let url = request.query("url"), !url.isEmpty else {
                        return .apiError("参数url不能为空，请指定书籍地址")
                    }
                    guard let book = try context.store.book(url: url) else {
                        return .apiError("未在数据库找到对应书籍，请先添加")
                    }
                    guard let provider = context.chapterListProvider else {
                        return .apiError("未找到对应书源,请换源")
                    }
                    guard let source = try context.store.source(url: book.origin) else {
                        return .apiError("未找到对应书源,请换源")
                    }
                    let chapters = try await provider(source, book)
                    try context.store.deleteChapters(bookUrl: book.bookUrl)
                    try context.store.insert(chapters)
                    var updated = book
                    updated.totalChapterNum = Int64(chapters.count)
                    try context.store.update(updated)
                    return .api(JSONValue.array(chapters.map(chapterJSON)))
                }
            },

            // MARK: - The images

            Route(method: "GET", path: "/cover") { request, context in
                await handle(request, context) { request in
                    guard let path = request.query("path"), !path.isEmpty else {
                        return .apiError("获取封面失败")
                    }
                    guard let provider = context.imageProvider else {
                        return .apiError("获取图片失败")
                    }
                    guard let image = try await provider(path) else {
                        return .apiError("获取封面失败")
                    }
                    return .binary(image, contentType: "image/jpeg")
                }
            },
            Route(method: "GET", path: "/image") { request, context in
                await handle(request, context) { request in
                    guard let bookUrl = request.query("url"), !bookUrl.isEmpty else {
                        return .apiError("bookUrl为空")
                    }
                    guard let path = request.query("path"), !path.isEmpty else {
                        return .apiError("图片链接为空")
                    }
                    guard try context.store.book(url: bookUrl) != nil else {
                        return .apiError("bookUrl不对")
                    }
                    guard let provider = context.imageProvider else {
                        return .apiError("获取图片失败")
                    }
                    guard let image = try await provider(path) else {
                        return .apiError("获取图片失败")
                    }
                    return .binary(image, contentType: "image/jpeg")
                }
            },

            // MARK: - The web reading configuration

            Route(method: "GET", path: "/getReadConfig") { _, context in
                await handle(nil, context) { _ in
                    guard let config = try context.store.cache("webReadConfig", now: 0),
                          !config.isEmpty else {
                        return .apiError("没有配置")
                    }
                    return .api(JSONValue.string(config))
                }
            },
            Route(method: "POST", path: "/saveReadConfig") { request, context in
                await handle(request, context) { request in
                    let text = String(decoding: request.body, as: UTF8.self)
                    if text.isEmpty {
                        try context.store.putCache("webReadConfig", value: nil, deadline: 0)
                    } else {
                        try context.store.putCache("webReadConfig", value: text, deadline: 0)
                    }
                    return .api(JSONValue.string(""))
                }
            },

            // MARK: - The RSS sources

            Route(method: "GET", path: "/getRssSources") { _, context in
                await handle(nil, context) { _ in
                    let sources = try context.store.allRssSources()
                    return .api(JSONValue.array(sources.map(rssSourceJSON)))
                }
            },
            Route(method: "GET", path: "/getRssSource") { request, context in
                await handle(request, context) { request in
                    guard let url = request.query("url"), !url.isEmpty else {
                        return .apiError("参数url不能为空，请指定书源地址")
                    }
                    guard let source = try context.store.allRssSources()
                        .first(where: { $0.sourceUrl == url }) else {
                        return .apiError("未找到源，请检查源地址")
                    }
                    return .api(rssSourceJSON(source))
                }
            },
            Route(method: "POST", path: "/saveRssSource") { request, context in
                await handle(request, context) { request in
                    guard let source = try rssSourceFromBody(request.body) else {
                        return .apiError("转换源失败")
                    }
                    if source.sourceName.isEmpty || source.sourceUrl.isEmpty {
                        return .apiError("源名称和URL不能为空")
                    }
                    try context.store.insert(source)
                    return .api(JSONValue.string(""))
                }
            },
            Route(method: "POST", path: "/saveRssSources") { request, context in
                await handle(request, context) { request in
                    let sources = try rssSourcesFromBody(request.body)
                    guard !sources.isEmpty else { return .apiError("转换源失败") }
                    var saved: [RssSource] = []
                    for source in sources {
                        guard !source.sourceName.isEmpty, !source.sourceUrl.isEmpty else { continue }
                        try context.store.insert(source)
                        saved.append(source)
                    }
                    return .api(JSONValue.array(saved.map(rssSourceJSON)))
                }
            },
            Route(method: "POST", path: "/deleteRssSources") { request, context in
                await handle(request, context) { request in
                    let urls = try urlsFromBody(request.body)
                    try context.store.deleteRssSources(urls: urls)
                    return .api(JSONValue.string("已执行"))
                }
            },

            // MARK: - The replace rules

            Route(method: "POST", path: "/saveReplaceRule") { request, context in
                await handle(request, context) { request in
                    guard let rule = try replaceRuleFromBody(request.body) else {
                        return .apiError("格式不对")
                    }
                    try context.store.insert(rule)
                    return .api(JSONValue.string(""))
                }
            },
            Route(method: "POST", path: "/deleteReplaceRule") { request, context in
                await handle(request, context) { request in
                    guard let rule = try replaceRuleFromBody(request.body) else {
                        return .apiError("格式不对")
                    }
                    try context.store.deleteReplaceRule(id: rule.id)
                    return .api(JSONValue.string(""))
                }
            },
            Route(method: "POST", path: "/testReplaceRule") { request, context in
                await handle(request, context) { request in
                    guard let payload = try testPayloadFromBody(request.body) else {
                        return .apiError("格式不对")
                    }
                    guard !payload.rule.pattern.isEmpty else {
                        return .apiError("替换规则不能为空")
                    }
                    let content = applyReplaceRule(payload.rule, to: payload.text)
                    return .api(JSONValue.string(content))
                }
            },

            // MARK: - The local books

            Route(method: "POST", path: "/addLocalBook") { request, context in
                await handle(request, context) { request in
                    // The upstream upload page posts a multipart form with the
                    // `fileName` field and the `fileData` file part; a raw
                    // body with the name in the query string also works.
                    var fileName = request.query("fileName")
                    var payload = request.body
                    if let boundary = MultipartParser.boundary(in: request.header("Content-Type")) {
                        do {
                            let parts = try MultipartParser.parse(body: request.body, contentType: request.header("Content-Type"))
                            if let field = parts.first(where: { $0.name == "fileName" }) {
                                fileName = field.text
                            }
                            if let file = parts.first(where: { $0.name == "fileData" }) {
                                payload = file.data
                                if fileName == nil || fileName?.isEmpty == true {
                                    fileName = file.fileName
                                }
                            }
                        } catch {
                            return .apiError("保存书籍错误\n\(error)")
                        }
                    }
                    guard let fileName, !fileName.isEmpty else {
                        return .apiError("fileName 不能为空")
                    }
                    guard !payload.isEmpty else {
                        return .apiError("fileData 不能为空")
                    }
                    guard let importer = context.localBookImporter else {
                        return .apiError("保存书籍错误")
                    }
                    do {
                        let imported = try await importer(fileName, payload)
                        if !imported {
                            return .apiError("保存书籍错误")
                        }
                        return .api(JSONValue.bool(true))
                    } catch {
                        return .apiError("保存书籍错误\n\(error)")
                    }
                }
            }
        ]
    }

    // MARK: - The helpers

    /// The JSON of an RSS source.
    static func rssSourceJSON(_ source: RssSource) -> JSONValue {
        RssSourceJSONBridge.encode(source)
    }

    static func rssSourceFromBody(_ body: Data) throws -> RssSource? {
        try rssSourcesFromBody(body).first
    }

    static func rssSourcesFromBody(_ body: Data) throws -> [RssSource] {
        let text = String(decoding: body, as: UTF8.self)
        guard !text.isEmpty else { return [] }
        let json = try JSONValue.parse(text)
        let items: [JSONValue]
        if case let .array(values) = json {
            items = values
        } else if case let .object(object) = json {
            if case let .array(values)? = object["rssSources"] {
                items = values
            } else {
                items = [json]
            }
        } else {
            return []
        }
        return items.compactMap { RssSourceJSONBridge.decode($0) }
    }

    static func replaceRuleFromBody(_ body: Data) throws -> ReplaceRule? {
        let text = String(decoding: body, as: UTF8.self)
        guard !text.isEmpty else { return nil }
        let json = try JSONValue.parse(text)
        return ReplaceRuleJSONBridge.decode(json)
    }

    /// The `{rule, text}` payload of the rule test — upstream
    /// `ReplaceRuleController.testRule`.
    struct ReplaceRuleTestPayload {
        let rule: ReplaceRule
        let text: String
    }

    static func testPayloadFromBody(_ body: Data) throws -> ReplaceRuleTestPayload? {
        let text = String(decoding: body, as: UTF8.self)
        guard !text.isEmpty else { return nil }
        let json = try JSONValue.parse(text)
        guard case let .object(object) = json else { return nil }
        guard let ruleValue = object["rule"] else { return nil }
        let rule: ReplaceRule?
        if case let .string(text) = ruleValue {
            guard let parsed = try? JSONValue.parse(text) else { return nil }
            rule = ReplaceRuleJSONBridge.decode(parsed)
        } else {
            rule = ReplaceRuleJSONBridge.decode(ruleValue)
        }
        guard let rule else { return nil }
        return ReplaceRuleTestPayload(rule: rule, text: object["text"]?.textValue ?? "")
    }

    /// Applies a single replace rule — upstream `ReplaceRuleController.testRule`.
    static func applyReplaceRule(_ rule: ReplaceRule, to text: String) -> String {
        guard !rule.pattern.isEmpty else { return text }
        if rule.isRegex {
            guard let expression = try? NSRegularExpression(pattern: rule.pattern) else { return text }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            return expression.stringByReplacingMatches(
                in: text,
                options: [],
                range: range,
                withTemplate: rule.replacement
            )
        }
        return text.replacingOccurrences(of: rule.pattern, with: rule.replacement)
    }
}
