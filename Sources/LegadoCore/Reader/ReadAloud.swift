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

    /// The speakable units of a chapter when the read aloud speaks page by
    /// page — upstream `textChapter.getNeedReadAloud(0, readAloudByPage = true, 0)`.
    ///
    /// With 按页朗读 the whole page is one spoken unit, so the speech follows
    /// the pages and pauses at the page border.
    public static func pageParagraphs(in chapter: TextChapter) -> [ReadAloudParagraph] {
        var result: [ReadAloudParagraph] = []
        for page in chapter.pages {
            let text = page.text.trimmingCharacters(in: .newlines)
            guard !text.isEmpty, !isSkipped(text) else { continue }
            let start = page.chapterPosition
            result.append(
                ReadAloudParagraph(
                    index: result.count,
                    text: text,
                    start: start,
                    end: start + text.count
                )
            )
        }
        return result
    }
}

// MARK: - The system voices

/// A voice of the system speech engine.
///
/// Upstream `SpeakEngineDialog` lists the system engines
/// (`viewModel.sysEngines`); on iOS they are the `AVSpeechSynthesisVoice`s.
/// The port keeps the identifier and the name in the Core so that the
/// selection can be stored and tested on every platform.
public struct ReadAloudVoice: Equatable, Identifiable, Sendable {
    /// The identifier of the voice — upstream the name of the engine.
    public let id: String
    /// The name that is shown to the user — upstream the label of the engine.
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

// MARK: - The chapter navigation

/// A chapter of the read aloud — the spoken units plus the index of the
/// chapter they belong to.
public struct ReadAloudChapter: Equatable, Sendable {
    public let chapterIndex: Int
    public let paragraphs: [ReadAloudParagraph]

    public init(chapterIndex: Int, paragraphs: [ReadAloudParagraph]) {
        self.chapterIndex = chapterIndex
        self.paragraphs = paragraphs
    }
}

/// Moves the read aloud from one chapter to the next.
///
/// Upstream the read aloud is a service that talks to `ReadBook`:
/// `BaseReadAloudService.nextChapter()` moves to the next chapter and
/// `prevP()` moves to the previous one (`toLast = true` ⇒ the last spoken
/// paragraph of that chapter).
public protocol ReadAloudChapterNavigating: AnyObject {
    /// The read aloud reached the end of the chapter.
    ///
    /// The implementation moves the reader to the next chapter and returns its
    /// spoken units; `nil` stops the read aloud (upstream `nextChapter()` →
    /// `stopSelf()` when there is no next chapter).
    func readAloudNextChapter(completion: @escaping (ReadAloudChapter?) -> Void)

    /// The read aloud was asked for the previous paragraph but it is the first
    /// one of the chapter.
    ///
    /// The implementation moves the reader to the previous chapter and returns
    /// its spoken units — the last one is spoken (upstream `prevP()` →
    /// `toLast = true; moveToPrevChapter(true)`).
    func readAloudPreviousChapter(completion: @escaping (ReadAloudChapter?) -> Void)
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
    /// The reader that moves the read aloud from one chapter to the next.
    public weak var chapterNavigator: ReadAloudChapterNavigating?
    /// The number of the consecutive failures — upstream `playErrorNo`.
    public private(set) var consecutiveFailures: Int = 0
    /// Called when a paragraph could not be spoken; the argument is the number
    /// of the consecutive failures.
    ///
    /// Upstream `HttpReadAloudService.onPlayerError` skips to the next
    /// paragraph and pauses after five consecutive errors.
    public var onSpeechFailed: ((Int) -> Void)?
    /// Set while the speech is stopped on purpose — a cancelled speech is not
    /// a failure.
    private var isStopping = false
    /// Set while the read aloud moves to another chapter.
    private var isNavigating = false

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
        self.consecutiveFailures = 0
        self.isNavigating = false
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
        consecutiveFailures = 0
        isNavigating = false
        onProgress?(nil)
        setState(.stopped)
    }

    /// Speaks the next paragraph — upstream `ReadAloud.nextParagraph`.
    ///
    /// Upstream `BaseReadAloudService.nextP()`: at the end of the chapter the
    /// read aloud moves to the next chapter and continues there; when there is
    /// no next chapter the read aloud stops.
    public func nextParagraph() {
        guard !paragraphs.isEmpty else { return }
        guard !isNavigating else { return }
        let next = currentIndex + 1
        if next < paragraphs.count {
            currentIndex = next
            speakCurrent()
            return
        }
        guard let navigator = chapterNavigator else {
            // Without a reader there is no chapter to continue with — upstream
            // `nextChapter()` → `stopSelf()`.
            stopSpeaking()
            setState(.stopped)
            return
        }
        isNavigating = true
        navigator.readAloudNextChapter { [weak self] chapter in
            guard let self else { return }
            self.isNavigating = false
            guard let chapter, !chapter.paragraphs.isEmpty else {
                // Upstream `nextChapter()`: there is no next chapter, so the
                // read aloud stops.
                self.stopSpeaking()
                self.setState(.stopped)
                return
            }
            self.paragraphs = chapter.paragraphs
            self.chapterIndex = chapter.chapterIndex
            self.currentIndex = 0
            self.speakCurrent()
        }
    }

    /// Speaks the previous paragraph — upstream `ReadAloud.prevParagraph`.
    ///
    /// Upstream `BaseReadAloudService.prevP()`: at the first paragraph of the
    /// chapter the read aloud moves to the previous chapter and speaks its
    /// last paragraph.
    public func prevParagraph() {
        guard !paragraphs.isEmpty else { return }
        guard !isNavigating else { return }
        let previous = currentIndex - 1
        if previous >= 0 {
            currentIndex = previous
            speakCurrent()
            return
        }
        guard let navigator = chapterNavigator else { return }
        isNavigating = true
        navigator.readAloudPreviousChapter { [weak self] chapter in
            guard let self else { return }
            self.isNavigating = false
            guard let chapter, !chapter.paragraphs.isEmpty else { return }
            self.paragraphs = chapter.paragraphs
            self.chapterIndex = chapter.chapterIndex
            self.currentIndex = chapter.paragraphs.count - 1
            self.speakCurrent()
        }
    }

    private func speakCurrent() {
        guard let paragraph = currentParagraph else {
            setState(.stopped)
            return
        }
        onProgress?(paragraph)
        let rate = configuration.speechRate
        isStopping = false
        synthesizer.speak(paragraph.text, rate: rate) { [weak self] finished in
            guard let self else { return }
            guard self.state == .playing else { return }
            guard !self.isStopping else { return }
            if finished {
                self.consecutiveFailures = 0
                self.nextParagraph()
                return
            }
            // Upstream `HttpReadAloudService.onPlayerError`: the read aloud
            // skips to the next paragraph; after five consecutive errors it
            // pauses.
            self.consecutiveFailures += 1
            self.onSpeechFailed?(self.consecutiveFailures)
            if self.consecutiveFailures >= Self.maximumConsecutiveFailures {
                self.pause()
                return
            }
            self.nextParagraph()
        }
    }

    /// The number of the consecutive failures after which the read aloud
    /// pauses — upstream `playErrorNo >= 5`.
    public static let maximumConsecutiveFailures = 5

    private func stopSpeaking() {
        isStopping = true
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
    ///   - scriptEngine: evaluates the URL and the header rule.
    ///   - loginHeaderMap: the stored login header of the profile — upstream
    ///     `AnalyzeUrl(source = httpTts)` merges it into the request.
    ///   - userAgent: the fallback `User-Agent`.
    public static func request(
        text: String,
        tts: HttpTTS,
        speed: Int = 10,
        scriptEngine: RuleScriptEngine? = nil,
        loginHeaderMap: [String: String]? = nil,
        userAgent: String = SourceSupport.defaultUserAgent
    ) throws -> HttpRequest {
        let url = try buildUrl(text: text, tts: tts, speed: speed, scriptEngine: scriptEngine)
        // Upstream `AnalyzeUrl(source = httpTts)`: the header rule of the
        // profile is evaluated, the login header is merged into it and a
        // default `User-Agent` is added when there is none.
        let headers = tts.headerMap(
            hasLoginHeader: true,
            scriptEngine: scriptEngine,
            userAgent: userAgent,
            loginHeaderMap: loginHeaderMap
        )
        return HttpRequest(url: url, method: "GET", headers: headers)
    }

    /// The error message of a response — upstream `getSpeakStream`.
    ///
    /// The upstream throws `NoStackTraceException(response.body.string())` when
    /// the content type is `application/json` or a `text/*` type, and
    /// `"TTS服务器返回错误：" + body` when the content type does not match the
    /// `contentType` of the profile.
    public static func errorMessage(contentType: String?, body: String?, tts: HttpTTS) -> String? {
        guard let contentType else { return nil }
        let type = (contentType.components(separatedBy: ";").first ?? contentType)
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
        if type == "application/json" || type.hasPrefix("text/") {
            return body ?? ""
        }
        if let expected = tts.contentType, !expected.isEmpty,
           !matches(contentType: type, tts: tts) {
            return "TTS服务器返回错误：" + (body ?? "")
        }
        return nil
    }

    /// The result of the `loginCheckJs` — upstream
    /// `analyzeUrl.evalJS(checkJs, response)`.
    public enum LoginCheckResult: Equatable, Sendable {
        /// The response is unchanged.
        case unchanged
        /// The script replaced the body of the response.
        case body(String)
        /// The script reported an error.
        case failure(String)
    }

    /// Runs the `loginCheckJs` of a profile on a response.
    ///
    /// The upstream binds the response to `result` and uses the value the
    /// script returns as the new response; a text is an error message and an
    /// object with a `body` replaces the body.
    public static func applyLoginCheck(
        script: String,
        body: String,
        code: Int,
        headers: [String: String],
        scriptEngine: RuleScriptEngine?
    ) throws -> LoginCheckResult {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let engine = scriptEngine else { return .unchanged }
        let response = RuleValue.scriptObject([
            "code": .number(Double(code)),
            "body": .text(body),
            "headers": .object(headers.mapValues { RuleValue.text($0) })
        ])
        let result = try engine.evaluate(trimmed, bindings: ["result": response])
        switch result {
        case .null:
            return .unchanged
        case .text(let message):
            return .failure(message)
        case .scriptObject(let members):
            if let newBody = members["body"]?.textValue { return .body(newBody) }
            return .unchanged
        case .object(let members):
            if let newBody = members["body"]?.textValue { return .body(newBody) }
            return .unchanged
        default:
            return .unchanged
        }
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
