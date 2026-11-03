import XCTest

@testable import LegadoCore

/// The change source (换源) — the port of
/// `ui/book/changesource/ChangeBookSourceViewModel.kt`.
final class ChangeSourceTests: XCTestCase {

    // MARK: - The chapter progress mapping

    private func chapter(_ index: Int64, _ title: String) -> BookChapter {
        BookChapter(
            url: "https://example.com/\(index)",
            title: title,
            isVolume: false,
            bookUrl: "https://example.com/book",
            index: index
        )
    }

    func testTheChapterNumberIsParsed() {
        XCTAssertEqual(ChapterProgressMapper.chapterNumber("第十二章 风起"), 12)
        XCTAssertEqual(ChapterProgressMapper.chapterNumber("第 3 回"), 3)
        XCTAssertEqual(ChapterProgressMapper.chapterNumber("12. 新的开始"), 12)
        XCTAssertEqual(ChapterProgressMapper.chapterNumber("第两百五十章"), 250)
        XCTAssertEqual(ChapterProgressMapper.chapterNumber("序章"), -1)
        XCTAssertEqual(ChapterProgressMapper.chapterNumber(nil), -1)
    }

    func testThePureChapterNameDropsTheNumber() {
        XCTAssertEqual(ChapterProgressMapper.pureChapterName("第十二章 风起"), "风起")
        XCTAssertEqual(ChapterProgressMapper.pureChapterName("第3回 风起"), "风起")
        // The upstream `regexB` keeps a number that ends the whole name
        // (the `(?!$)` guard), so "第3回" survives.
        XCTAssertEqual(ChapterProgressMapper.pureChapterName("第3回"), "第3回")
        XCTAssertEqual(ChapterProgressMapper.pureChapterName("【作者】风起"), "风起")
    }

    func testTheChineseNumbersAreParsed() {
        XCTAssertEqual(ChapterProgressMapper.parseChineseNumber("十二"), 12)
        XCTAssertEqual(ChapterProgressMapper.parseChineseNumber("二十"), 20)
        XCTAssertEqual(ChapterProgressMapper.parseChineseNumber("两百五十"), 250)
        XCTAssertEqual(ChapterProgressMapper.parseChineseNumber("一千零一"), 1001)
        XCTAssertEqual(ChapterProgressMapper.parseChineseNumber("12"), 12)
    }

    func testTheJaccardSimilarity() {
        XCTAssertEqual(ChapterProgressMapper.jaccardSimilarity("风起", "风起"), 1.0)
        XCTAssertEqual(ChapterProgressMapper.jaccardSimilarity("风起", "云涌"), 0.0)
        XCTAssertEqual(ChapterProgressMapper.jaccardSimilarity("", ""), 1.0)
        XCTAssertEqual(ChapterProgressMapper.jaccardSimilarity("abc", "abd"), 0.5, accuracy: 0.0001)
    }

    func testTheProgressIsMappedByName() {
        let toc = (1...20).map { chapter(Int64($0), "第\($0)章 标题\($0)") }
        // The old book was at "第5章 标题5" (index 4).
        let index = ChapterProgressMapper.durChapter(
            oldIndex: 4,
            oldTitle: "第5章 标题5",
            newToc: toc,
            oldCount: 20
        )
        XCTAssertEqual(index, 4)
    }

    func testTheProgressIsMappedByNumber() {
        let toc = (1...20).map { chapter(Int64($0), "第\($0)章 标题\($0)") }
        // The old title has no number, so the number of the old chapter is
        // unknown and the index is kept.
        let index = ChapterProgressMapper.durChapter(
            oldIndex: 7,
            oldTitle: "风起",
            newToc: toc,
            oldCount: 20
        )
        XCTAssertEqual(index, 7)
    }

    func testTheProgressIsClampedToTheNewList() {
        let toc = (1...3).map { chapter(Int64($0), "第\($0)章") }
        let index = ChapterProgressMapper.durChapter(
            oldIndex: 19,
            oldTitle: "第20章",
            newToc: toc,
            oldCount: 20
        )
        XCTAssertEqual(index, 2)
    }

    func testAnEmptyListKeepsTheOldIndex() {
        XCTAssertEqual(ChapterProgressMapper.durChapter(oldIndex: 5, oldTitle: "x", newToc: []), 5)
        XCTAssertEqual(ChapterProgressMapper.durChapter(oldIndex: 0, oldTitle: "x", newToc: []), 0)
    }

    // MARK: - The sources

    func testOnlyTheEnabledSourcesAreSearched() {
        let enabled = BookSource(bookSourceUrl: "https://a.com", bookSourceName: "A", enabled: true)
        let disabled = BookSource(bookSourceUrl: "https://b.com", bookSourceName: "B", enabled: false)
        let sources = ChangeSourceService.sources([enabled, disabled])
        XCTAssertEqual(sources.map { $0.bookSourceUrl }, ["https://a.com"])
    }

    func testTheSourcesAreOrderedByTheirCustomOrder() {
        let first = BookSource(bookSourceUrl: "https://a.com", bookSourceName: "A", customOrder: 2, enabled: true)
        let second = BookSource(bookSourceUrl: "https://b.com", bookSourceName: "B", customOrder: 1, enabled: true)
        let sources = ChangeSourceService.sources([first, second])
        XCTAssertEqual(sources.map { $0.bookSourceUrl }, ["https://b.com", "https://a.com"])
    }

    func testTheGroupIsMatchedOnTheCommaBoundaries() {
        let source = BookSource(
            bookSourceUrl: "https://a.com",
            bookSourceName: "A",
            bookSourceGroup: "默认,轻小说",
            enabled: true
        )
        XCTAssertEqual(ChangeSourceService.sources([source], group: "轻小说").count, 1)
        XCTAssertEqual(ChangeSourceService.sources([source], group: "小说").count, 0)
        // An empty group falls back to all the enabled sources.
        XCTAssertEqual(ChangeSourceService.sources([source], group: nil).count, 1)
    }

    func testTheAuthorIsSanitised() {
        XCTAssertEqual(ChangeSourceService.sanitizedAuthor("作者：鲁迅"), "鲁迅")
        XCTAssertEqual(ChangeSourceService.sanitizedAuthor("鲁迅 著"), "鲁迅")
        XCTAssertEqual(ChangeSourceService.sanitizedAuthor("鲁迅"), "鲁迅")
    }

    // MARK: - The ranking

    func testTheCandidatesAreRankedByTheBookScore() {
        let book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        let low = ChangeSourceCandidate(book: book, sourceUrl: "https://a.com", sourceName: "A")
        let high = ChangeSourceCandidate(book: book, sourceUrl: "https://b.com", sourceName: "B")
        let sorted = ChangeSourceService.sorted(
            [low, high],
            options: ChangeSourceOptions(bookScores: [low.scoreKey: 1, high.scoreKey: 5])
        )
        XCTAssertEqual(sorted.map { $0.sourceUrl }, ["https://b.com", "https://a.com"])
    }

    func testTheCandidatesAreRankedByTheSourceScore() {
        let book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        let low = ChangeSourceCandidate(book: book, sourceUrl: "https://a.com", sourceName: "A")
        let high = ChangeSourceCandidate(book: book, sourceUrl: "https://b.com", sourceName: "B")
        let sorted = ChangeSourceService.sorted(
            [low, high],
            options: ChangeSourceOptions(sourceScores: ["https://a.com": 3, "https://b.com": 9])
        )
        XCTAssertEqual(sorted.map { $0.sourceUrl }, ["https://b.com", "https://a.com"])
    }

    func testTheCandidatesAreRankedByTheCustomOrder() {
        let book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        let first = ChangeSourceCandidate(book: book, sourceUrl: "https://a.com", sourceName: "A", originOrder: 1)
        let second = ChangeSourceCandidate(book: book, sourceUrl: "https://b.com", sourceName: "B", originOrder: 2)
        let sorted = ChangeSourceService.sorted([second, first])
        XCTAssertEqual(sorted.map { $0.sourceUrl }, ["https://a.com", "https://b.com"])
    }

    func testTheWordCountBreaksTheTie() {
        let book = Book(bookUrl: "https://example.com/book", name: "测试书", author: "作者")
        let short = ChangeSourceCandidate(
            book: book, sourceUrl: "https://a.com", sourceName: "A",
            chapterWordCount: 10, chapterWordCountText: "[1] 第一章\n字数：10"
        )
        let long = ChangeSourceCandidate(
            book: book, sourceUrl: "https://b.com", sourceName: "B",
            chapterWordCount: 2000, chapterWordCountText: "[5] 第五章\n字数：2000"
        )
        let sorted = ChangeSourceService.sorted([short, long], options: ChangeSourceOptions(loadWordCount: true))
        XCTAssertEqual(sorted.map { $0.sourceUrl }, ["https://b.com", "https://a.com"])
    }

    func testTheChapterNumberIsReadFromTheMeasurementText() {
        XCTAssertEqual(ChangeSourceService.chapterNumber("[12] 第十二章\n字数：1234"), 12)
        XCTAssertEqual(ChangeSourceService.chapterNumber("没有编号"), -1)
        XCTAssertEqual(ChangeSourceService.chapterNumber(nil), -1)
    }

    // MARK: - Switching the source

    func testSwitchingKeepsTheUserFieldsAndTheProgress() {
        var old = Book(bookUrl: "https://old.com/book", name: "测试书", author: "作者")
        old.durChapterIndex = 4
        old.durChapterTitle = "第5章 标题5"
        old.durChapterPos = 120
        old.group = 8
        old.customTag = "标签"
        old.type = BookType.updateError
        let toc = (1...20).map { chapter(Int64($0), "第\($0)章 标题\($0)") }
        var new = Book(bookUrl: "https://new.com/book", name: "测试书", author: "作者")
        new.type = BookType.updateError

        let switched = ChangeSourceService.switchSource(oldBook: old, newBook: new, toc: toc)
        XCTAssertEqual(switched.bookUrl, "https://new.com/book")
        XCTAssertEqual(switched.durChapterIndex, 4)
        XCTAssertEqual(switched.durChapterTitle, "第5章 标题5")
        XCTAssertEqual(switched.durChapterPos, 120)
        XCTAssertEqual(switched.group, 8)
        XCTAssertEqual(switched.customTag, "标签")
        // The "update error" flag is removed.
        XCTAssertEqual(switched.type & BookType.updateError, 0)
    }
}
