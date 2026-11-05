//
//  ReaderAloudDialogView.swift
//  LegadoUI
//
//  The read-aloud settings of the reader — upstream
//  `ui/book/read/config/ReadAloudDialog.kt`.
//
//  The upstream dialog offers:
//  - the speech rate (`AppConfig.ttsSpeechRate`, 0…10) with the
//    跟随系统语速 toggle (`AppConfig.ttsFlowSys`),
//  - the auto-stop timer (`AppConfig.ttsTimer`, 0/5/10/15/30/60/90/180
//    minutes) — `ReadAloud.setTimer(context, minutes)`,
//  - the HTTP TTS engines (`HttpTTS`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The read-aloud settings.
public struct ReaderAloudDialogView: View {

    /// The reader that owns the read aloud.
    @ObservedObject var controller: ReaderController

    /// The timer choices — upstream `ReadAloudDialog`: `intArrayOf(0, 5, 10,
    /// 15, 30, 60, 90, 180)`.
    public static let timerChoices: [Int] = [0, 5, 10, 15, 30, 60, 90, 180]

    @State private var engines: [HttpTTS] = []
    @State private var selectedEngineId: Int64 = 0
    /// Where the chosen engine is stored — upstream `SpeakEngineDialog`:
    /// the footer button 书籍 writes the book's engine, the button 全局
    /// writes the global one and clears the book's.
    @State private var engineScope: EngineScope = .book
    /// The system voices — upstream `SpeakEngineDialog` lists the system
    /// engines (`viewModel.sysEngines`); on iOS they are the
    /// `AVSpeechSynthesisVoice`s.
    @State private var voices: [ReadAloudVoice] = []
    @State private var selectedVoiceId: String = ""

    /// The scope of the chosen engine.
    public enum EngineScope: String, CaseIterable, Identifiable, Sendable {
        /// The engine of the book that is open — upstream 书籍.
        case book
        /// The global default — upstream 全局.
        case global

        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .book: return "本书"
            case .global: return "全局"
            }
        }
    }

    public init(controller: ReaderController) {
        self.controller = controller
    }

    public var body: some View {
        Form {
            Section("语速") {
                Toggle("跟随系统语速", isOn: Binding(
                    get: { settings.ttsFollowSys },
                    set: { value in
                        settings.ttsFollowSys = value
                        applyConfiguration()
                    }
                ))
                if !settings.ttsFollowSys {
                    HStack {
                        Text("语速")
                        Slider(
                            value: Binding(
                                get: { Double(settings.ttsSpeechRate) },
                                set: { value in
                                    settings.ttsSpeechRate = Int(value.rounded())
                                }
                            ),
                            in: 0...10,
                            step: 1
                        )
                        Text("\(settings.ttsSpeechRate)")
                            .frame(width: 28, alignment: .trailing)
                    }
                }
            }
            Section("朗读") {
                Toggle("按页朗读", isOn: Binding(
                    get: { settings.readAloudByPage },
                    set: { value in
                        settings.readAloudByPage = value
                        applyConfiguration()
                    }
                ))
                // Upstream `pref_config_aloud.xml`: the audio of the HTTP TTS
                // engine is either downloaded or streamed.
                Toggle("流式播放朗读音频", isOn: Binding(
                    get: { settings.streamReadAloudAudio },
                    set: { value in
                        settings.streamReadAloudAudio = value
                        applyConfiguration()
                    }
                ))
                Toggle("忽略音频焦点", isOn: Binding(
                    get: { settings.ignoreAudioFocus },
                    set: { value in settings.ignoreAudioFocus = value }
                ))
                Toggle("通话时暂停朗读", isOn: Binding(
                    get: { settings.pauseReadAloudWhilePhoneCalls },
                    set: { value in settings.pauseReadAloudWhilePhoneCalls = value }
                ))
                Toggle("朗读时保持唤醒", isOn: Binding(
                    get: { settings.readAloudWakeLock },
                    set: { value in settings.readAloudWakeLock = value }
                ))
                Toggle("系统媒体控制兼容", isOn: Binding(
                    get: { settings.systemMediaControlCompatibilityChange },
                    set: { value in settings.systemMediaControlCompatibilityChange = value }
                ))
                Toggle("媒体按钮下一段", isOn: Binding(
                    get: { settings.mediaButtonPerNext },
                    set: { value in settings.mediaButtonPerNext = value }
                ))
            }
            Section("定时停止") {
                Picker("定时", selection: Binding(
                    get: { settings.ttsTimer },
                    set: { value in
                        settings.ttsTimer = value
                        controller.readAloud.startTimer(minutes: value)
                    }
                )) {
                    ForEach(ReaderAloudDialogView.timerChoices, id: \.self) { minutes in
                        Text(minutes == 0 ? "不停止" : "\(minutes) 分钟").tag(minutes)
                    }
                }
            }
            if !engines.isEmpty {
                Section("语音引擎") {
                    Picker("引擎", selection: $selectedEngineId) {
                        Text("系统语音").tag(Int64(0))
                        ForEach(engines, id: \.id) { engine in
                            Text(engine.name).tag(engine.id)
                        }
                    }
                    .onChange(of: selectedEngineId) { _, value in
                        selectEngine(id: value)
                    }
                    // Upstream `SpeakEngineDialog`: the footer decides whether
                    // the engine belongs to the book or to the whole app.
                    Picker("作用范围", selection: $engineScope) {
                        ForEach(EngineScope.allCases) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .onChange(of: engineScope) { _, _ in
                        selectEngine(id: selectedEngineId)
                    }
                }
            }
            if !voices.isEmpty {
                Section("系统语音") {
                    Picker("语音", selection: $selectedVoiceId) {
                        ForEach(voices, id: \.id) { voice in
                            Text(voice.name).tag(voice.id)
                        }
                    }
                    .onChange(of: selectedVoiceId) { _, value in
                        controller.readAloud.systemVoiceIdentifier = value
                    }
                }
            }
        }
        .navigationTitle("朗读设置")
        .onAppear {
            loadEngines()
            loadVoices()
        }
    }

    // MARK: - The helpers

    private var settings: AppSettings {
        controller.environment.settings
    }

    /// Applies the configuration to the running read aloud — upstream
    /// `ReadAloud.updateConfig()`.
    private func applyConfiguration() {
        let rate = settings.ttsFollowSys
            ? ReadAloudService.speechRate(for: 5)
            : ReadAloudService.speechRate(for: settings.ttsSpeechRate)
        controller.readAloud.controller.setConfiguration(
            ReadAloudController.Configuration(
                speechRate: rate,
                speakSpeed: settings.ttsSpeechRate + 5,
                readAloudByPage: settings.readAloudByPage
            )
        )
        // Upstream `AppConfig.streamReadAloudAudio` decides whether the audio
        // of the HTTP TTS engine is downloaded or streamed.
        controller.readAloud.setDelivery(
            settings.streamReadAloudAudio ? .stream : .download
        )
    }

    /// Loads the HTTP TTS engines of the user — upstream `HttpTTSDao.all`.
    private func loadEngines() {
        engines = (try? controller.environment.store.allHttpTTS()) ?? []
        // Upstream `ReadAloud.ttsEngine`: the engine of the book wins over
        // the global one.
        let bookEngine = TtsEngine.engine(of: controller.book)
        let resolved = TtsEngine.resolve(
            bookEngine: bookEngine,
            globalEngine: settings.ttsEngine
        )
        let stored = TtsEngine.profileId(of: resolved) ?? 0
        selectedEngineId = engines.contains(where: { $0.id == stored }) ? stored : 0
        selectEngine(id: selectedEngineId)
    }

    /// Switches the engine — upstream `ReadAloud.setTts`.
    ///
    /// Upstream `SpeakEngineDialog.kt:143-152`: the footer button 书籍 writes
    /// the engine into the book that is open (`ReadBook.book?.setTtsEngine`),
    /// the button 全局 writes the global default (`AppConfig.ttsEngine`) and
    /// clears the book's engine.
    private func selectEngine(id: Int64) {
        let value = id == 0 ? nil : String(id)
        switch engineScope {
        case .book:
            controller.setTtsEngine(value)
        case .global:
            settings.ttsEngine = value
            controller.setTtsEngine(nil)
        }
        let engine = engines.first(where: { $0.id == id })
        controller.readAloud.useHttpTts(engine)
    }

    /// Loads the system voices — upstream `viewModel.sysEngines`.
    private func loadVoices() {
        voices = ReadAloudVoice.available
        let current = controller.readAloud.systemVoiceIdentifier
        selectedVoiceId = voices.contains(where: { $0.id == current }) ? current : ""
    }
}
