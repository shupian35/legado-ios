//
//  ReadAloudPlatform.swift
//  LegadoUI
//
//  The Apple binding of the read aloud.
//
//  Upstream the read aloud is a foreground service:
//  * `service/TTSReadAloudService.kt` drives the Android `TextToSpeech`;
//  * `service/HttpReadAloudService.kt` downloads the audio of every paragraph
//    from an HTTP TTS service and plays it with `MediaPlayer`.
//
//  The state machine of both lives in `LegadoCore/Reader/ReadAloud.swift`; the
//  files here only provide the platform engines:
//
//  * `AVSpeechSynthesizerEngine` — the system voice (`AVSpeechSynthesizer`);
//  * `AVAudioTtsPlayer` — the raw audio bytes of the HTTP TTS.
//
//  Both are behind `#if canImport(AVFoundation)`, so the Linux build ignores
//  them and the port stays verifiable there.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

#if canImport(AVFoundation)
import AVFoundation

// MARK: - The system voice

/// The system speech engine (`AVSpeechSynthesizer`).
///
/// Upstream `TTSReadAloudService` uses the Android `TextToSpeech` engine; the
/// upstream rate `(ttsSpeechRate + 5) / 10` (1.0 = the default speed) is
/// mapped onto the AVSpeechUtterance range (the minimum … the maximum).
public final class AVSpeechSynthesizerEngine: NSObject, SpeechSynthesizing, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    /// The language of the voice — upstream picks it from the system locale.
    public var language: String = Locale.current.identifier
    /// Upstream `AppConfig.ignoreAudioFocus` — when it is on the speech mixes
    /// with the audio of the other apps.
    public var ignoreAudioFocus: Bool = false

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func speak(_ text: String, rate: Float, completion: @escaping (Bool) -> Void) {
        Self.activateAudioSession(ignoreAudioFocus: ignoreAudioFocus)
        _ = synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = Self.utteranceRate(for: rate)
        utterance.pitchMultiplier = 1.0
        pendingCompletion = completion
        activeUtterance = utterance
        synthesizer.speak(utterance)
    }

    public func stop() {
        _ = synthesizer.stopSpeaking(at: .immediate)
        activeUtterance = nil
        pendingCompletion?(false)
        pendingCompletion = nil
    }

    /// Activates the media playback category.
    ///
    /// Without it iOS mutes the speech when the ring switch is silent and
    /// while the device is locked.
    ///
    /// Upstream `BaseReadAloudService.requestFocus()` returns immediately when
    /// `AppConfig.ignoreAudioFocus` is on — the speech then mixes with the
    /// audio of the other apps instead of interrupting it, which is what the
    /// ambient category does on iOS.
    static func activateAudioSession(ignoreAudioFocus: Bool = false) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(ignoreAudioFocus ? .ambient : .playback)
        try? session.setActive(true)
    }

    /// Maps the upstream rate (1.0 = the default) onto the AVSpeech range.
    public static func utteranceRate(for rate: Float) -> Float {
        let clamped = min(max(rate, 0.5), 2.0)
        let minimum = AVSpeechUtteranceMinimumSpeechRate
        let maximum = AVSpeechUtteranceMaximumSpeechRate
        let normal = AVSpeechUtteranceDefaultSpeechRate
        if clamped <= 1.0 {
            let span = normal - minimum
            return minimum + span * (clamped - 0.5) / 0.5
        } else {
            let span = maximum - normal
            return normal + span * (clamped - 1.0)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        // The delegate reports the utterance the callback belongs to — the
        // callback of an utterance that was cancelled in the meantime must
        // not complete the current one.
        guard utterance === activeUtterance else { return }
        activeUtterance = nil
        pendingCompletion?(true)
        pendingCompletion = nil
    }

    public func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        guard utterance === activeUtterance else { return }
        activeUtterance = nil
        pendingCompletion?(false)
        pendingCompletion = nil
    }

    private var pendingCompletion: ((Bool) -> Void)?
    /// The utterance that is spoken right now.
    private var activeUtterance: AVSpeechUtterance?
}

/// Routes the speech either to the system voice or to the HTTP TTS service.
///
/// Upstream the user picks the engine in the settings (`ttsEngine`); the port
/// switches between the two when the user configures an HTTP TTS profile.
public final class RoutableSpeechSynthesizer: SpeechSynthesizing, @unchecked Sendable {

    private let system: SpeechSynthesizing
    /// The HTTP TTS engine — `nil` when the user did not configure one.
    public var http: HttpTtsSynthesizer?

    public init(system: SpeechSynthesizing, http: HttpTtsSynthesizer? = nil) {
        self.system = system
        self.http = http
    }

    public func speak(_ text: String, rate: Float, completion: @escaping (Bool) -> Void) {
        if let http {
            http.speak(text, rate: rate, completion: completion)
        } else {
            system.speak(text, rate: rate, completion: completion)
        }
    }

    public func stop() {
        system.stop()
        http?.stop()
    }
}

// MARK: - The HTTP TTS

/// Speaks the paragraphs through an HTTP TTS service.
///
/// Upstream `HttpReadAloudService` downloads the audio of a paragraph, plays
/// it and moves on to the next one; the response is the raw binary audio and
/// the `contentType` of the profile is a regular expression the response
/// content type has to match.
public final class HttpTtsSynthesizer: SpeechSynthesizing, @unchecked Sendable {

    private let tts: HttpTTS
    private let client: HttpClient
    private let scriptEngine: RuleScriptEngine?
    private let player: AVAudioTtsPlayer
    private let streamer: AVStreamingTtsPlayer
    /// How the audio is delivered — upstream `AppConfig.streamReadAloudAudio`.
    public var delivery: HttpTtsDelivery = .download
    /// The upstream `speakSpeed = speechRatePlay + 5`.
    private var speed: Int = 10
    /// The upstream `AppConfig.ttsSpeechRate` — it is part of the name of the
    /// cached audio.
    public var speechRate: Int = 0
    /// Upstream `AppConfig.ignoreAudioFocus`.
    public var ignoreAudioFocus: Bool = false
    /// The folder of the cached audio — upstream `cacheDir/httpTTS`.
    public var cacheRoot: URL?
    /// The title of the chapter — it is part of the name of the cached audio.
    public var chapterTitle: String = ""
    /// The stored login header of the profile — upstream
    /// `AnalyzeUrl(source = httpTts)` merges it into the request.
    public var loginHeaderMap: [String: String]?
    /// The callback that receives the error messages of the service — upstream
    /// `AppLog.put(msg, e, true)`.
    public var onError: ((String) -> Void)?
    /// The task of the running download.
    private var task: Task<Void, Never>?

    public init(
        tts: HttpTTS,
        client: HttpClient = URLSessionHttpClient(),
        scriptEngine: RuleScriptEngine? = nil,
        player: AVAudioTtsPlayer = AVAudioTtsPlayer(),
        streamer: AVStreamingTtsPlayer = AVStreamingTtsPlayer()
    ) {
        self.tts = tts
        self.client = client
        self.scriptEngine = scriptEngine
        self.player = player
        self.streamer = streamer
    }

    /// Sets the upstream speed.
    public func setSpeed(_ speed: Int) {
        self.speed = speed
    }

    public func speak(_ text: String, rate: Float, completion: @escaping (Bool) -> Void) {
        task?.cancel()
        task = Task {
            do {
                let speakText = HttpTtsPlayback.speakText(text)
                let request = try HttpTts.request(
                    text: speakText,
                    tts: tts,
                    speed: speed,
                    scriptEngine: scriptEngine,
                    loginHeaderMap: loginHeaderMap
                )
                if delivery == .stream {
                    // The audio is streamed straight from the server — upstream
                    // `downloadAndPlayAudiosStream()`.
                    guard let url = URL(string: request.url) else {
                        completion(false)
                        return
                    }
                    streamer.play(
                        url: url,
                        headers: request.headers,
                        ignoreAudioFocus: ignoreAudioFocus,
                        completion: completion
                    )
                    return
                }
                // Upstream `hasSpeakFile(name)`: the audio that was downloaded
                // before is played again.
                if let root = cacheRoot,
                   let cached = HttpTtsCache.data(
                       root: root,
                       text: text,
                       chapterTitle: chapterTitle,
                       ttsUrl: tts.url,
                       speechRate: speechRate
                   ) {
                    player.play(data: cached, ignoreAudioFocus: ignoreAudioFocus, completion: completion)
                    return
                }
                let response = try await client.send(request)
                let contentType = response.headers.first { $0.key.lowercased() == "content-type" }?.value
                var data = response.data ?? response.errorBody
                // Upstream `analyzeUrl.evalJS(checkJs, response)`.
                if let checkJs = tts.loginCheckJs, !checkJs.isEmpty {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                    let result = try HttpTts.applyLoginCheck(
                        script: checkJs,
                        body: body,
                        code: response.code,
                        headers: response.headers,
                        scriptEngine: scriptEngine
                    )
                    switch result {
                    case .unchanged:
                        break
                    case .body(let newBody):
                        data = newBody.data(using: .utf8)
                    case .failure(let message):
                        onError?(message)
                        completion(false)
                        return
                    }
                }
                // Upstream `getSpeakStream`: a JSON or a text response is the
                // error message of the service.
                let text_ = data.flatMap { String(data: $0, encoding: .utf8) }
                if let message = HttpTts.errorMessage(contentType: contentType, body: text_, tts: tts) {
                    onError?(message)
                    completion(false)
                    return
                }
                guard let audio = data else {
                    completion(false)
                    return
                }
                guard HttpTts.matches(contentType: contentType, tts: tts) else {
                    completion(false)
                    return
                }
                if let root = cacheRoot {
                    HttpTtsCache.store(
                        audio,
                        root: root,
                        text: text,
                        chapterTitle: chapterTitle,
                        ttsUrl: tts.url,
                        speechRate: speechRate
                    )
                }
                player.play(data: audio, ignoreAudioFocus: ignoreAudioFocus, completion: completion)
            } catch {
                completion(false)
            }
        }
    }

    /// Downloads the audio of the paragraphs of the next chapter — upstream
    /// `preDownloadAudios(httpTts)`: the first ten paragraphs of the next
    /// chapter are fetched while the current one is spoken.
    public func preDownload(paragraphs: [String], chapterTitle: String) {
        guard delivery == .download, let root = cacheRoot else { return }
        let items = HttpTtsPlayback.preDownloadPlan(
            paragraphs: paragraphs,
            chapterTitle: chapterTitle,
            ttsUrl: tts.url,
            speechRate: speechRate
        )
        Task {
            for item in items {
                guard !item.isSilent else { continue }
                if HttpTtsCache.data(
                    root: root,
                    text: item.text,
                    chapterTitle: chapterTitle,
                    ttsUrl: tts.url,
                    speechRate: speechRate
                ) != nil {
                    continue
                }
                guard let request = try? HttpTts.request(
                    text: item.speakText,
                    tts: tts,
                    speed: speed,
                    scriptEngine: scriptEngine,
                    loginHeaderMap: loginHeaderMap
                ) else { continue }
                guard let response = try? await client.send(request),
                      let data = response.data ?? response.errorBody else { continue }
                HttpTtsCache.store(
                    data,
                    root: root,
                    text: item.text,
                    chapterTitle: chapterTitle,
                    ttsUrl: tts.url,
                    speechRate: speechRate
                )
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        player.stop()
        streamer.stop()
    }
}

/// Plays the raw audio bytes of the HTTP TTS service.
///
/// Upstream `HttpReadAloudService` downloads the whole chapter worth of audio
/// up front (unless `streamReadAloudAudio` is on) and plays the parts one by
/// one with a `MediaPlayer`.
public final class AVAudioTtsPlayer: NSObject, AVAudioPlayerDelegate {

    private var player: AVAudioPlayer?
    private var pendingCompletion: ((Bool) -> Void)?

    /// The MIME type of the downloaded bytes — upstream stores it to pick the
    /// player (`MediaPlayer` uses the content type of the response).
    public var contentType: String?

    public func play(data: Data, ignoreAudioFocus: Bool = false, completion: @escaping (Bool) -> Void) {
        stop()
        AVSpeechSynthesizerEngine.activateAudioSession(ignoreAudioFocus: ignoreAudioFocus)
        do {
            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            _ = player.prepareToPlay()
            _ = player.play()
            self.player = player
            pendingCompletion = completion
        } catch {
            completion(false)
        }
    }

    public func stop() {
        player?.stop()
        player = nil
        pendingCompletion?(false)
        pendingCompletion = nil
    }

    // MARK: - AVAudioPlayerDelegate

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        pendingCompletion?(flag)
        pendingCompletion = nil
    }
}

// MARK: - The streaming player

/// Streams the audio of the HTTP TTS service straight from the server.
///
/// Upstream `HttpReadAloudService.downloadAndPlayAudiosStream()` hands the
/// URL of the audio to the player instead of downloading it into a cache file
/// first (the preference `AppConfig.streamReadAloudAudio`).
public final class AVStreamingTtsPlayer: NSObject {

    private var player: AVPlayer?
    private var pendingCompletion: ((Bool) -> Void)?
    private var endObserver: NSObjectProtocol?

    public override init() {
        super.init()
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    /// Streams the audio of `url`.
    ///
    /// - Parameters:
    ///   - url: the URL of the audio.
    ///   - headers: the headers of the TTS request — upstream sends them
    ///     with the request as well.
    public func play(url: URL, headers: [String: String], ignoreAudioFocus: Bool = false, completion: @escaping (Bool) -> Void) {
        stop()
        AVSpeechSynthesizerEngine.activateAudioSession(ignoreAudioFocus: ignoreAudioFocus)
        var options: [String: Any] = [:]
        if !headers.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
        }
        let asset = AVURLAsset(url: url, options: options)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player
        pendingCompletion = completion
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.finish(true)
        }
        player.play()
    }

    public func stop() {
        player?.pause()
        player = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        pendingCompletion?(false)
        pendingCompletion = nil
    }

    private func finish(_ success: Bool) {
        pendingCompletion?(success)
        pendingCompletion = nil
    }
}

#endif

// MARK: - The read-aloud service

/// Drives the read aloud on Apple platforms.
///
/// It owns the `ReadAloudController` of `LegadoCore` and provides the platform
/// engines: the system voice and — when the user configured an HTTP TTS
/// profile — the audio player.
@available(iOS 17.0, macOS 14.0, *)
public final class ReadAloudService: ObservableObject {

    /// The state machine of `LegadoCore`.
    public let controller: ReadAloudController

    /// The HTTP TTS profile of the user (upstream `HttpTTS`).
    public var httpTts: HttpTTS?

    /// The HTTP client used to download the audio.
    public var httpClient: HttpClient

    /// The script engine of the rules (used to evaluate the `{{speakText}}`).
    public var scriptEngine: RuleScriptEngine?

    @Published public private(set) var state: ReadAloudState = .stopped
    @Published public private(set) var currentParagraph: ReadAloudParagraph?

    /// The book the reader speaks (the notification shows it).
    public var bookName: String = ""
    /// The chapter the reader speaks (the notification shows it).
    ///
    /// It is part of the name of the cached audio — upstream
    /// `md5SpeakFileName(content, textChapter)`.
    public var chapterTitle: String = "" {
        didSet {
            #if canImport(AVFoundation)
            router?.http?.chapterTitle = chapterTitle
            #endif
        }
    }

    /// The folder of the cached audio — upstream `cacheDir/httpTTS`.
    public var cacheRoot: URL?

    /// The stored login header of the profile — upstream
    /// `AnalyzeUrl(source = httpTts)` merges it into the request.
    public var loginHeaderMap: [String: String]?

    /// The upstream `AppConfig.ttsSpeechRate` — it is part of the name of the
    /// cached audio.
    public var ttsSpeechRate: Int = 0

    /// The callback that receives the error messages of the service — upstream
    /// `AppLog.put(msg, e, true)`.
    public var onError: ((String) -> Void)?

    /// The sink of the transport notification (upstream
    /// `BaseReadAloudService` posts the state with the six media actions).
    public var notificationSink: NotificationPosting?

    /// Posts the transport notification for the current state.
    public func postNotification() {
        guard let sink = notificationSink else { return }
        let content = NotificationContent.readAloud(
            bookName: bookName,
            chapterTitle: chapterTitle,
            isPlaying: state == .playing
        )
        sink.post(content)
    }

    #if canImport(AVFoundation)
    private let speechEngine: AVSpeechSynthesizerEngine?
    private let audioPlayer = AVAudioTtsPlayer()
    private let router: RoutableSpeechSynthesizer?
    #endif

    public init(httpClient: HttpClient = URLSessionHttpClient(), scriptEngine: RuleScriptEngine? = nil) {
        self.httpClient = httpClient
        self.scriptEngine = scriptEngine
        #if canImport(AVFoundation)
        let engine = AVSpeechSynthesizerEngine()
        let router = RoutableSpeechSynthesizer(system: engine)
        speechEngine = engine
        self.router = router
        controller = ReadAloudController(synthesizer: router)
        #else
        controller = ReadAloudController()
        #endif
        controller.onStateChange { [weak self] state in
            self?.state = state
            self?.postNotification()
        }
        controller.onProgress { [weak self] paragraph in
            self?.currentParagraph = paragraph
        }
    }

    /// Uses an HTTP TTS profile (upstream `HttpTTS`); `nil` switches back to
    /// the system voice.
    public func useHttpTts(_ tts: HttpTTS?) {
        httpTts = tts
        #if canImport(AVFoundation)
        if let tts {
            let engine = HttpTtsSynthesizer(
                tts: tts,
                client: httpClient,
                scriptEngine: scriptEngine
            )
            engine.setSpeed(controller.currentConfiguration.speakSpeed)
            engine.delivery = delivery
            engine.cacheRoot = cacheRoot
            engine.chapterTitle = chapterTitle
            engine.loginHeaderMap = loginHeaderMap
            engine.speechRate = ttsSpeechRate
            engine.onError = onError
            router?.http = engine
        } else {
            router?.http = nil
        }
        #endif
    }

    /// Copies the settings of the service into the HTTP TTS engine.
    public func refreshHttpTtsSettings() {
        #if canImport(AVFoundation)
        guard let engine = router?.http else { return }
        engine.cacheRoot = cacheRoot
        engine.chapterTitle = chapterTitle
        engine.loginHeaderMap = loginHeaderMap
        engine.speechRate = ttsSpeechRate
        engine.onError = onError
        #endif
    }

    /// Downloads the audio of the next chapter — upstream `preDownloadAudios`.
    ///
    /// The first ten paragraphs of the next chapter are fetched while the
    /// current one is spoken.
    public func preDownloadNextChapter(paragraphs: [String], chapterTitle: String) {
        #if canImport(AVFoundation)
        router?.http?.preDownload(paragraphs: paragraphs, chapterTitle: chapterTitle)
        #endif
    }

    /// How the audio of the HTTP TTS engine is delivered — upstream
    /// `AppConfig.streamReadAloudAudio`.
    public private(set) var delivery: HttpTtsDelivery = .download

    /// Sets the delivery mode of the HTTP TTS engine — upstream
    /// `AppConfig.streamReadAloudAudio`.
    public func setDelivery(_ delivery: HttpTtsDelivery) {
        self.delivery = delivery
        #if canImport(AVFoundation)
        router?.http?.delivery = delivery
        #endif
    }

    /// Reads the chapter aloud, starting at the paragraph.
    public func play(paragraphs: [ReadAloudParagraph], chapterIndex: Int = 0, startIndex: Int = 0) {
        controller.play(paragraphs: paragraphs, chapterIndex: chapterIndex, startIndex: startIndex)
    }

    /// Pauses the speech.
    public func pause() {
        controller.pause()
        #if canImport(AVFoundation)
        speechEngine?.stop()
        audioPlayer.stop()
        #endif
    }

    /// Continues the speech.
    public func resume() {
        controller.resume()
    }

    /// Stops the speech.
    public func stop() {
        controller.stop()
        cancelTimer()
        timer.cancel()
        remainingMinutes = 0
        #if canImport(AVFoundation)
        speechEngine?.stop()
        audioPlayer.stop()
        #endif
    }

    /// The auto-stop timer in minutes — upstream `ReadAloud.setTimer`.
    ///
    /// `0` disables the timer.
    public var timerMinutes: Int {
        get { timer.minutes }
        set { startTimer(minutes: newValue) }
    }

    /// The minutes that are left — upstream `BaseReadAloudService.timeMinute`.
    ///
    /// The upstream counts it down every minute and posts it to the UI
    /// (`EventBus.READ_ALOUD_DS`); the timer does not run while the speech is
    /// paused.
    @Published public private(set) var remainingMinutes: Int = 0

    /// The countdown itself — upstream `BaseReadAloudService.doDs`.
    private var timer = ReadAloudTimer()

    /// The task of the auto-stop timer.
    private var timerTask: Task<Void, Never>?

    /// Starts (or cancels) the auto-stop timer — upstream
    /// `ReadAloud.setTimer(context, minutes)`.
    ///
    /// The speech stops when the timer expires.
    public func startTimer(minutes: Int) {
        timer.start(minutes: minutes)
        remainingMinutes = timer.remaining
        cancelTimer()
        guard timer.minutes > 0 else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard let self else { return }
                // The upstream does not count while the speech is paused.
                let expired = self.timer.tick(paused: self.state == .paused)
                self.remainingMinutes = self.timer.remaining
                if expired {
                    self.stop()
                    return
                }
            }
        }
    }

    /// Adds ten minutes to the timer — upstream `BaseReadAloudService.addTimer`.
    ///
    /// The upstream stops at 180 minutes and wraps around to zero.
    public func addTimer() {
        timer.add()
        remainingMinutes = timer.remaining
        cancelTimer()
        guard timer.minutes > 0 else { return }
        startTimer(minutes: timer.minutes)
    }

    /// Cancels the auto-stop timer.
    public func cancelTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// Moves to the next paragraph.
    public func nextParagraph() {
        controller.nextParagraph()
    }

    /// Moves to the previous paragraph.
    public func previousParagraph() {
        controller.prevParagraph()
    }

    /// The rate the upstream uses: `(ttsSpeechRate + 5) / 10`.
    public static func speechRate(for setting: Int) -> Float {
        Float(setting + 5) / 10.0
    }

    /// The identifier of the system voice — upstream the user picks one of the
    /// system engines (`SpeakEngineDialog` → `viewModel.sysEngines`).
    public var systemVoiceIdentifier: String {
        get {
            #if canImport(AVFoundation)
            return speechEngine?.language ?? Locale.current.identifier
            #else
            return Locale.current.identifier
            #endif
        }
        set {
            #if canImport(AVFoundation)
            speechEngine?.language = newValue
            #endif
        }
    }

    /// Upstream `AppConfig.ignoreAudioFocus` — when it is on the speech mixes
    /// with the audio of the other apps instead of interrupting it.
    public var ignoreAudioFocus: Bool = false {
        didSet {
            #if canImport(AVFoundation)
            speechEngine?.ignoreAudioFocus = ignoreAudioFocus
            router?.http?.ignoreAudioFocus = ignoreAudioFocus
            #endif
        }
    }
}

// MARK: - The system voices

extension ReadAloudVoice {
    /// The system voices of the platform — upstream `viewModel.sysEngines`.
    public static var available: [ReadAloudVoice] {
        #if canImport(AVFoundation)
        return AVSpeechSynthesisVoice.speechVoices()
            .map { ReadAloudVoice(id: $0.identifier, name: $0.name) }
            .sorted { $0.name < $1.name }
        #else
        return []
        #endif
    }
}
