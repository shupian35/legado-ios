//
//  SourceCheckView.swift
//  LegadoUI
//
//  The verification of the book sources — upstream
//  `ui/book/source/manage/BookSourceActivity.checkSource` (L498-528) and
//  `ui/config/CheckSourceConfig.kt`.
//
//  The upstream shows a dialog with the keyword of the search, a button that
//  opens the configuration of the check (`CheckSourceConfig`) and the option
//  to check only the selected sources. The options are persisted in the cache
//  (`model/CheckSource.kt`).
//
//  See `AppModel.swift` for the state.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

// MARK: - The verification

/// The verification of the book sources.
///
/// Upstream `BookSourceActivity.checkSource` (L498-528) opens a dialog with
/// the keyword of the search; the keyword of the source wins over the one of
/// the user (`SourceChecker.checkKeyword`). The upstream also limits the
/// check to the selected sources (`CheckSource.start` receives the selection)
/// and the configuration of the check (`CheckSourceConfig`) is persistent.
public struct SourceCheckView: View {

    @ObservedObject var model: LegadoAppModel

    /// The sources to check — an empty list means every source.
    let sources: [BookSource]

    /// Called when the check is done — upstream the `CHECK_SOURCE_DONE` event
    /// that `BookSourceActivity` listens to (it filters the invalid sources
    /// out of the list).
    var onFinished: ((Bool) -> Void)?

    @State private var results: [SourceCheckResult] = []
    @State private var isLoading = false
    @State private var keyword: String = ""
    @State private var config = SourceCheckConfig()
    @State private var isConfigPresented = false
    @State private var message: String?
    @State private var checkTask: Task<Void, Never>?

    public init(
        model: LegadoAppModel,
        sources: [BookSource] = [],
        onFinished: ((Bool) -> Void)? = nil
    ) {
        self.model = model
        self.sources = sources
        self.onFinished = onFinished
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Upstream `BookSourceActivity.checkSource` — the dialog with the
            // keyword of the search.
            HStack(spacing: 8) {
                TextField("校验关键词", text: $keyword)
                    .textFieldStyle(.roundedBorder)
                Button(isLoading ? "取消" : "开始") {
                    isLoading ? cancel() : start()
                }
                .font(.system(size: 13))
            }
            HStack(spacing: 12) {
                Text(config.summary)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                Spacer()
                Button("校验设置") {
                    isConfigPresented = true
                }
                .font(.system(size: 12))
            }
            if isLoading {
                ProgressView("正在校验…")
            }
            if let message {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            List(results, id: \.sourceUrl) { result in
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.source.bookSourceName)
                        .font(.system(size: 15, weight: .medium))
                    Text(result.message)
                        .font(.system(size: 13))
                        .foregroundColor(result.isSuccess ? .secondary : .red)
                    if !result.invalidGroups.isEmpty {
                        Text(result.invalidGroups.joined(separator: ", "))
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .listStyle(PlainListStyle())
        }
        .padding(16)
        .navigationTitle("校验书源")
        .sheet(isPresented: $isConfigPresented) {
            SourceCheckConfigView(model: model) { updated in
                config = updated
                keyword = updated.options.keyword
            }
        }
        .onAppear {
            loadConfig()
            if !isLoading && results.isEmpty {
                start()
            }
        }
        .onDisappear {
            checkTask?.cancel()
        }
    }

    /// The sources of the check — the selection of the user or every source.
    private var targets: [BookSource] {
        if sources.isEmpty {
            return (try? model.environment.sources(enabledOnly: false)) ?? []
        }
        return sources
    }

    /// Loads the persisted options — upstream `CheckSource` reads them from
    /// the cache when the object is created.
    private func loadConfig() {
        config = SourceCheckConfig.load(from: model.environment.settings.settingsStore)
        keyword = config.options.keyword
    }

    /// Starts the check.
    private func start() {
        isLoading = true
        results = []
        message = nil
        var options = config.options
        options.keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        // Upstream `CheckSource.keyword` is kept in the memory; the port
        // persists it with the other options.
        config = SourceCheckConfig(options: options)
        config.save(to: model.environment.settings.settingsStore)
        let total = targets.count
        // Upstream `CheckSourceService` — a resident notification with the
        // progress of the check and a 取消 action.
        model.postCheckNotification(message: "正在检查书源", finished: 0, total: total)
        // Upstream `BookSourceActivity.kt:507` — the screen is kept on while
        // the check runs.
        ScreenAwake.begin()
        checkTask = Task {
            var collected: [SourceCheckResult] = []
            for source in targets {
                if Task.isCancelled { break }
                let result = await checkWithTimeout(source, options: options)
                if Task.isCancelled { break }
                collected.append(result)
                results = collected
                try? model.environment.store.insert(result.source)
                model.postCheckNotification(
                    message: "正在检查书源",
                    finished: collected.count,
                    total: total
                )
            }
            model.reloadSources()
            isLoading = false
            // Upstream `BookSourceActivity.kt:629` — the screen may sleep
            // again when the check is over.
            ScreenAwake.end()
            // Upstream `BookSourceActivity.observeLiveBus` — the check of the
            // sources that failed shows them at the top of the list.
            if let failed = collected.first(where: { !$0.isSuccess }) {
                message = "校验完成，\(collected.filter { !$0.isSuccess }.count) 个书源失效"
                _ = failed
            } else {
                message = "校验完成"
            }
            // Upstream `BookSourceActivity.kt:637-642` — when a source ended
            // up in a group whose name contains "失效" the list is filtered
            // by that word.
            let hasInvalid = collected.contains { result in
                result.invalidGroups.contains { $0.contains("失效") }
            }
            onFinished?(hasInvalid)
        }
        // The 取消 action of the check notification stops the check — upstream
        // `CheckSourceService.stop`.
        model.sourceCheckTask.task = checkTask
    }

    /// Cancels the check — upstream `CheckSource.stop`.
    private func cancel() {
        checkTask?.cancel()
        checkTask = nil
        model.sourceCheckTask.cancel()
        isLoading = false
        // The screen may sleep again — upstream `BookSourceActivity.kt:629`.
        ScreenAwake.end()
        message = "已取消校验"
    }

    /// Checks one source with the timeout of the options.
    ///
    /// Upstream `CheckSourceConfig` limits every request of the check to the
    /// timeout (`CheckSource.timeout`, stored in milliseconds).
    private func checkWithTimeout(
        _ source: BookSource,
        options: SourceCheckOptions
    ) async -> SourceCheckResult {
        let dependencies = model.environment.dependencies()
        let timeout = max(options.timeout, 1)
        let box = SourceCheckTimeoutBox()
        Task {
            let result = await SourceChecker.check(
                source: source,
                options: options,
                dependencies: dependencies
            )
            box.finish(result)
        }
        Task {
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            box.finish(nil)
        }
        let result = await withCheckedContinuation { continuation in
            box.attach(continuation)
        }
        if let result { return result }
        // The timeout expired — upstream `CheckSource.Group.timeout`.
        var updated = source
        updated.addGroup(SourceChecker.Group.timeout)
        updated.addErrorComment(SourceChecker.Group.timeout)
        return SourceCheckResult(
            sourceUrl: source.bookSourceUrl,
            isSuccess: false,
            invalidGroups: updated.invalidGroupNames,
            message: SourceChecker.failureMessage(SourceChecker.Group.timeout),
            respondTime: Int64(timeout * 1000),
            source: updated
        )
    }
}

/// The one-shot box of the timeout of the verification.
final class SourceCheckTimeoutBox: @unchecked Sendable {

    private let lock = NSLock()
    private var continuation: CheckedContinuation<SourceCheckResult?, Never>?
    private var finishedResult: SourceCheckResult?
    private var didFinish = false

    /// Attaches the continuation of the check.
    func attach(_ continuation: CheckedContinuation<SourceCheckResult?, Never>) {
        lock.lock()
        if didFinish {
            let value = finishedResult
            lock.unlock()
            continuation.resume(returning: value)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Finishes the check — with the result of the check or with `nil` when
    /// the timeout expired.
    func finish(_ result: SourceCheckResult?) {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        didFinish = true
        finishedResult = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
    }
}

// MARK: - The configuration of the verification

/// The configuration of the verification — upstream
/// `ui/config/CheckSourceConfig.kt`.
///
/// The upstream edits the timeout in seconds (it is stored in milliseconds)
/// and the toggles are interdependent: the search and the discovery exclude
/// each other, the details of the book enable the chapter list and the
/// content, and the chapter list enables the content.
public struct SourceCheckConfigView: View {

    @ObservedObject var model: LegadoAppModel

    /// The action of the confirmation.
    var onSave: ((SourceCheckConfig) -> Void)?

    @State private var config = SourceCheckConfig()
    @State private var timeoutText: String = "180"
    @State private var message: String?

    public init(model: LegadoAppModel, onSave: ((SourceCheckConfig) -> Void)? = nil) {
        self.model = model
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("超时") {
                    TextField("秒", text: $timeoutText)
                        .legadoNumberPadKeyboard()
                }
                Section("校验内容") {
                    Toggle("搜索", isOn: $config.options.checkSearch)
                        .onChange(of: config.options.checkSearch) { _, value in
                            // Upstream: the search and the discovery exclude
                            // each other.
                            if !value { config.options.checkDiscovery = true }
                        }
                    Toggle("发现", isOn: $config.options.checkDiscovery)
                        .onChange(of: config.options.checkDiscovery) { _, value in
                            if !value { config.options.checkSearch = true }
                        }
                    Toggle("详情", isOn: $config.options.checkInfo)
                        .onChange(of: config.options.checkInfo) { _, value in
                            if !value {
                                config.options.checkCategory = false
                                config.options.checkContent = false
                            }
                        }
                    Toggle("目录", isOn: $config.options.checkCategory)
                        .disabled(!config.options.checkInfo)
                        .onChange(of: config.options.checkCategory) { _, value in
                            if !value { config.options.checkContent = false }
                        }
                    Toggle("正文", isOn: $config.options.checkContent)
                        .disabled(!config.options.checkCategory)
                }
                Section("关键词") {
                    TextField("校验关键词", text: $config.options.keyword)
                }
                if let message {
                    Section {
                        Text(message)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("校验设置")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("确定") {
                        save()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        onSave?(config)
                    }
                }
            }
            .onAppear {
                load()
            }
        }
    }

    /// Loads the persisted options — upstream `CheckSourceConfig.onFragmentCreated`.
    private func load() {
        config = SourceCheckConfig.load(from: model.environment.settings.settingsStore)
        // The upstream shows the timeout in seconds.
        timeoutText = String(config.timeoutSeconds)
    }

    /// Saves the options — upstream `CheckSourceConfig` writes the timeout in
    /// milliseconds and the five toggles.
    private func save() {
        let trimmed = timeoutText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let seconds = Int(trimmed), seconds > 0 else {
            message = "超时时间必须大于 0 秒"
            return
        }
        config.timeoutSeconds = seconds
        config.save(to: model.environment.settings.settingsStore)
        onSave?(config)
    }
}
