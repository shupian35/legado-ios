//
//  ReadAloud.swift
//  LegadoCore
//
//  Port of the read-aloud core of
//  `app/src/main/java/io/legado/app/service/BaseReadAloudService.kt`,
//  `app/src/main/java/io/legado/app/service/TTSReadAloudService.kt` and
//  `app/src/main/java/io/legado/app/service/HttpReadAloudService.kt`.
//
//  The spoken unit upstream is the *paragraph*, not the sentence: the chapter
//  content is split with `split("\n")` and every non-empty line is spoken.
//  A paragraph that consists only of whitespace, control characters,
//  punctuation, separators or symbols is skipped
//  (`notReadAloudRegex`).
//
//  The audio playback itself is platform specific (AVSpeechSynthesizer /
//  AVPlayer on Apple platforms) and therefore injected from the outside, so
//  the state machine stays testable on every platform.
//

import Foundation

// MARK: - Paragraphs

/// One speakable paragraph of a chapter.
public struct ReadAloudParagraph: Equatable, Sendable {
    /// The index of the paragraph inside the chapter.
    public let index: Int
    /// The text that is spoken.
    public let text: String
    /// The character offset of the paragraph inside the chapter content.
    public let start: Int
    /// The character offset just after the paragraph.
    public let end: Int

    public init(index: Int, text: String, start: Int, end: Int) {
        self.index = index
        self.text = text
        self.start = start
        self.end = end
    }
}

/// Splits a chapter into the speakable paragraphs.
public enum ReadAloudSplitter {

    /// Upstream `notReadAloudRegex` —
    /// `^(\s|\p{C}|\p{P}|\p{Z}|\p{S})+$`.
    public static let skippedPattern = "^(\\s|\\p{C}|\\p{P}|\\p{Z}|\\p{S})+$"

    private static let skippedRegex = try? NSRegularExpression(pattern: skippedPattern)

    /// Whether the line is skipped (it holds nothing worth speaking).
    public static func isSkipped(_ line: String) -> Bool {
        guard let regex = skippedRegex else { return false }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.firstMatch(in: line, options: [], range: range) != nil
    }

    /// The speakable paragraphs of a chapter content.
    ///
    /// The offsets are the character offsets inside `content`, so the reader
    /// can map the spoken paragraph onto the visible page.
    public static func paragraphs(in content: String) -> [ReadAloudParagraph] {
        var result: [ReadAloudParagraph] = []
        var offset = 0
        var index = 0
        // The upstream split is on "\n" only; "\r" stays inside the line.
        let contentArray = Array(content)
        var lineStart = 0
        var i = 0
        while i <= contentArray.count {
            let isEnd = i == contentArray.count
            if isEnd || contentArray[i] == "\n" {
                let line = String(contentArray[lineStart..<i])
                if !line.isEmpty, !isSkipped(line) {
                    result.append(
                        ReadAloudParagraph(index: index, text: line, start: lineStart, end: i)
                    )
                    index += 1
                }
                lineStart = i + 1
            }
            i += 1
        }
        offset = contentArray.count
        _ = offset
        return result
    }
}

// MARK: - Position mapping

/// Maps the spoken paragraph onto the visible page.
public enum ReadAloudPosition {

    /// The page that holds the character offset — upstream
    /// `pageIndex = binarySearch(page.chapterPosition)`.
    public static func pageIndex(forChapterOffset offset: Int, in chapter: TextChapter) -> Int {
        chapter.pageIndex(forCharacterIndex: offset)
    }

    /// The start of the read-aloud highlight — upstream
    /// `aloudSpanStart = chapterStart - getReadLength(pageIndex)`.
    public static func aloudSpanStart(chapterOffset: Int, in chapter: TextChapter) -> Int {
        let pageIndex = pageIndex(forChapterOffset: chapterOffset, in: chapter)
        return chapter.readLength(pageIndex: pageIndex)
    }

    /// The chapter offset of a paragraph.
    public static func chapterOffset(of paragraph: ReadAloudParagraph) -> Int {
        paragraph.start
    }
}

// MARK: - The synthesizer

/// The platform specific part of the read aloud.
public protocol SpeechSynthesizing: AnyObject {
    /// Speaks the text; the completion is called with `true` when the text was
    /// spoken to the end and `false` when the speech was interrupted.
    func speak(_ text: String, rate: Float, completion: @escaping (Bool) -> Void)
    /// Stops the speech immediately.
    func stop()
}

/// The stub used on the platforms without a speech engine.
public final class UnavailableSpeechSynthesizer: SpeechSynthesizing {
    public init() {}
    public func speak(_ text: String, rate: Float, completion: @escaping (Bool) -> Void) {
        completion(false)
    }
    public func stop() {}
}

// MARK: - The state machine

/// The state of the read aloud — upstream `EventBus.ALOUD_STATE`.
public enum ReadAloudState: String, Sendable {
    case stopped
    case playing
    case paused
}

/// The read-aloud controller.
///
/// Upstream this is a foreground `Service`; the port keeps the same state
/// machine but the audio playback is injected.
public final class ReadAloudController {

    /// The configuration of the read aloud.
    public struct Configuration: Equatable, Sendable {
        /// The local speech rate — upstream `(ttsSpeechRate + 5) / 10f`.
        public var speechRate: Float
        /// The HTTP TTS speed — upstream `speechRatePlay + 5`.
        public var speakSpeed: Int
        /// Whether the read aloud speaks a whole page at once.
        public var readAloudByPage: Bool

        public init(speechRate: Float = 1.0, speakSpeed: Int = 10, readAloudByPage: Bool = false) {
            self.speechRate = speechRate
            self.speakSpeed = speakSpeed
            self.readAloudByPage = readAloudByPage
        }

        /// The upstream default configuration:
        /// `speechRatePlay = 5` when the system rate is followed, so the local
        /// rate is `(5 + 5) / 10 = 1.0` and the HTTP speed is `5 + 5 = 10`.
        public static let `default` = Configuration()
    }

    /// The paragraphs of the chapter that is being read.
    public private(set) var paragraphs: [ReadAloudParagraph] = []
    /// The index of the paragraph that is being read.
    public private(set) var currentIndex: Int = 0
    /// The state of the read aloud.
    public private(set) var state: ReadAloudState = .stopped
    /// The chapter the paragraphs belong to.
    public private(set) var chapterIndex: Int = 0

    private let synthesizer: SpeechSynthesizing
    private var configuration: Configuration
    private var onProgress: ((ReadAloudParagraph?) -> Void)?
    private var onStateChange: ((ReadAloudState) -> Void)?
    /// Set while a completion of a cancelled speech is pending.
    private var pendingCompletion: ((Bool) -> Void)?

    public init(
        synthesizer: SpeechSynthesizing = UnavailableSpeechSynthesizer(),
        configuration: Configuration = .default
    ) {
        self.synthesizer = synthesizer
        self.configuration = configuration
    }

    /// The configuration.
    public var currentConfiguration: Configuration { configuration }

    /// Replaces the configuration.
    public func setConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
    }

    /// The callback that receives the paragraph that is being read.
    public func onProgress(_ handler: ((ReadAloudParagraph?) -> Void)?) {
        onProgress = handler
    }

    /// The callback that receives the state changes.
    public func onStateChange(_ handler: ((ReadAloudState) -> Void)?) {
        onStateChange = handler
    }

    /// The paragraph that is being read.
    public var currentParagraph: ReadAloudParagraph? {
        guard paragraphs.indices.contains(currentIndex) else { return nil }
        return paragraphs[currentIndex]
    }

    /// The chapter offset of the paragraph that is being read.
    public var currentChapterOffset: Int? {
        currentParagraph?.start
    }

    /// Starts the read aloud at the given paragraph.
    public func play(paragraphs: [ReadAloudParagraph], chapterIndex: Int = 0, startIndex: Int = 0) {
        if state == .playing || state == .paused {
            stopSpeaking()
        }
        self.paragraphs = paragraphs
        self.chapterIndex = chapterIndex
        self.currentIndex = paragraphs.isEmpty ? 0 : max(0, min(startIndex, paragraphs.count - 1))
        setState(.playing)
        speakCurrent()
    }

    /// Resumes the read aloud after a pause.
    public func resume() {
        guard state == .paused else { return }
        setState(.playing)
        speakCurrent()
    }

    /// Pauses the read aloud — the paragraph is repeated when it resumes.
    public func pause() {
        guard state == .playing else { return }
        stopSpeaking()
        setState(.paused)
    }

    /// Stops the read aloud.
    public func stop() {
        stopSpeaking()
        paragraphs = []
        currentIndex = 0
        onProgress?(nil)
        setState(.stopped)
    }

    /// Speaks the next paragraph — upstream `ReadAloud.nextParagraph`.
    public func nextParagraph() {
        guard !paragraphs.isEmpty else { return }
        let next = currentIndex + 1
        guard next < paragraphs.count else {
            // Upstream keeps the last paragraph when there is no next one.
            return
        }
        currentIndex = next
        speakCurrent()
    }

    /// Speaks the previous paragraph — upstream `ReadAloud.prevParagraph`.
    public func prevParagraph() {
        guard !paragraphs.isEmpty else { return }
        let previous = currentIndex - 1
        guard previous >= 0 else { return }
        currentIndex = previous
        speakCurrent()
    }

    private func speakCurrent() {
        guard let paragraph = currentParagraph else {
            setState(.stopped)
            return
        }
        onProgress?(paragraph)
        let rate = configuration.speechRate
        synthesizer.speak(paragraph.text, rate: rate) { [weak self] finished in
            guard let self else { return }
            guard finished else { return }
            guard self.state == .playing else { return }
            self.nextParagraph()
        }
    }

    private func stopSpeaking() {
        pendingCompletion = nil
        synthesizer.stop()
    }

    private func setState(_ state: ReadAloudState) {
        guard self.state != state else { return }
        self.state = state
        onStateChange?(state)
    }
}

// MARK: - HTTP TTS

/// Builds the HTTP TTS request — upstream `HttpReadAloudService`.
///
/// The response is **raw binary audio**; `contentType` is a regular expression
/// the response content type has to match.
public enum HttpTts {

    /// The request for one paragraph.
    ///
    /// - Parameters:
    ///   - text: the paragraph that is spoken.
    ///   - tts: the HTTP TTS profile.
    ///   - speed: upstream `speakSpeed = speechRatePlay + 5`.
    public static func request(
        text: String,
        tts: HttpTTS,
        speed: Int = 10,
        scriptEngine: RuleScriptEngine? = nil
    ) throws -> HttpRequest {
        let url = try buildUrl(text: text, tts: tts, speed: speed, scriptEngine: scriptEngine)
        var headers: [String: String] = [:]
        if let header = tts.header, !header.isEmpty {
            if case let .object(parsed)? = try? JSONValue.parse(header) {
                for (key, value) in parsed {
                    headers[key] = value.textValue
                }
            }
        }
        return HttpRequest(url: url, method: "GET", headers: headers)
    }

    /// The URL of the request — the `{{speakText}}` / `{{speakSpeed}}` bindings
    /// are evaluated by the script engine when there is one.
    private static func buildUrl(
        text: String,
        tts: HttpTTS,
        speed: Int,
        scriptEngine: RuleScriptEngine?
    ) throws -> String {
        let raw = tts.url
        guard let engine = scriptEngine else {
            return raw
                .replacingOccurrences(of: "{{speakText}}", with: text)
                .replacingOccurrences(of: "{{speakSpeed}}", with: String(speed))
        }
        let value = try engine.evaluate(raw, bindings: [
            "speakText": .text(text),
            "speakSpeed": .number(Double(speed))
        ])
        return value.textValue ?? raw
    }

    /// Whether a response content type matches the profile.
    ///
    /// `contentType` is a regular expression upstream; an empty value accepts
    /// everything.
    public static func matches(contentType: String?, tts: HttpTTS) -> Bool {
        guard let pattern = tts.contentType, !pattern.isEmpty else { return true }
        guard let contentType else { return false }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(contentType.startIndex..<contentType.endIndex, in: contentType)
        return regex.firstMatch(in: contentType, options: [], range: range) != nil
    }
}
