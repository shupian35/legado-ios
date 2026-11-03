//
//  DefaultDataTests.swift
//  LegadoCoreTests
//
//  Tests for the default data that upstream ships in
//  `app/src/main/assets/defaultData/` (the TXT table of contents rules, the
//  HTTP TTS engines, the RSS sources, the dictionary rules and the keyboard
//  assists) and for the import helpers of `DefaultData`.
//
//  Upstream reference: app/src/main/java/io/legado/app/help/DefaultData.kt,
//  app/src/main/java/io/legado/app/data/dao/TxtTocRuleDao.kt,
//  app/src/main/java/io/legado/app/data/dao/HttpTTSDao.kt,
//  app/src/main/java/io/legado/app/data/dao/RssSourceDao.kt,
//  app/src/main/java/io/legado/app/model/localBook/TextFile.kt
//

import XCTest
@testable import LegadoCore

final class DefaultDataTests: XCTestCase {

    private func makeStore() throws -> LegadoStore {
        let store = LegadoStore(tables: MemoryTableStore())
        try store.createSchema()
        return store
    }

    // MARK: - The embedded documents

    func testTheDefaultTxtTocRulesAreDecoded() {
        let rules = DefaultData.txtTocRules
        XCTAssertEqual(rules.count, 26)
        XCTAssertEqual(rules.first?.name, "目录(去空白)")
        XCTAssertEqual(rules.last?.name, "默认分章规则")
        // Upstream marks the defaults with the negative ids so that they can
        // be replaced on an upgrade (`delete from txtTocRules where id < 0`).
        XCTAssertEqual(rules.first?.id, -1)
        XCTAssertEqual(rules.last?.id, -100)
        XCTAssertTrue(rules.allSatisfy { $0.id < 0 })
        XCTAssertEqual(rules.first?.serialNumber, 0)
        XCTAssertEqual(rules.last?.serialNumber, 99)
        // The enabled rules are the ones the upstream ships active.
        let enabled = rules.filter { $0.enable }
        XCTAssertEqual(enabled.map(\.name), [
            "目录(去空白)", "目录", "数字 分隔符 标题名称", "大写数字 分隔符 标题名称",
            "正文 标题/序号", "Chapter/Section/Part/Episode 序号 标题", "特殊符号 序号 标题",
            "特殊符号 标题(单个)", "章/卷 序号 标题", "书名 括号 序号", "书名 序号",
            "字数分割 分节阅读"
        ])
    }

    func testTheDefaultTxtTocRuleRegexesSurviveTheEmbedding() {
        // The JSON escapes must not be eaten by the Swift string literal.
        let rule = DefaultData.txtTocRules[1].rule
        XCTAssertTrue(rule.contains("\\s{0,4}"))
        XCTAssertTrue(rule.contains("(?:章|节"))
        XCTAssertTrue(rule.hasSuffix(".{0,30}$"))
    }

    func testTheDefaultRssSourcesUseTheLegadoGroup() {
        let sources = DefaultData.rssSources
        XCTAssertEqual(sources.count, 4)
        for source in sources {
            XCTAssertEqual(source.sourceGroup, "legado")
        }
        XCTAssertEqual(sources.map(\.sourceName), [
            "使用说明", "小说拾遗", "Meow云", "烏雲净化"
        ])
    }

    func testTheDefaultHttpTTSEnginesHaveNegativeIds() {
        let engines = DefaultData.httpTTS
        XCTAssertEqual(engines.count, 2)
        for engine in engines {
            XCTAssertLessThan(engine.id, 0)
        }
        XCTAssertEqual(engines.map(\.id), [-100, -29])
        XCTAssertEqual(engines.first?.name, "1.百度")
        XCTAssertEqual(engines.first?.contentType, "audio/wav")
    }

    func testTheDefaultDictRulesAndKeyboardAssistsAreDecoded() {
        let dictRules = DefaultData.dictRules
        XCTAssertFalse(dictRules.isEmpty)
        XCTAssertTrue(dictRules.contains { $0.name == "百度汉语" })
        XCTAssertTrue(dictRules.contains { $0.showRule.contains("jsoup") })

        let assists = DefaultData.keyboardAssists
        XCTAssertEqual(assists.count, 32)
        XCTAssertEqual(assists.first?.key, "@css:")
        XCTAssertEqual(assists.last?.key, "useWebView")
        XCTAssertEqual(assists.last?.value, ",{\"webView\": true}")
    }

    // MARK: - The import helpers

    func testImportDefaultsFillsTheEmptyTables() throws {
        let store = try makeStore()
        try DefaultData.importDefaults(store: store)
        XCTAssertEqual(try store.allTxtTocRules().count, 26)
        XCTAssertEqual(try store.allKeyboardAssists().count, 32)
        // The enabled rules keep the order of the upstream (by serial number).
        let enabled = try store.enabledTxtTocRules()
        XCTAssertEqual(enabled.first?.serialNumber, 0)
        XCTAssertEqual(enabled.last?.serialNumber, 23)
    }

    func testImportDefaultsKeepsTheExistingRules() throws {
        let store = try makeStore()
        var rule = TxtTocRule(id: 0, name: "我的规则", rule: "第.*章")
        rule.serialNumber = 9
        try store.insert(rule)

        try DefaultData.importDefaults(store: store)
        let rules = try store.allTxtTocRules()
        XCTAssertEqual(rules.count, 1)
        XCTAssertEqual(rules.first?.name, "我的规则")
        // A rule without an id gets a fresh one (upstream Room generates it).
        XCTAssertNotEqual(rules.first?.id, 0)
    }

    func testImportDefaultTocRulesReplacesTheDefaults() throws {
        let store = try makeStore()
        try DefaultData.importDefaults(store: store)
        try DefaultData.importDefaultTocRules(store: store)
        let rules = try store.allTxtTocRules()
        XCTAssertEqual(rules.count, 26)
        XCTAssertTrue(rules.allSatisfy { $0.id < 0 })
        XCTAssertEqual(rules.first?.id, -1)
        XCTAssertEqual(rules.last?.id, -100)
    }

    func testImportDefaultRssSourcesReplacesTheLegadoGroup() throws {
        let store = try makeStore()
        try DefaultData.importDefaultRssSources(store: store)
        XCTAssertEqual(try store.allRssSources().count, 4)

        try DefaultData.importDefaultRssSources(store: store)
        XCTAssertEqual(try store.allRssSources().count, 4)
    }

    func testImportDefaultHttpTTSReplacesTheDefaults() throws {
        let store = try makeStore()
        try DefaultData.importDefaultHttpTTS(store: store)
        let engines = try store.allHttpTTS()
        XCTAssertEqual(engines.count, DefaultData.httpTTS.count)

        try DefaultData.importDefaultHttpTTS(store: store)
        XCTAssertEqual(try store.allHttpTTS().count, DefaultData.httpTTS.count)
    }

    // MARK: - The table of contents detection

    func testTheDefaultRulesDetectTheChaptersOfATxtFile() throws {
        // The upstream rule "目录(去空白)" needs a blank in front of the
        // title, so the file starts with a line of its own — the text in
        // front of the first title becomes the "前言" prologue, exactly like
        // upstream `TextFile.analyze`.
        let content = """
        一本测试小说

        第一章 开始

        这是第一章的内容。

        第二章 继续

        这是第二章的内容。

        第三章 结束

        这是第三章的内容。
        """
        let rules = DefaultData.txtTocRules.filter { $0.enable }
        let pattern = TextBook.detectTocRule(content: content, rules: rules)
        XCTAssertNotNil(pattern)
        XCTAssertEqual(pattern, rules.first?.rule)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("default-rule-\(UUID().uuidString).txt")
        try content.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let book = TextBook(fileURL: url)
        let parsed = try book.chapterList(tocRules: rules)
        let titles = parsed.chapters.map(\.title)
        XCTAssertEqual(titles, ["前言", "第一章 开始", "第二章 继续", "第三章 结束"])
        XCTAssertEqual(parsed.intro, "一本测试小说\n\n")
    }
}
