//
//  SourceDebugView.swift
//  LegadoUI
//
//  The book source debugger — upstream `ui/book/source/debug/*`.
//
//  The upstream lets the user type a keyword (or a URL with one of the
//  prefixes) and streams the log of the rule evaluation:
//
//    * a plain URL   → the detail page (`DebugActivity`)
//    * `分类::网址`   → the explore page
//    * `++网址`      → the chapter list page
//    * `--网址`      → the chapter content page
//    * anything else → the search page
//
//  The port uses the platform-independent `SourceDebugger` of `LegadoCore`
//  (the same code the WebSocket debug endpoint uses).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// One line of the debug log.
public struct DebugLogEntry: Identifiable, Equatable, Sendable {
    public let id = UUID()
    /// The upstream state (the `DebugLogState`).
    public let state: Int
    /// The message.
    public let message: String
    /// The elapsed time.
    public let elapsed: String

    public init(state: Int, message: String, elapsed: String) {
        self.state = state
        self.message = message
        self.elapsed = elapsed
    }
}

/// The source debugger screen.
public struct SourceDebugView: View {

    @ObservedObject var model: LegadoAppModel

    /// The sources the user can debug.
    @State private var selectedUrl: String = ""
    /// The keyword or the URL.
    @State private var keyword: String = ""
    /// The log lines.
    @State private var logs: [DebugLogEntry] = []
    /// Whether a debug run is in progress.
    @State private var isRunning = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Picker("书源", selection: $selectedUrl) {
                        ForEach(model.sources, id: \.bookSourceUrl) { source in
                            Text(source.bookSourceName).tag(source.bookSourceUrl)
                        }
                    }
                    TextField("关键字 / 网址", text: $keyword)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("开始调试") {
                            run()
                        }
                        .disabled(isRunning || selectedUrl.isEmpty)
                        if isRunning {
                            ProgressView()
                        }
                    }
                }
                .padding(12)

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(logs) { entry in
                            Text(entry.message)
                                .font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(12)
                }
            }
            .navigationTitle("调试")
            .onAppear {
                if selectedUrl.isEmpty, let first = model.sources.first {
                    selectedUrl = first.bookSourceUrl
                }
            }
        }
    }

    /// Runs the debugger and collects the log.
    private func run() {
        guard let source = model.sources.first(where: { $0.bookSourceUrl == selectedUrl }) else { return }
        logs = []
        isRunning = true
        let debugger = SourceDebugger()
        let collector = DebugLogCollector()
        debugger.sink = collector
        Task {
            await debugger.debugBookSource(
                source,
                key: keyword,
                dependencies: model.environment.dependencies()
            )
            await MainActor.run {
                logs = collector.entries
                isRunning = false
            }
        }
    }
}

/// Collects the log lines of a debug run.
final class DebugLogCollector: DebugLogSink, @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [DebugLogEntry] = []

    /// The collected lines.
    var entries: [DebugLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func printLog(state: Int, message: String) {
        lock.lock()
        storage.append(DebugLogEntry(state: state, message: message, elapsed: ""))
        lock.unlock()
    }
}
