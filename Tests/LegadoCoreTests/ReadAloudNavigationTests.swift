//
//  ReadAloudNavigationTests.swift
//  LegadoCoreTests
//
//  The read aloud moves from one chapter to the next — upstream
//  `BaseReadAloudService.nextP()` / `nextChapter()` / `prevP()` — and the
//  failure of a paragraph does not stop the read aloud (upstream
//  `HttpReadAloudService.onPlayerError`).
//

import XCTest
@testable import LegadoCore

// MARK: - The fakes

private final class NavigationSynthesizer: SpeechSynthesizing {
    private(set) var spoken: [String] = []
    private var completions: [(Bool) -> Void] = []
    private(set) var stopCount = 0

    func speak(_ text: String, rate: Float, completion: @escaping (Bool) -> Void) {
        spoken.append(text)
        completions.append(completion)
    }

    func stop() {
        stopCount += 1
        completions.removeAll()
    }

    /// Simulates the end of the speech of the last paragraph.
    func finish(finished: Bool = true) {
        guard let completion = completions.popLast() else { return }
        completion(finished)
    }
}

/// A reader that moves the read aloud from one chapter to the next.
private final class FakeNavigator: ReadAloudChapterNavigating {
    var nextChapter: ReadAloudChapter?
    var previousChapter: ReadAloudChapter?
    private(set) var nextCount = 0
    private(set) var previousCount = 0

    func readAloudNextChapter(completion: @escaping (ReadAloudChapter?) -> Void) {
        nextCount += 1
        completion(nextChapter)
    }

    func readAloudPreviousChapter(completion: @escaping (ReadAloudChapter?) -> Void) {
        previousCount += 1
        completion(previousChapter)
    }
}

// MARK: - The chapter navigation

final class ReadAloudNavigationTests: XCTestCase {

    private var synthesizer: NavigationSynthesizer!
    private var controller: ReadAloudController!
    private var navigator: FakeNavigator!

    override func setUp() {
        super.setUp()
        synthesizer = NavigationSynthesizer()
        controller = ReadAloudController(synthesizer: synthesizer)
        navigator = FakeNavigator()
        controller.chapterNavigator = navigator
    }

    private var paragraphs: [ReadAloudParagraph] {
        ReadAloudSplitter.paragraphs(in: "one\ntwo")
    }

    /// Upstream `BaseReadAloudService.nextP()`: at the end of the chapter the
    /// read aloud moves to the next chapter and continues there.
    func testTheReadAloudContinuesInTheNextChapter() {
        navigator.nextChapter = ReadAloudChapter(
            chapterIndex: 1,
            paragraphs: ReadAloudSplitter.paragraphs(in: "three\nfour")
        )
        controller.play(paragraphs: paragraphs)
        synthesizer.finish()
        XCTAssertEqual(synthesizer.spoken, ["one", "two"])
        // The end of the chapter — the read aloud moves on.
        synthesizer.finish()
        XCTAssertEqual(navigator.nextCount, 1)
        XCTAssertEqual(synthesizer.spoken, ["one", "two", "three"])
        XCTAssertEqual(controller.chapterIndex, 1)
    }

    /// Upstream `nextChapter()` → `stopSelf()` when there is no next chapter.
    func testTheReadAloudStopsWhenThereIsNoNextChapter() {
        navigator.nextChapter = nil
        controller.play(paragraphs: paragraphs)
        synthesizer.finish()
        synthesizer.finish()
        XCTAssertEqual(navigator.nextCount, 1)
        XCTAssertEqual(controller.state, .stopped)
    }

    /// Upstream `prevP()`: at the first paragraph the read aloud moves to the
    /// previous chapter and speaks its last paragraph.
    func testThePreviousParagraphCrossesTheChapter() {
        navigator.previousChapter = ReadAloudChapter(
            chapterIndex: 0,
            paragraphs: ReadAloudSplitter.paragraphs(in: "before one\nbefore two")
        )
        controller.play(paragraphs: paragraphs)
        controller.prevParagraph()
        XCTAssertEqual(navigator.previousCount, 1)
        XCTAssertEqual(synthesizer.spoken, ["one", "before two"])
        XCTAssertEqual(controller.chapterIndex, 0)
    }

    /// Without a reader the read aloud cannot move to another chapter.
    func testWithoutANavigatorTheReadAloudStops() {
        controller.chapterNavigator = nil
        controller.play(paragraphs: paragraphs)
        synthesizer.finish()
        synthesizer.finish()
        XCTAssertEqual(controller.state, .stopped)
    }

    /// Upstream `HttpReadAloudService.onPlayerError`: a failure skips to the
    /// next paragraph instead of stopping the read aloud.
    func testAFailureContinuesWithTheNextParagraph() {
        var failures: [Int] = []
        controller.onSpeechFailed = { failures.append($0) }
        controller.play(paragraphs: paragraphs)
        synthesizer.finish(finished: false)
        XCTAssertEqual(failures, [1])
        XCTAssertEqual(synthesizer.spoken, ["one", "two"])
        XCTAssertEqual(controller.state, .playing)
    }

    /// Upstream `onPlayerError`: after five consecutive errors the read aloud
    /// pauses.
    func testFiveFailuresPauseTheReadAloud() {
        var failures: [Int] = []
        controller.onSpeechFailed = { failures.append($0) }
        // The read aloud moves on so that the failures can accumulate.
        navigator.nextChapter = ReadAloudChapter(
            chapterIndex: 1,
            paragraphs: ReadAloudSplitter.paragraphs(in: "three\nfour")
        )
        controller.play(paragraphs: paragraphs)
        for _ in 0..<5 {
            synthesizer.finish(finished: false)
        }
        XCTAssertEqual(failures, [1, 2, 3, 4, 5])
        XCTAssertEqual(controller.state, .paused)
    }

    /// A cancelled speech is not a failure.
    func testACancelledSpeechIsNotAFailure() {
        var failures: [Int] = []
        controller.onSpeechFailed = { failures.append($0) }
        controller.play(paragraphs: paragraphs)
        controller.pause()
        XCTAssertTrue(failures.isEmpty)
    }

    /// The counter is reset when a paragraph is spoken successfully.
    func testTheFailureCounterIsResetByASuccess() {
        controller.play(paragraphs: paragraphs)
        synthesizer.finish(finished: false)
        XCTAssertEqual(controller.consecutiveFailures, 1)
        synthesizer.finish()
        XCTAssertEqual(controller.consecutiveFailures, 0)
    }
}

// MARK: - 按页朗读

final class ReadAloudPageParagraphTests: XCTestCase {

    private func makeChapter() -> TextChapter {
        let chapter = TextChapter(
            chapter: BookChapter(url: "u1", title: "t", bookUrl: "u", index: 0),
            position: 0,
            title: "t",
            chaptersSize: 1,
            sameTitleRemoved: false,
            isVip: false,
            isPay: false
        )
        for page in 0..<2 {
            let textPage = TextPage()
            textPage.index = page
            textPage.chapterIndex = 0
            textPage.chapterSize = 2
            textPage.text = "page\(page)"
            let line = TextLine()
            line.text = "page\(page)"
            line.chapterPosition = page * 10
            textPage.addLine(line)
            textPage.isCompleted = true
            chapter.addPage(textPage)
        }
        chapter.isCompleted = true
        return chapter
    }

    /// Upstream `textChapter.getNeedReadAloud(0, readAloudByPage = true, 0)`:
    /// the spoken unit is the page.
    func testTheSpokenUnitIsThePage() {
        let units = ReadAloudSplitter.pageParagraphs(in: makeChapter())
        XCTAssertEqual(units.count, 2)
        XCTAssertEqual(units[0].text, "page0")
        XCTAssertEqual(units[1].text, "page1")
        XCTAssertEqual(units[0].start, 0)
        XCTAssertEqual(units[1].start, 10)
    }

    /// A page without text is not spoken.
    func testAnEmptyPageIsSkipped() {
        let chapter = makeChapter()
        let page = chapter.page(at: 0)!
        page.text = "   \n  "
        let units = ReadAloudSplitter.pageParagraphs(in: chapter)
        XCTAssertEqual(units.count, 1)
        XCTAssertEqual(units[0].text, "page1")
    }
}
