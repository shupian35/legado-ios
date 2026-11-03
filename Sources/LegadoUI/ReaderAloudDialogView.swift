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
                }
            }
        }
        .navigationTitle("朗读设置")
        .onAppear {
            loadEngines()
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
    }

    /// Loads the HTTP TTS engines of the user — upstream `HttpTTSDao.all`.
    private func loadEngines() {
        engines = (try? controller.environment.store.allHttpTTS()) ?? []
        let stored = settings.ttsEngineId
        selectedEngineId = engines.contains(where: { $0.id == stored }) ? stored : 0
        selectEngine(id: selectedEngineId)
    }

    /// Switches the engine — upstream `ReadAloud.setTts`.
    private func selectEngine(id: Int64) {
        settings.ttsEngineId = id
        let engine = engines.first(where: { $0.id == id })
        controller.readAloud.useHttpTts(engine)
    }
}
