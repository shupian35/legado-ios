//
//  ReadAloudTests.swift
//  LegadoCoreTests
//
//  The read-aloud core: the paragraph splitting, the skipped paragraphs, the
//  position mapping and the state machine.
//

import XCTest
@testable import LegadoCore

// MARK: - A recording synthesizer

private final class RecordingSynthesizer: SpeechSynthesizing {
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

// MARK: - The splitter

final class ReadAloudSplitterTests: XCTestCase {

    func testEmptyLinesAreDropped() {
        let paragraphs = ReadAloudSplitter.paragraphs(in: "one\n\ntwo")
        XCTAssertEqual(paragraphs.count, 2)
        XCTAssertEqual(paragraphs[0].text, "one")
        XCTAssertEqual(paragraphs[1].text, "two")
    }

    func testTheOffsetsPointIntoTheContent() {
        let content = "one\ntwo\nthree"
        let paragraphs = ReadAloudSplitter.paragraphs(in: content)
        XCTAssertEqual(paragraphs.count, 3)
        XCTAssertEqual(paragraphs[0].start, 0)
        XCTAssertEqual(paragraphs[0].end, 3)
        XCTAssertEqual(paragraphs[1].start, 4)
        XCTAssertEqual(paragraphs[2].start, 8)
        XCTAssertEqual(content.count, paragraphs[2].end)
    }

    /// Upstream `notReadAloudRegex` — a paragraph made only of punctuation,
    /// symbols, separators or control characters is never spoken.
    func testDecorationParagraphsAreSkipped() {
        XCTAssertTrue(ReadAloudSplitter.isSkipped("……"))
        XCTAssertTrue(ReadAloudSplitter.isSkipped("---"))
        XCTAssertTrue(ReadAloudSplitter.isSkipped("   "))
        XCTAssertTrue(ReadAloudSplitter.isSkipped("· · ·"))
        // A single punctuation mark is decoration as well.
        XCTAssertTrue(ReadAloudSplitter.isSkipped("。"))
        XCTAssertFalse(ReadAloudSplitter.isSkipped("hello"))
        XCTAssertFalse(ReadAloudSplitter.isSkipped("hello。"))
    }

    func testSkippedParagraphsAreNotInTheList() {
        let paragraphs = ReadAloudSplitter.paragraphs(in: "one\n……\ntwo")
        XCTAssertEqual(paragraphs.map(\.text), ["one", "two"])
    }

    func testTheIndexCountsTheSpokenParagraphs() {
        let paragraphs = ReadAloudSplitter.paragraphs(in: "one\n……\ntwo")
        XCTAssertEqual(paragraphs.map(\.index), [0, 1])
    }
}

// MARK: - The position mapping

final class ReadAloudPositionTests: XCTestCase {

    private func makeChapter() -> TextChapter {
        let chapter = TextChapter(
            chapter: BookChapter(url: "u", title: "t"),
            position: 0,
            title: "t",
            chaptersSize: 1,
            sameTitleRemoved: false,
            isVip: false,
            isPay: false,
            effectiveReplaceRules: nil
        )
        for page in 0..<3 {
            let textPage = TextPage()
            textPage.index = page
            textPage.chapterIndex = 0
            textPage.chapterSize = 3
            textPage.text = "0123456789"
            let line = TextLine()
            line.text = "0123456789"
            line.chapterPosition = page * 10
            textPage.addLine(line)
            textPage.isCompleted = true
            chapter.addPage(textPage)
        }
        chapter.isCompleted = true
        return chapter
    }

    func testThePageOfAChapterOffset() {
        let chapter = makeChapter()
        XCTAssertEqual(ReadAloudPosition.pageIndex(forChapterOffset: 0, in: chapter), 0)
        XCTAssertEqual(ReadAloudPosition.pageIndex(forChapterOffset: 12, in: chapter), 1)
        XCTAssertEqual(ReadAloudPosition.pageIndex(forChapterOffset: 25, in: chapter), 2)
    }

    /// Upstream `aloudSpanStart = chapterStart - getReadLength(pageIndex)`.
    func testTheAloudSpanStartIsTheStartOfThePage() {
        let chapter = makeChapter()
        XCTAssertEqual(ReadAloudPosition.aloudSpanStart(chapterOffset: 12, in: chapter), 10)
        XCTAssertEqual(ReadAloudPosition.aloudSpanStart(chapterOffset: 0, in: chapter), 0)
    }
}

// MARK: - The state machine

final class ReadAloudControllerTests: XCTestCase {

    private var synthesizer: RecordingSynthesizer!
    private var controller: ReadAloudController!
    private var paragraphs: [ReadAloudParagraph]!

    override func setUp() {
        super.setUp()
        synthesizer = RecordingSynthesizer()
        controller = ReadAloudController(synthesizer: synthesizer)
        paragraphs = ReadAloudSplitter.paragraphs(in: "one\ntwo\nthree")
    }

    func testTheInitialStateIsStopped() {
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertNil(controller.currentParagraph)
    }

    func testPlaySpeaksTheFirstParagraph() {
        controller.play(paragraphs: paragraphs)
        XCTAssertEqual(controller.state, .playing)
        XCTAssertEqual(synthesizer.spoken, ["one"])
        XCTAssertEqual(controller.currentParagraph?.text, "one")
    }

    func testTheProgressIsPublished() {
        var progress: [String] = []
        controller.onProgress { paragraph in
            if let paragraph { progress.append(paragraph.text) }
        }
        controller.play(paragraphs: paragraphs)
        XCTAssertEqual(progress, ["one"])
    }

    func testTheStateIsPublished() {
        var states: [ReadAloudState] = []
        controller.onStateChange { states.append($0) }
        controller.play(paragraphs: paragraphs)
        controller.pause()
        controller.resume()
        controller.stop()
        XCTAssertEqual(states, [.playing, .paused, .playing, .stopped])
    }

    func testTheNextParagraphIsSpokenWhenTheSpeechEnds() {
        controller.play(paragraphs: paragraphs)
        synthesizer.finish()
        XCTAssertEqual(synthesizer.spoken, ["one", "two"])
        XCTAssertEqual(controller.currentParagraph?.text, "two")
    }

    func testTheLastParagraphDoesNotLoop() {
        controller.play(paragraphs: paragraphs, startIndex: 2)
        synthesizer.finish()
        XCTAssertEqual(synthesizer.spoken, ["three"])
        XCTAssertEqual(controller.currentParagraph?.text, "three")
    }

    func testNextAndPrevParagraph() {
        controller.play(paragraphs: paragraphs)
        controller.nextParagraph()
        XCTAssertEqual(controller.currentParagraph?.text, "two")
        controller.nextParagraph()
        XCTAssertEqual(controller.currentParagraph?.text, "three")
        controller.nextParagraph()
        XCTAssertEqual(controller.currentParagraph?.text, "three")
        controller.prevParagraph()
        XCTAssertEqual(controller.currentParagraph?.text, "two")
        controller.prevParagraph()
        XCTAssertEqual(controller.currentParagraph?.text, "one")
        controller.prevParagraph()
        XCTAssertEqual(controller.currentParagraph?.text, "one")
    }

    func testPauseStopsTheSpeechAndResumeRepeatsTheParagraph() {
        controller.play(paragraphs: paragraphs)
        controller.pause()
        XCTAssertEqual(controller.state, .paused)
        XCTAssertEqual(synthesizer.stopCount, 1)
        controller.resume()
        XCTAssertEqual(controller.state, .playing)
        XCTAssertEqual(synthesizer.spoken, ["one", "one"])
    }

    func testStopClearsTheParagraphs() {
        controller.play(paragraphs: paragraphs)
        controller.stop()
        XCTAssertEqual(controller.state, .stopped)
        XCTAssertNil(controller.currentParagraph)
        XCTAssertTrue(paragraphs.isEmpty == false)
    }

    func testTheChapterOffsetOfTheCurrentParagraph() {
        controller.play(paragraphs: paragraphs, startIndex: 1)
        XCTAssertEqual(controller.currentChapterOffset, 4)
    }

    func testTheDefaultConfigurationMatchesUpstream() {
        let configuration = ReadAloudController.Configuration.default
        XCTAssertEqual(configuration.speechRate, 1.0)
        XCTAssertEqual(configuration.speakSpeed, 10)
        XCTAssertFalse(configuration.readAloudByPage)
    }
}

// MARK: - The HTTP TTS

final class HttpTtsTests: XCTestCase {

    private func makeTTS(contentType: String? = nil, header: String? = nil) -> HttpTTS {
        HttpTTS(
            id: 1,
            name: "test",
            url: "http://tts.local/{{speakText}}?speed={{speakSpeed}}",
            contentType: contentType,
            header: header
        )
    }

    func testTheRequestCarriesTheTextAndTheSpeed() throws {
        let request = try HttpTts.request(text: "hello", tts: makeTTS())
        XCTAssertTrue(request.url.contains("hello"))
        XCTAssertTrue(request.url.contains("speed=10"))
    }

    func testTheHeaderIsParsed() throws {
        let tts = makeTTS(header: "{\"token\":\"abc\"}")
        let request = try HttpTts.request(text: "x", tts: tts)
        XCTAssertEqual(request.headers["token"], "abc")
    }

    /// Upstream the content type is a regular expression.
    func testTheContentTypeIsMatchedAsARegularExpression() {
        let tts = makeTTS(contentType: "audio/.*")
        XCTAssertTrue(HttpTts.matches(contentType: "audio/mpeg", tts: tts))
        XCTAssertFalse(HttpTts.matches(contentType: "text/html", tts: tts))
    }

    func testAnEmptyContentTypeAcceptsEverything() {
        let tts = makeTTS(contentType: nil)
        XCTAssertTrue(HttpTts.matches(contentType: "text/html", tts: tts))
        XCTAssertTrue(HttpTts.matches(contentType: nil, tts: tts))
    }
}
