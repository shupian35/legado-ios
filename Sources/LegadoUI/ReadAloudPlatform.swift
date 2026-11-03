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

    public override init() {
        super.init()
        synthesizer.delegate = self
    }

    public func speak(_ text: String, rate: Float, completion: @escaping (Bool) -> Void) {
        Self.activateAudioSession()
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
    static func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback)
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
    /// The upstream `speakSpeed = speechRatePlay + 5`.
    private var speed: Int = 10
    /// The task of the running download.
    private var task: Task<Void, Never>?

    public init(
        tts: HttpTTS,
        client: HttpClient = URLSessionHttpClient(),
        scriptEngine: RuleScriptEngine? = nil,
        player: AVAudioTtsPlayer = AVAudioTtsPlayer()
    ) {
        self.tts = tts
        self.client = client
        self.scriptEngine = scriptEngine
        self.player = player
    }

    /// Sets the upstream speed.
    public func setSpeed(_ speed: Int) {
        self.speed = speed
    }

    public func speak(_ text: String, rate: Float, completion: @escaping (Bool) -> Void) {
        task?.cancel()
        task = Task {
            do {
                let request = try HttpTts.request(
                    text: text,
                    tts: tts,
                    speed: speed,
                    scriptEngine: scriptEngine
                )
                let response = try await client.send(request)
                let contentType = response.headers.first { $0.key.lowercased() == "content-type" }?.value
                guard HttpTts.matches(contentType: contentType, tts: tts) else {
                    completion(false)
                    return
                }
                guard let data = response.data ?? response.errorBody else {
                    completion(false)
                    return
                }
                player.play(data: data, completion: completion)
            } catch {
                completion(false)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        player.stop()
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

    public func play(data: Data, completion: @escaping (Bool) -> Void) {
        stop()
        AVSpeechSynthesizerEngine.activateAudioSession()
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
    public var chapterTitle: String = ""

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
            router?.http = engine
        } else {
            router?.http = nil
        }
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
        #if canImport(AVFoundation)
        speechEngine?.stop()
        audioPlayer.stop()
        #endif
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
}
