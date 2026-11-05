//
//  ReaderView.swift
//  LegadoUI
//
//  The reader — upstream `ui/book/read/ReadBookActivity`.
//
//  The pagination itself lives in `LegadoCore` (`ReadBook`, `ChapterProvider`),
//  so the view only shows the current page and forwards the page turns.
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

/// Drives the reader of one book.
public final class ReaderController: NSObject, ObservableObject, ReadBookDelegate, ReadAloudChapterNavigating {

    /// The book being read.
    @Published public var book: Book
    /// The chapter list.
    @Published public var chapters: [BookChapter]
    /// The state machine.
    public private(set) var readBook: ReadBook

    /// The text of the current page.
    @Published public var pageText: String = ""

    /// The laid-out lines of the current page — upstream `TextPage.textLines`.
    @Published public var pageLines: [TextLine] = []
    /// The offset of every line inside the page text — upstream
    /// `TextPage.getTextStartOffset` (the long press finds the line).
    @Published public var pageLineOffsets: [Int] = []
    /// The title of the current chapter.
    @Published public var chapterTitle: String = ""
    /// The index of the current page inside the chapter.
    @Published public var pageIndex: Int = 0
    /// The number of pages of the current chapter.
    @Published public var pageSize: Int = 0
    /// The index of the current chapter.
    @Published public var chapterIndex: Int = 0
    /// The last error.
    @Published public var errorMessage: String?
    /// Whether the reader is busy.
    @Published public var isLoading = false
    /// The fraction of the page turn that has been travelled (0…1) — upstream
    /// `HorizontalPageDelegate.onDraw` redraws the pages with the offset of
    /// the drag.
    @Published public var pageTurnProgress: Double = 0

    /// The chapter the reader opens at.
    public var startChapterIndex: Int?

    /// The character position the reader opens at — upstream
    /// `ReadBookActivity` restores the position of a bookmark.
    public var startChapterPos: Int?

    /// Whether the system is in dark mode — it decides the night colours of
    /// the reader background (upstream `AppConfig.isNightTheme`).
    public var systemNightMode = false

    /// The background presets of the reader — upstream
    /// `ReadBookConfig.configList` (the styles of the reader).
    public var backgroundPresets: [ReaderBackgroundPreset] {
        environment.backgroundManager.presets
    }

    /// The index of the selected background preset — upstream
    /// `ReadBookConfig.styleSelect` (`PreferKey.readStyleSelect`).
    @Published public var backgroundStyleIndex: Int = 0

    /// The background preset of the reader (upstream `ReadBookConfig.durConfig`).
    ///
    /// The colours belong to the configuration — the upstream keeps them in
    /// the style (`Config.bgStr`, `Config.textColor`, `Config.bgAlpha`), so
    /// they are taken from the configuration and the preset is only the
    /// template of the style.
    public var backgroundPreset: ReaderBackgroundPreset {
        var preset = selectedBackgroundPreset
        preset.bgStr = config.backgroundColor
        preset.bgStrNight = config.backgroundColorNight
        preset.bgStrEInk = config.backgroundColorEInk
        preset.textColor = config.textColor
        preset.textColorNight = config.textColorNight
        preset.textColorEInk = config.textColorEInk
        preset.bgAlpha = config.backgroundAlpha
        return preset
    }

    /// The selected background preset — upstream
    /// `ReadBookConfig.getConfig(styleSelect)`.
    private var selectedBackgroundPreset: ReaderBackgroundPreset {
        let presets = environment.backgroundManager.presets
        guard presets.indices.contains(backgroundStyleIndex) else {
            return environment.backgroundManager.current
        }
        return presets[backgroundStyleIndex]
    }

    /// The display mode of the reader (upstream `AppConfig.isEInkMode`).
    public var displayMode: ReaderDisplayMode {
        ReaderDisplayMode.resolve(
            themeMode: environment.settings.themeMode,
            systemNightMode: systemNightMode
        )
    }

    /// The directory the user backgrounds are stored in (upstream
    /// `<externalFiles>/bg`).
    public var backgroundRoot: URL {
        environment.cacheStorage?.layout.root ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    let environment: AppEnvironment
    private let measurer: TextMeasuring
    private let contentProvider: AppChapterContentProvider

    /// The application model — the reader shows the table of contents of the
    /// running reader (upstream `ReadMenu` opens the chapter list).
    public weak var model: LegadoAppModel?

    /// The read aloud of the reader (upstream `TTSReadAloudService`).
    public let readAloud: ReadAloudService

    /// The auto pager — upstream `ui/book/read/page/AutoPager.kt`.
    public let autoPager: AutoPager

    /// The system integrations of the reader (the keep-screen-on, the
    /// brightness, the orientation — upstream `BaseReadBookActivity.kt`).
    public let system: ReaderSystemIntegration

    /// The lock-screen and headset buttons of the read aloud.
    private var mediaCommands: MediaCommandBridge?

    /// Whether the auto pager is running.
    @Published public var isAutoPaging = false

    /// The progress of the automatic page turn (0…1) — upstream
    /// `AutoPager.onDraw` draws the bar at the bottom of the page.
    @Published public var autoPageProgress: Double = 0

    /// Whether the reader menu is shown.
    @Published public var isMenuPresented = false

    /// The selection of the text — upstream `ContentTextView`.
    public let selection = ReaderSelectionController()

    /// Whether the in-reader search is shown — upstream `SearchMenu`.
    @Published public var isSearchPresented = false

    /// Whether the whole-book content search is shown — upstream
    /// `ReadBookActivity.openSearchActivity` → `SearchContentActivity`.
    @Published public var isContentSearchPresented = false

    /// The keyword the content search starts with.
    @Published public var contentSearchKeyword: String = ""

    /// Whether the table of contents is shown inside the reader — upstream
    /// `ReadMenu` opens the chapter list of the running reader.
    @Published public var isTocPresented = false

    /// The result of the dictionary lookup — upstream `DictDialog`.
    @Published public var dictResult: DictLookupResult?

    /// The word of the dictionary lookup — upstream `DictDialog` (the
    /// argument of the dialog).
    @Published public var dictWord: String?

    /// The rules of the dictionary lookup — one tab per rule.
    @Published public var dictRules: [DictRule] = []

    /// Whether the dictionary dialog is shown.
    @Published public var isDictPresented = false

    /// The binding of the dictionary dialog — the sheet is shown while the
    /// result exists.
    public var dictBinding: Binding<Bool> {
        Binding(
            get: { self.isDictPresented && self.dictResult != nil },
            set: { if !$0 { self.dictResult = nil } }
        )
    }

    /// The pattern of the replace rule of the selection — upstream
    /// `ReplaceEditActivity.startIntent`.
    @Published public var replacePattern: String = ""
    /// The replacement of the replace rule.
    @Published public var replaceReplacement: String = ""
    /// Whether the replace rule sheet is shown.
    @Published public var isReplacePresented = false
    /// The keyword of the in-reader search.
    @Published public var searchKeyword: String = ""
    /// The address of the in-app browser.
    @Published public var browserURL: String = ""
    /// Whether the in-app browser is shown.
    @Published public var isBrowserPresented = false
    /// The shared text.
    @Published public var sharedText: String = ""
    /// Whether the share sheet is shown.
    @Published public var isSharePresented = false

    /// The task that drives the auto pager.
    private var autoPageTask: Task<Void, Never>?

    /// The reader configuration (upstream `ReadBookConfig`).
    @Published public var config: ReaderConfig

    /// The shared layout — upstream `ReadBookConfig.shareConfig`.
    ///
    /// The upstream keeps a second layout next to the current one and uses it
    /// for every background when the "共用布局" switch is on
    /// (`ReadBookConfig.kt:243`).
    @Published public var shareConfig: ReaderConfig

    /// The store of the reader configuration — upstream `ReadBookConfig`
    /// (the preferences of the app).
    ///
    /// The configuration is loaded when the reader opens and saved whenever it
    /// changes, so that the preferences of the reader survive a restart of
    /// the app.
    public let configStore: ReaderConfigStore

    /// The configuration box the state machine reads its configuration from —
    /// the reader settings (the font size, the spacing) change it at runtime.
    private let configBox = ReaderConfigBox()

    /// The box of the page layout — the page size follows the screen.
    private let layoutBox: ReaderLayoutBox

    /// The resolved fonts — upstream `ChapterProvider.getTypeface()`.
    public var resolvedFonts: FontResolver.Resolved {
        FontResolver.resolve(
            textBold: config.textBold,
            textSize: config.textSize,
            titleSize: config.titleSize,
            systemTypeface: environment.settings.systemTypefaces,
            fontPath: environment.settings.string(.fontFolder)
        )
    }

    public init(environment: AppEnvironment, book: Book, chapters: [BookChapter]) {
        self.book = book
        self.chapters = chapters
        self.environment = environment
        self.readAloud = ReadAloudService(
            httpClient: environment.httpClient,
            scriptEngine: environment.scriptEngine
        )
        // The transport notification (the upstream `BaseReadAloudService`
        // posts the read-aloud state with the six media actions).
        self.readAloud.bookName = book.name
        self.readAloud.notificationSink = NotificationService.shared
        // The engine of the book wins over the global one — upstream
        // `ReadAloud.ttsEngine` (`ReadBook.book?.getTtsEngine() ?:
        // AppConfig.ttsEngine`).
        let ttsProfile = TtsEngine.profile(
            of: TtsEngine.resolve(
                bookEngine: TtsEngine.engine(of: book),
                globalEngine: environment.settings.ttsEngine
            ),
            store: environment.store
        )
        self.readAloud.useHttpTts(ttsProfile)
        // The audio of the HTTP TTS engine is cached — upstream
        // `cacheDir/httpTTS`.
        self.readAloud.cacheRoot = try? LocalFileStore.cachesDirectory()
        // The stored login header of the profile — upstream
        // `AnalyzeUrl(source = httpTts)`.
        if let ttsProfile {
            self.readAloud.loginHeaderMap = try? environment.loginService.loginHeaderMap(for: ttsProfile.key)
        }
        self.readAloud.ttsSpeechRate = environment.settings.ttsSpeechRate
        self.readAloud.onError = { message in
            AppLog.shared.put(message)
        }
        self.readAloud.refreshHttpTtsSettings()
        self.autoPager = AutoPager(
            configuration: AutoPager.Configuration(
                speed: environment.settings.autoReadSpeed,
                mode: .pageTurn
            )
        )
        self.system = ReaderSystemIntegration(settings: environment.settings)
        #if canImport(UIKit) && !os(watchOS)
        // On iOS the real font metrics are used — the counterpart of the
        // upstream `TextMeasure` (Android's `Paint` + `StaticLayout`).
        let box = configBox
        let settings = environment.settings
        let measurer: TextMeasuring = CoreTextMeasurer { style in
            let config = box.config
            let resolved = FontResolver.resolve(
                textBold: config.textBold,
                textSize: config.textSize,
                titleSize: config.titleSize,
                systemTypeface: settings.systemTypefaces,
                fontPath: settings.string(.fontFolder)
            )
            let descriptor = style == config.titleStyle ? resolved.title : resolved.body
            return descriptor.uiFont(size: style.fontSize, bold: style.isBold)
        }
        #else
        let measurer: TextMeasuring = ApproximateTextMeasurer()
        #endif
        self.measurer = measurer
        self.contentProvider = AppChapterContentProvider(environment: environment)
        // The configuration of the reader is a preference of the app (the
        // upstream `ReadBookConfig`) — it is loaded from the settings, so the
        // reader opens with the preferences of the user.
        let store = ReaderConfigStore(settings: environment.settings)
        self.configStore = store
        var config = store.load()
        // The colours of the style are the default of the configuration — the
        // upstream keeps them in the style (`ReadBookConfig.durConfig`).
        let preset = environment.backgroundManager.current
        if !store.hasValue(for: .bgStr) {
            config.backgroundColor = preset.bgStr
            config.backgroundColorNight = preset.bgStrNight
            config.backgroundColorEInk = preset.bgStrEInk
        }
        if !store.hasValue(for: .textColor) {
            config.textColor = preset.textColor
            config.textColorNight = preset.textColorNight
            config.textColorEInk = preset.textColorEInk
        }
        self.config = config
        configBox.config = config
        // The shared layout — upstream `ReadBookConfig.shareConfig`.
        self.shareConfig = store.loadShare()
        // The selected style of the reader — upstream
        // `ReadBookConfig.styleSelect` (`PreferKey.readStyleSelect`).
        if environment.backgroundManager.presets.indices.contains(config.styleIndex) {
            environment.backgroundManager.select(index: config.styleIndex)
        }
        self.backgroundStyleIndex = environment.backgroundManager.selectedIndex
        let layout = ReaderLayout(
            config: config,
            size: CGSizeLike(width: 400, height: 700),
            measurer: measurer
        )
        let layoutBox = ReaderLayoutBox(layout: layout)
        self.layoutBox = layoutBox
        self.readBook = ReadBook(
            book: book,
            chapterList: chapters,
            contentProvider: AppChapterContentProvider(environment: environment),
            measurer: measurer,
            scriptEngine: environment.scriptEngine,
            titleRules: (try? environment.store.replaceRulesForTitle(name: book.name, origin: book.origin)) ?? [],
            contentRules: (try? environment.store.replaceRulesForContent(name: book.name, origin: book.origin)) ?? [],
            configProvider: { [configBox] in configBox.config },
            layoutProvider: { [layoutBox] in layoutBox.layout },
            // Upstream `PreferKey.preDownloadNum` — the number of chapters
            // that are prefetched after the current one.
            preDownloadCount: environment.settings.preDownloadNumber,
            chineseConversionMode: ChineseConversionMode(
                rawValue: environment.settings.chineseConverterType
            ) ?? .off
        )
        super.init()
        readBook.delegate = self
        readBook.persister = StoreProgressPersister(store: environment.store)
        // Upstream `BaseReadAloudService.nextChapter()` / `prevP()` move the
        // read aloud from one chapter to the next.
        readAloud.controller.chapterNavigator = self
    }

    // MARK: - Actions

    /// Opens the reader.
    public func start() async {
        isLoading = true
        if let index = startChapterIndex, chapters.indices.contains(index) {
            await readBook.openChapter(index: index, position: startChapterPos ?? 0)
        } else {
            await readBook.loadCurrentChapter()
        }
        isLoading = false
        // The upstream syncs the reading progress with the WebDAV server when
        // a book is opened (`ReadBookViewModel.initBook` → the
        // `syncBookProgressPlus` path).
        await syncProgressOnOpen()
    }

    /// Syncs the reading progress with the WebDAV server when the book is
    /// opened — upstream `ReadBookViewModel.initBook` (the `syncBookProgressPlus`
    /// path) → `ReadBook.syncProgress`.
    ///
    /// The upstream gates the whole exchange with `AppConfig.syncBookProgress`
    /// and only runs it on open when `syncBookProgressPlus` is on: the local
    /// progress is uploaded when the server has none or an older one, and the
    /// user is asked when the server is further into the book.
    public func syncProgressOnOpen() async {
        let settings = environment.settings
        guard settings.syncBookProgress, settings.syncBookProgressPlus else { return }
        guard let service = webDavService() else { return }
        let local = BookProgress(book: book)
        let remote: BookProgress
        do {
            remote = try await service.downloadProgress(fileName: local.fileName)
        } catch {
            // The server has no progress for this book — the upstream uploads
            // the local one.
            do {
                try await service.uploadProgress(local)
                progressMessage = "已同步阅读进度"
            } catch {
                AppLog.shared.put("上传阅读进度失败", error: error)
            }
            return
        }
        let outcome = BookProgressSync.resolve(
            remote: remote,
            local: local,
            totalChapters: Int(book.simulatedTotalChapterNum())
        )
        switch outcome {
        case .same:
            break
        case .remoteOlder:
            do {
                try await service.uploadProgress(local)
                progressMessage = "已同步阅读进度"
            } catch {
                AppLog.shared.put("上传阅读进度失败", error: error)
            }
        case .remoteNewer(let progress):
            // The server is further into the book — the upstream asks the
            // user whether the local progress should be overwritten.
            pendingRemoteProgress = progress
        case .beyondTheBook:
            break
        }
    }

    /// The size of the page changed — the device was rotated or the window
    /// was resized.
    ///
    /// The layout is computed again and the current chapter is laid out again,
    /// keeping the reading position (upstream `ChapterProvider.upStyle` is
    /// called again when the screen changes).
    public func updatePageSize(_ size: CGSizeLike) {
        guard size.width > 0, size.height > 0 else { return }
        let current = layoutBox.layout
        guard current.viewWidth != size.width || current.viewHeight != size.height else { return }
        layoutBox.layout = ReaderLayout(
            config: config,
            size: size,
            measurer: measurer
        )
        Task { await readBook.reloadCurrentChapter() }
    }

    /// Goes to the next page, crossing into the next chapter when needed.
    public func nextPage() async {
        guard let chapter = readBook.curTextChapter else { return }
        pageTurnDirection = .next
        if readBook.pageIndex + 1 < chapter.pageSize {
            readBook.updatePageIndex(readBook.pageIndex + 1)
            refreshPage()
        } else if await readBook.moveToNextChapter() {
            refreshPage()
        } else {
            // The end of the book — the upstream checks for new chapters
            // here (`ReadBook.upToc`).
            await checkForNewChapters()
            await readBook.saveRead(pageChanged: false)
        }
    }

    /// Checks whether the book has new chapters — upstream `ReadBook.upToc()`.
    public func checkForNewChapters() async {        let environment = self.environment
        let refreshed = await readBook.checkForNewChapters { book in
            guard let source = try? environment.source(for: book) else { return [] }
            let result = try await WebBook.getChapterList(
                bookSource: source,
                book: book,
                dependencies: environment.dependencies()
            )
            return result.chapters
        }
        if let refreshed, refreshed > chapters.count {
            refreshPage()
        }
    }

    /// Applies a new table of contents rule — upstream
    /// `ReadBookActivity.onTocRegexDialogResult` (`it.tocUrl = tocRegex` +
    /// `loadChapterList(it)`).
    public func applyTocRegex(_ rule: String) async {
        var changed = book
        changed.tocUrl = rule
        try? environment.store.update(changed)
        book = changed
        guard let fileURL = model?.localImporter?.fileURL(for: book) else {
            errorMessage = "找不到本地文件"
            return
        }
        do {
            let result = try TocOperations.reparse(
                book: book,
                rule: rule,
                fileURL: fileURL,
                splitLongChapter: book.readConfigBox.splitLongChapter
            )
            try? environment.store.deleteChapters(bookUrl: book.bookUrl)
            try? environment.store.insert(result.chapters)
            chapters = result.chapters
            await readBook.replaceChapterList(result.chapters)
            refreshPage()
        } catch {
            errorMessage = "目录规则无效"
        }
    }

    /// Goes to the previous page, crossing into the previous chapter when needed.
    public func previousPage() async {
        pageTurnDirection = .previous
        if readBook.pageIndex > 0 {
            readBook.updatePageIndex(readBook.pageIndex - 1)
            refreshPage()
        } else if await readBook.moveToPrevChapter() {
            refreshPage()
        }
    }

    /// The progress of the book, 0…1.
    public var progress: Double { readBook.progress }

    /// The values the header and the footer tips are rendered from —
    /// upstream `PageView.setProgress` (the tip context of the page).
    public var tipContext: ReaderTipContext {
        ReaderTipContext(
            bookName: book.name,
            chapterTitle: chapterTitle,
            pageIndex: pageIndex,
            pageSize: pageSize,
            chapterIndex: chapterIndex,
            chapterSize: chapters.count,
            readProgress: ReaderTipRenderer.readProgress(
                chapterIndex: chapterIndex,
                chapterSize: chapters.count,
                pageIndex: pageIndex,
                pageSize: pageSize
            ),
            isChapterCompleted: isChapterCompleted,
            time: Date(),
            batteryLevel: ReaderBattery.level
        )
    }

    /// Whether the chapter on the screen is completely read — upstream
    /// `PageView.upChapterCompleted`.
    public var isChapterCompleted: Bool {
        pageSize > 0 && pageIndex >= pageSize - 1
    }

    // MARK: - The reader settings

    /// Changes the reader configuration and lays the chapter out again —
    /// upstream `ReadBookActivity` re-reads the configuration when the font
    /// size or the spacing changes.
    ///
    /// The configuration is saved — the upstream saves the style when the
    /// dialog is closed (`ReadStyleDialog.kt:66`: `ReadBookConfig.save()`).
    public func updateReaderStyle(_ mutate: (inout ReaderConfig) -> Void) async {
        // Upstream `ReadBookConfig.config get() = if (shareLayout) shareConfig
        // else durConfig` — the change is written into the layout that is in
        // use.
        if shareLayoutEnabled {
            var shared = shareConfig
            mutate(&shared)
            shareConfig = shared
            configStore.saveShare(shared)
            await applyEffectiveLayout()
            return
        }
        var updated = config
        mutate(&updated)
        config = updated
        configBox.config = updated
        configStore.save(updated)
        await readBook.openChapter(index: readBook.durChapterIndex)
        refreshPage()
    }

    /// Applies the reader settings — upstream `MoreConfigDialog` and
    /// `ReadStyleDialog`: the configuration is saved and the page is laid out
    /// again.
    public func applyReaderSettings(_ mutate: (inout ReaderConfig) -> Void) async {
        await updateReaderStyle(mutate)
    }

    // MARK: - The shared layout

    /// Whether the shared layout is used — upstream
    /// `ReadBookConfig.shareLayout` (the "共用布局" switch of the style
    /// dialog).
    public var shareLayoutEnabled: Bool {
        environment.settings.shareLayout
    }

    /// The layout that the reader uses — upstream
    /// `ReadBookConfig.config get() = if (shareLayout) shareConfig else durConfig`.
    public var effectiveConfig: ReaderConfig {
        ShareLayout.effective(
            current: config,
            share: shareConfig,
            enabled: shareLayoutEnabled
        )
    }

    /// The layout that is used for a share — upstream
    /// `ReadBookConfig.getExportConfig()`.
    public var exportConfig: ReaderConfig {
        ShareLayout.exportConfig(
            current: config,
            share: shareConfig,
            enabled: shareLayoutEnabled
        )
    }

    /// Turns the shared layout on or off — upstream `ReadBookConfig.shareLayout`.
    ///
    /// The upstream reads the switch while the style dialog is open
    /// (`ReadStyleDialog.kt`); the port writes the preference and lays the
    /// chapter out again.
    public func setShareLayout(_ enabled: Bool) async {
        environment.settings.shareLayout = enabled
        await applyEffectiveLayout()
    }

    /// Applies the layout that is in use — upstream
    /// `ReadBookConfig.config`.
    private func applyEffectiveLayout() async {
        let effective = effectiveConfig
        configBox.config = effective
        await readBook.openChapter(index: readBook.durChapterIndex)
        refreshPage()
    }

    /// Saves the shared layout — upstream `ReadBookConfig.save()` writes the
    /// share configuration next to the current one.
    public func saveShareLayout(_ layout: ReaderConfig) async {
        shareConfig = layout
        configStore.saveShare(layout)
        if shareLayoutEnabled {
            await applyEffectiveLayout()
        }
    }

    /// Selects a background preset — upstream
    /// `ReadBookConfig.changeBgTextConfig` (the style of the reader).
    ///
    /// The colours of the preset become the colours of the configuration —
    /// the upstream styles *are* the configurations
    /// (`ReadBookConfig.Config`).
    public func selectBackgroundPreset(index: Int) async {
        guard environment.backgroundManager.presets.indices.contains(index) else { return }
        environment.backgroundManager.select(index: index)
        environment.backgroundManager.save()
        backgroundStyleIndex = index
        let preset = environment.backgroundManager.presets[index]
        await updateReaderStyle { config in
            config.styleIndex = index
            config.backgroundColor = preset.bgStr
            config.backgroundColorNight = preset.bgStrNight
            config.backgroundColorEInk = preset.bgStrEInk
            config.textColor = preset.textColor
            config.textColorNight = preset.textColorNight
            config.textColorEInk = preset.textColorEInk
            config.backgroundAlpha = preset.bgAlpha
        }
    }

    /// Changes the Chinese converter — upstream `ReadStyleDialog.kt:110`:
    /// the converter is unloaded and the content is laid out again.
    public func setChineseConverter(_ mode: ChineseConversionMode) async {
        configStore.chineseConverterType = mode.rawValue
        environment.settings.chineseConverterType = mode.rawValue
        readBook.chineseConversionMode = mode
        await readBook.reloadCurrentChapter()
        refreshPage()
    }

    /// Jumps to a page of the current chapter — upstream `setSeekPage`.
    public func jump(toPage index: Int) {
        guard let chapter = readBook.curTextChapter else { return }
        let clamped = max(0, min(index, max(0, chapter.pageSize - 1)))
        readBook.updatePageIndex(clamped)
        refreshPage()
    }

    /// Jumps to a chapter — upstream `skipToChapter`.
    public func jump(toChapter index: Int) async {
        guard chapters.indices.contains(index) else { return }
        await readBook.openChapter(index: index)
        refreshPage()
    }

    /// Jumps to a character position of a chapter — upstream
    /// `ReadBookActivity.navigateToSearch` (the in-reader search).
    public func jump(toChapter index: Int, position: Int) async {
        guard chapters.indices.contains(index) else { return }
        await readBook.openChapter(index: index, position: position)
        refreshPage()
    }

    // MARK: - The auto pager

    /// Starts the auto pager — upstream `AutoPager.start()`.
    public func startAutoPage() {
        guard !isAutoPaging else { return }
        isAutoPaging = true
        // Upstream `AutoPager.start()`: the E-Ink mode turns the whole page
        // after the interval, the normal mode fills the progress of the page
        // and the scroll page animation scrolls the content.
        var configuration = autoPager.configuration
        if environment.settings.isEInkMode {
            configuration.mode = .pageTurn
        } else if pageTurnStyle == .scroll {
            configuration.mode = .scroll
        } else {
            configuration.mode = .progress
        }
        autoPager.configuration = configuration
        autoPager.onTurn = { [weak self] direction in
            guard let self else { return false }
            Task { await self.nextPage() }
            return true
        }
        autoPager.onScroll = { [weak self] progress in
            self?.autoPageProgress = progress
        }
        autoPager.start()
        scheduleAutoPageTick()
    }

    /// Stops the auto pager — upstream `AutoPager.stop()`.
    public func stopAutoPage() {
        isAutoPaging = false
        autoPager.stop()
        autoPageProgress = 0
        autoPageTask?.cancel()
        autoPageTask = nil
    }

    /// Toggles the auto pager.
    public func toggleAutoPage() {
        if isAutoPaging {
            stopAutoPage()
        } else {
            startAutoPage()
        }
    }

    /// Schedules the next tick of the auto pager.
    ///
    /// The E-Ink mode turns the page after the whole interval (the upstream
    /// `postDelayed`), the other modes are ticked often so that the progress
    /// of the page grows smoothly (the upstream computes the offset on every
    /// draw).
    private func scheduleAutoPageTick() {
        autoPageTask?.cancel()
        let mode = autoPager.configuration.mode
        let interval: UInt64 = mode == .pageTurn
            ? UInt64(autoPager.speed) * 1_000_000_000
            : 50_000_000
        autoPageTask = Task { [weak self] in
            var last = Date()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                guard let self, self.isAutoPaging else { return }
                let now = Date()
                let elapsed = now.timeIntervalSince(last)
                last = now
                self.autoPager.tick(
                    elapsed: elapsed,
                    pageHeight: self.layoutBox.layout.viewHeight
                )
            }
        }
    }

    /// The page-turn animation style — upstream `ReadBookConfig.pageAnim`.
    ///
    /// The upstream stores the animation in the configuration of the reader
    /// (`ReadBookConfig.kt:548`: `pageAnim = 0`, the cover animation).
    public var pageTurnStyle: PageTurnStyle {
        PageTurnStyle(rawValue: config.pageAnim) ?? .cover
    }

    /// Changes the page-turn animation — upstream `ReadStyleDialog` (the
    /// "翻页动画" picker writes `ReadBookConfig.pageAnim`).
    public func setPageTurnStyle(_ style: PageTurnStyle) {
        Task { await updateReaderStyle { $0.pageAnim = style.rawValue } }
    }

    /// The direction of the last page turn — the reader animates the page
    /// that is being left behind.
    public var pageTurnDirection: PageTurnDirection = .next

    /// The laid-out lines of the page that the turn reveals — the next page
    /// when the page is turned forward, the previous page otherwise.
    ///
    /// The upstream draws the revealed page under the page that is turned
    /// away (`CoverPageDelegate.onDraw` → `nextRecorder.draw`); the port does
    /// the same.
    public var revealedPageLines: [TextLine] {
        guard let chapter = readBook.curTextChapter else { return [] }
        switch pageTurnDirection {
        case .next:
            let index = readBook.pageIndex + 1
            guard index < chapter.pageSize else { return [] }
            return chapter.page(at: index)?.lines ?? []
        case .previous:
            let index = readBook.pageIndex - 1
            guard index >= 0 else { return [] }
            return chapter.page(at: index)?.lines ?? []
        }
    }

    /// Starts the read aloud of the current chapter.
    ///
    /// Upstream `ReadAloud.play(pageIndex, startPos)` reads the chapter that
    /// is on screen; the spoken unit is the paragraph — or the page when
    /// 按页朗读 (`PreferKey.readAloudByPage`) is on.
    public func startReadAloud() async {
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        let paragraphs = await readAloudUnits(for: chapter, index: index)
        guard !paragraphs.isEmpty else { return }
        readAloud.chapterTitle = chapter.title
        readAloud.play(
            paragraphs: paragraphs,
            chapterIndex: index,
            startIndex: readAloudStartIndex(paragraphs: paragraphs)
        )
        preDownloadNextChapterAudio()
    }

    /// Downloads the audio of the next chapter — upstream `preDownloadAudios`.
    ///
    /// The first ten paragraphs of the next chapter are fetched while the
    /// current one is spoken.
    private func preDownloadNextChapterAudio() {
        guard readAloud.httpTts != nil else { return }
        let nextIndex = readBook.durChapterIndex + 1
        guard chapters.indices.contains(nextIndex) else { return }
        let chapter = chapters[nextIndex]
        Task { [weak self] in
            guard let self else { return }
            let units = await self.readAloudUnits(for: chapter, index: nextIndex)
            guard !units.isEmpty else { return }
            self.readAloud.preDownloadNextChapter(
                paragraphs: units.map(\.text),
                chapterTitle: chapter.title
            )
        }
    }

    /// The spoken units of a chapter.
    ///
    /// With 按页朗读 (`PreferKey.readAloudByPage`) the unit is the page — the
    /// upstream `textChapter.getNeedReadAloud(0, readAloudByPage, 0)` — else it
    /// is the paragraph.
    public func readAloudUnits(for chapter: BookChapter, index: Int) async -> [ReadAloudParagraph] {
        if environment.settings.readAloudByPage {
            if let laidOut = readBook.curTextChapter, laidOut.chapter.bookUrl == chapter.bookUrl {
                let pages = ReadAloudSplitter.pageParagraphs(in: laidOut)
                if !pages.isEmpty { return pages }
            }
        }
        guard let content = try? await contentProvider.chapterContent(book: book, chapter: chapter),
              !content.isEmpty else {
            return []
        }
        return ReadAloudSplitter.paragraphs(in: content)
    }

    /// The index of the spoken unit the read aloud starts at.
    ///
    /// Upstream `BaseReadAloudService.newReadAloud(play, pageIndex, startPos)`
    /// continues at the position the reader is on; the port starts at the
    /// paragraph that holds the current reading position.
    private func readAloudStartIndex(paragraphs: [ReadAloudParagraph]) -> Int {
        guard !paragraphs.isEmpty else { return 0 }
        guard let position = currentReadAloudPosition() else { return 0 }
        let index = paragraphs.firstIndex { $0.start <= position && position < $0.end }
        return index ?? 0
    }

    /// The character offset the reader is on — upstream `ReadBook.durChapterPos`.
    private func currentReadAloudPosition() -> Int? {
        guard let chapter = readBook.curTextChapter else { return nil }
        let pageIndex = readBook.pageIndex
        guard let page = chapter.page(at: pageIndex) else { return nil }
        return page.chapterPosition
    }

    // MARK: - The chapter navigation of the read aloud

    /// Moves the read aloud to the next chapter — upstream
    /// `BaseReadAloudService.nextChapter()`.
    public func readAloudNextChapter(completion: @escaping (ReadAloudChapter?) -> Void) {
        Task { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            guard await self.readBook.moveToNextChapter() else {
                completion(nil)
                return
            }
            completion(await self.readAloudChapterPayload())
        }
    }

    /// Moves the read aloud to the previous chapter — upstream
    /// `BaseReadAloudService.prevP()` (the last paragraph of that chapter).
    public func readAloudPreviousChapter(completion: @escaping (ReadAloudChapter?) -> Void) {
        Task { [weak self] in
            guard let self else {
                completion(nil)
                return
            }
            guard await self.readBook.moveToPrevChapter() else {
                completion(nil)
                return
            }
            completion(await self.readAloudChapterPayload())
        }
    }

    /// The spoken units of the chapter the reader is on.
    private func readAloudChapterPayload() async -> ReadAloudChapter? {
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return nil }
        let chapter = chapters[index]
        let units = await readAloudUnits(for: chapter, index: index)
        guard !units.isEmpty else { return nil }
        readAloud.chapterTitle = chapter.title
        return ReadAloudChapter(chapterIndex: index, paragraphs: units)
    }

    /// Highlights the paragraph that is being read — upstream
    /// `ReadBookActivity.observeEventSticky(EventBus.TTS_PROGRESS)`: the page
    /// that holds the spoken paragraph is highlighted with the accent colour
    /// (`TextColumn.draw`), and the reading position follows the speech.
    public func updateReadAloudHighlight() {
        guard let chapter = readBook.curTextChapter else { return }
        // Upstream `TextPage.removePageAloudSpan()` — only one paragraph is
        // highlighted at a time.
        for page in chapter.pages {
            page.removePageAloudSpan()
        }
        guard let paragraph = readAloud.currentParagraph else {
            refreshPage()
            return
        }
        let offset = paragraph.start
        let pageIndex = ReadAloudPosition.pageIndex(forChapterOffset: offset, in: chapter)
        guard chapter.pages.indices.contains(pageIndex) else { return }
        let spanStart = ReadAloudPosition.aloudSpanStart(chapterOffset: offset, in: chapter)
        chapter.pages[pageIndex].updatePageAloudSpan(aloudSpanStart: spanStart)
        // The reader follows the spoken paragraph.
        readBook.moveToPosition(offset)
        refreshPage()
    }

    private func refreshPage() {
        guard let chapter = readBook.curTextChapter else { return }
        let index = min(max(0, readBook.pageIndex), max(0, chapter.pageSize - 1))
        if chapter.pages.indices.contains(index) {
            let page = chapter.pages[index]
            pageText = page.text
            // The laid-out lines of the page — the upstream draws them on a
            // canvas, the port renders them with SwiftUI.
            pageLines = page.lines
            pageLineOffsets = page.lineOffsets
        } else {
            pageText = ""
            pageLines = []
            pageLineOffsets = []
        }
        pageIndex = index
        pageSize = chapter.pageSize
        chapterIndex = readBook.durChapterIndex
        chapterTitle = readBook.durChapterTitle
        readAloud.chapterTitle = chapterTitle
    }

    // MARK: - The continuous-scroll reading mode

    /// The page offset of the continuous scroll — upstream
    /// `ContentTextView.pageOffset` (0 = the top of the current page).
    @Published public var scrollOffset: Double = 0

    /// The height of a page's content — upstream `TextPage.height`
    /// (the bottom of the last line).
    private func scrollPageHeight(_ page: TextPage) -> Double {
        page.lines.last?.lineBottom ?? page.height
    }

    /// The pages that are drawn in the continuous-scroll mode — upstream
    /// `ContentTextView.drawPage` (the current page, the next page and the
    /// page after that when it is visible).
    public var scrollPages: [ReaderScrollPage] {
        guard let chapter = readBook.curTextChapter else { return [] }
        let index = min(max(0, readBook.pageIndex), max(0, chapter.pageSize - 1))
        guard chapter.pages.indices.contains(index) else { return [] }
        let current = chapter.pages[index]
        let next = chapter.pages.indices.contains(index + 1) ? chapter.pages[index + 1] : nil
        let nextPlus = chapter.pages.indices.contains(index + 2) ? chapter.pages[index + 2] : nil
        let offsets = ScrollPageMode.stackedPages(
            offset: scrollOffset,
            currentHeight: scrollPageHeight(current),
            nextHeight: next.map(scrollPageHeight) ?? 0,
            hasNext: next != nil,
            hasNextPlus: nextPlus != nil,
            nextPlusHeight: nextPlus.map(scrollPageHeight) ?? 0,
            visibleHeight: layoutBox.layout.viewHeight
        )
        return offsets.compactMap { item in
            guard chapter.pages.indices.contains(index + item.index) else { return nil }
            let page = chapter.pages[index + item.index]
            return ReaderScrollPage(index: item.index, lines: page.lines, offset: item.offset)
        }
    }

    /// Scrolls the content — upstream `ContentTextView.scroll(mOffset)`.
    ///
    /// When the offset leaves the current page the reader moves to the
    /// previous or the next page (the upstream's `pageFactory.moveToPrev` /
    /// `moveToNext`).
    public func scroll(by delta: Double) {
        guard let chapter = readBook.curTextChapter else { return }
        let index = min(max(0, readBook.pageIndex), max(0, chapter.pageSize - 1))
        guard chapter.pages.indices.contains(index) else { return }
        let current = chapter.pages[index]
        let result = ScrollPageMode.scroll(
            offset: scrollOffset,
            delta: delta,
            pageHeight: scrollPageHeight(current),
            visibleHeight: layoutBox.layout.viewHeight,
            hasPrevious: index > 0,
            hasNext: chapter.pages.indices.contains(index + 1)
        )
        scrollOffset = result.offset
        switch result.pageDelta {
        case -1:
            if index > 0 {
                readBook.updatePageIndex(index - 1)
                refreshPage()
            } else {
                // The first page of the chapter — the upstream's `moveToPrev`
                // continues in the previous chapter.
                Task {
                    if await readBook.moveToPrevChapter() {
                        refreshPage()
                    }
                }
            }
        case 1:
            if chapter.pages.indices.contains(index + 1) {
                readBook.updatePageIndex(index + 1)
                refreshPage()
            } else {
                // The last page of the chapter — the upstream's `moveToNext`
                // continues in the next chapter.
                Task {
                    if await readBook.moveToNextChapter() {
                        refreshPage()
                    }
                }
            }
        default:
            break
        }
    }

    /// The tap that turns the page in the continuous-scroll mode — upstream
    /// `ScrollPageDelegate.nextPageByAnim` → `calcNextPageOffset`.
    ///
    /// The tap scrolls by one line, so the last line of the page stays
    /// visible; a book of images scrolls by the whole visible height.
    public func scrollToNextPage() {
        guard let chapter = readBook.curTextChapter else { return }
        let index = min(max(0, readBook.pageIndex), max(0, chapter.pageSize - 1))
        guard chapter.pages.indices.contains(index) else { return }
        let current = chapter.pages[index]
        let offset = ScrollPageMode.nextOffset(
            lastLineTop: current.lines.last?.lineTop ?? 0,
            paddingTop: current.paddingTop,
            visibleHeight: layoutBox.layout.viewHeight,
            isImage: book.isImage,
            hasImageOrEmpty: current.hasImageOrEmpty(),
            isTextStyle: imageStyle == .text
        )
        scroll(by: offset)
    }

    /// The tap that turns the page back — upstream
    /// `ScrollPageDelegate.prevPageByAnim` → `calcPrevPageOffset`.
    public func scrollToPreviousPage() {
        guard let chapter = readBook.curTextChapter else { return }
        let index = min(max(0, readBook.pageIndex), max(0, chapter.pageSize - 1))
        guard chapter.pages.indices.contains(index) else { return }
        let current = chapter.pages[index]
        let offset = ScrollPageMode.previousOffset(
            firstLineBottom: current.lines.first?.lineBottom ?? 0,
            paddingTop: current.paddingTop,
            visibleHeight: layoutBox.layout.viewHeight,
            isImage: book.isImage,
            hasImageOrEmpty: current.hasImageOrEmpty(),
            isTextStyle: imageStyle == .text
        )
        scroll(by: offset)
    }

    /// Resets the scroll offset — the upstream resets it when the content is
    /// set (`ContentTextView.resetPageOffset`).
    public func resetScrollOffset() {
        scrollOffset = 0
    }

    /// The last vertical translation of the scroll gesture — the delta of the
    /// drag is the difference to the previous event (upstream
    /// `ScrollPageDelegate.onScroll` uses `touchY - lastY`).
    public var lastScrollTranslation: Double = 0

    /// The vertical drag of the continuous-scroll mode.
    public func scrollDragChanged(translation: Double) {
        let delta = translation - lastScrollTranslation
        lastScrollTranslation = translation
        scroll(by: delta)
    }

    /// The scroll drag ended — the next drag starts from zero.
    public func scrollDragEnded() {
        lastScrollTranslation = 0
    }

    /// Registers the lock-screen and headset buttons — the upstream
    /// `receiver/MediaButtonReceiver.kt` registers the same six actions with
    /// the Android media session.
    public func activateMediaCommands() {
        let bridge = MediaCommandBridge()
        // Upstream `mediaButtonPerNext` — the media buttons skip a paragraph
        // instead of a chapter when it is on.
        bridge.perNext = environment.settings.bool(.mediaButtonPerNext, default: false)
        bridge.onPreviousChapter = { [weak self] in
            Task { await self?.readBook.moveToPrevChapter() }
        }
        bridge.onNextChapter = { [weak self] in
            Task { await self?.readBook.moveToNextChapter() }
        }
        bridge.onPreviousParagraph = { [weak self] in
            self?.readAloud.previousParagraph()
        }
        bridge.onNextParagraph = { [weak self] in
            self?.readAloud.nextParagraph()
        }
        bridge.onTogglePlayPause = { [weak self] in
            self?.toggleReadAloud()
        }
        bridge.onStop = { [weak self] in
            self?.readAloud.stop()
        }
        mediaCommands = bridge
        // The buttons of the transport notification do the same — upstream
        // `BaseReadAloudService` handles the six actions of the notification.
        NotificationService.shared.actionHandler = { [weak self] identifier in
            guard let self else { return }
            switch identifier {
            case "prevChapter":
                Task { await self.readBook.moveToPrevChapter() }
            case "prevParagraph":
                self.readAloud.previousParagraph()
            case "toggle":
                self.toggleReadAloud()
            case "nextParagraph":
                self.readAloud.nextParagraph()
            case "nextChapter":
                Task { await self.readBook.moveToNextChapter() }
            case "stop":
                self.readAloud.stop()
            default:
                break
            }
        }
    }

    /// Removes the lock-screen and headset buttons.
    public func deactivateMediaCommands() {
        mediaCommands?.clearNowPlaying()
        mediaCommands = nil
        NotificationService.shared.actionHandler = nil
    }

    /// Pauses or continues the read aloud.
    public func toggleReadAloud() {
        if readAloud.state == .playing {
            readAloud.pause()
        } else if readAloud.state == .paused {
            readAloud.resume()
        }
    }

    /// Runs a click action — the port of the upstream `ReadView.click(action)`.
    public func performClickAction(_ action: ClickAction) {        switch action {
        case .noAction:
            break
        case .menu:
            isMenuPresented = true
        case .nextPage:
            // The continuous-scroll mode scrolls instead of turning the page
            // — upstream `ScrollPageDelegate.nextPageByAnim`.
            if pageTurnStyle == .scroll {
                scrollToNextPage()
            } else {
                Task { await nextPage() }
            }
        case .prevPage:
            if pageTurnStyle == .scroll {
                scrollToPreviousPage()
            } else {
                Task { await previousPage() }
            }
        case .nextChapter:
            Task { await readBook.moveToNextChapter() }
        case .prevChapter:
            Task { await readBook.moveToPrevChapter() }
        case .prevParagraph:
            readAloud.previousParagraph()
        case .nextParagraph:
            readAloud.nextParagraph()
        case .addBookmark:
            Task { await addBookmark() }
        case .editContent:
            isContentEditPresented = true
        case .toggleReplaceRule:
            toggleReplaceRule()
        case .chapterList:
            isTocPresented = true
        case .searchContent:
            isSearchPresented = true
        case .syncProgress:
            Task { await readBook.saveRead(pageChanged: false) }
        case .pauseResumeReadAloud:
            if readAloud.state == .playing {
                readAloud.pause()
            } else if readAloud.state == .paused {
                readAloud.resume()
            }
        }
    }

    /// Adds a bookmark for the current chapter — upstream `ReadBookActivity`.
    public func addCurrentBookmark() async {
        await addBookmark()
    }

    /// The replace rules that are applied to the current chapter — upstream
    /// `ReadBookActivity.menu_effectiveReplaceRules`.
    public var effectiveReplaceRules: [ReplaceRule] {
        readBook.curTextChapter?.effectiveReplaceRules ?? []
    }

    /// The bookmark that is edited — upstream `ReadBookActivity.menu_bookmark`
    /// → `showDialogFragment(BookmarkDialog(bookmark))`.
    @Published public var pendingBookmark: Bookmark?

    private func addBookmark() async {
        let chapter = chapters.indices.contains(readBook.durChapterIndex)
            ? chapters[readBook.durChapterIndex]
            : nil
        guard let chapter else { return }
        let bookmark = Bookmark(
            time: Int64(Date().timeIntervalSince1970),
            bookName: book.name,
            bookAuthor: book.author,
            chapterIndex: Int64(readBook.durChapterIndex),
            chapterPos: Int64(readBook.durChapterPos),
            chapterName: chapter.title,
            bookText: chapter.title,
            content: chapter.url
        )
        pendingBookmark = bookmark
    }

    /// Adds a bookmark for the selected text — upstream
    /// `ReadBookActivity.createBookmark` (the selection is the bookmark text).
    public func addBookmark(selectedText: String) {
        let chapter = chapters.indices.contains(readBook.durChapterIndex)
            ? chapters[readBook.durChapterIndex]
            : nil
        guard let chapter else { return }
        let bookmark = Bookmark(
            time: Int64(Date().timeIntervalSince1970),
            bookName: book.name,
            bookAuthor: book.author,
            chapterIndex: Int64(readBook.durChapterIndex),
            chapterPos: Int64(readBook.durChapterPos),
            chapterName: chapter.title,
            bookText: selectedText.isEmpty ? chapter.title : selectedText,
            content: selectedText.isEmpty ? chapter.url : selectedText
        )
        pendingBookmark = bookmark
    }

    /// Toggles the replace rules of the book — upstream
    /// `ReadBookActivity.changeReplaceRuleState` (the "启用替换净化" switch).
    public func toggleReplaceRule() {
        var changed = book
        changed.useReplaceRule = !changed.useReplaceRule
        try? environment.store.update(changed)
        Task { await readBook.openChapter(index: readBook.durChapterIndex) }
        refreshPage()
    }

    // MARK: - The upstream top bar options

    /// Saves the simulated reading — upstream
    /// `BaseReadBookActivity.showSimulatedReading()`.
    public func setSimulatedReading(_ config: BookReadConfig) {
        var changed = book
        changed.readConfigBox = config
        try? environment.store.update(changed)
        reloadContent()
    }

    /// Sets the character set of a local book — upstream
    /// `ReadBook.setCharset(it)` (the "切换编码" option).
    public func setCharset(_ charset: String) {
        var changed = book
        changed.charset = charset
        try? environment.store.update(changed)
        reloadContent()
    }

    /// Toggles the re-segmenting of the paragraphs — upstream
    /// `ReadBookActivity.menu_re_segment`.
    public func toggleReSegment() {
        var changed = book
        changed.reSegment = !changed.reSegment
        try? environment.store.update(changed)
        reloadContent()
    }

    /// Toggles the removal of a tag from the content — upstream
    /// `ReadBookActivity.menu_del_ruby_tag` / `menu_del_h_tag`.
    ///
    /// The tags are upstream `Book.rubyTag` (4) and `Book.hTag` (2).
    public func toggleDelTag(_ tag: Int64) {
        var changed = book
        var config = changed.readConfigBox
        config.delTag = changed.hasDelTag(tag) ? changed.removingDelTag(tag) : changed.addingDelTag(tag)
        changed.readConfigBox = config
        try? environment.store.update(changed)
        reloadContent()
    }

    /// The image style of the book — upstream `Book.getImageStyle()`.
    public var imageStyle: BookImageStyle {
        guard let raw = book.readConfigBox.imageStyle else { return .standard }
        return BookImageStyle(rawValue: raw) ?? .standard
    }

    /// Sets the image style — upstream `ReadBookActivity.menu_image_style`.
    public func setImageStyle(_ style: BookImageStyle) {
        var changed = book
        var config = changed.readConfigBox
        config.imageStyle = style.rawValue
        if style == .single {
            // Upstream switches to the cover animation with the single style.
            config.pageAnim = 0
        }
        changed.readConfigBox = config
        try? environment.store.update(changed)
        Task { await updateReaderStyle { $0.pageAnim = config.pageAnim ?? $0.pageAnim } }
        reloadContent()
    }

    /// Whether the duplicated title is removed for the current chapter —
    /// upstream `BookHelp.removeSameTitle`.
    public var removesSameTitle: Bool {
        guard let storage = environment.cacheStorage else { return true }
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return true }
        return storage.isSameTitleRemoved(book: book, chapter: chapters[index])
    }

    /// Keeps (or removes again) the duplicated title of the current chapter —
    /// upstream `ReadBookViewModel.reverseRemoveSameTitle()`.
    public func toggleSameTitleRemoved() {
        guard let storage = environment.cacheStorage else { return }
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return }
        storage.setSameTitleRemoved(
            book: book,
            chapter: chapters[index],
            removed: !removesSameTitle
        )
        reloadContent()
    }

    /// Reverses the paragraphs of the current chapter — upstream
    /// `ReadBookViewModel.reverseContent(book)`.
    public func reverseCurrentContent() {
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        guard let storage = environment.cacheStorage,
              let content = storage.content(book: book, chapter: chapter) else { return }
        let paragraphs = content.components(separatedBy: "\n").reversed().joined(separator: "\n")
        try? storage.saveText(book: book, chapter: chapter, content: paragraphs)
        reloadContent()
    }

    /// Buys the current chapter — upstream `ReadBookActivity.payAction()`.
    ///
    /// The purchase script of the source is evaluated with the chapter as the
    /// context; an absolute URL opens the web view, "true" means the purchase
    /// succeeded and the table of contents is reloaded.
    public func payChapter() async {
        guard !book.isLocal else { return }
        guard let model else { return }
        guard let source = try? model.environment.source(for: book) else { return }
        guard chapters.indices.contains(chapterIndex) else {
            errorMessage = "没有章节"
            return
        }
        let chapter = chapters[chapterIndex]
        do {
            let result = try ChapterPay.pay(
                source: source,
                book: book,
                chapter: chapter,
                dependencies: model.environment.dependencies()
            )
            switch result {
            case .openURL(let url):
                browserURL = url
                isBrowserPresented = true
            case .refreshTableOfContents:
                await checkForNewChapters()
            case .ignored:
                break
            }
        } catch {
            // Upstream `AppLog.put("执行购买操作出错…", it, true)`.
            AppLog.shared.put("执行购买操作出错", error: error)
            errorMessage = error.localizedDescription
        }
    }

    /// Reloads the content of the current chapter — upstream
    /// `ReadBook.loadContent(false)` after a content option changed.
    private func reloadContent() {
        Task {
            await readBook.reloadCurrentChapter()
            refreshPage()
        }
    }

    // MARK: - The content refresh (upstream `ReadBookViewModel`)

    /// Refreshes the content of the current chapter — upstream
    /// `ReadBookViewModel.refreshContentDur(book)`: the cached content of the
    /// chapter is deleted and the chapter is loaded again.
    public func refreshCurrentContent() {
        Task {
            guard chapters.indices.contains(chapterIndex) else { return }
            let chapter = chapters[chapterIndex]
            model?.environment.cacheStorage?.deleteContent(book: book, chapter: chapter)
            await readBook.reloadCurrentChapter()
            refreshPage()
        }
    }

    /// Refreshes the content of the chapters after the current one — upstream
    /// `ReadBookViewModel.refreshContentAfter(book)`.
    public func refreshContentAfter() {
        Task {
            if let storage = model?.environment.cacheStorage {
                for chapter in chapters[chapterIndex...] {
                    storage.deleteContent(book: book, chapter: chapter)
                }
            }
            await readBook.reloadCurrentChapter()
            refreshPage()
        }
    }

    /// Refreshes the content of the whole book — upstream
    /// `ReadBookViewModel.refreshContentAll(book)`: the whole cache of the
    /// book is cleared and the current chapter is loaded again.
    public func refreshAllContent() {
        Task {
            model?.environment.cacheStorage?.clearCache(book: book)
            await readBook.reloadCurrentChapter()
            refreshPage()
        }
    }

    /// Replaces the content of the current chapter — upstream
    /// `ReadBookViewModel.saveContent(book, content)`, which is what the
    /// per-chapter source change (章节换源) calls.
    ///
    /// The content is written into the cache of the chapter and the chapter is
    /// loaded again, so the reader shows the text of the other source.
    public func replaceCurrentContent(_ content: String) {
        Task {
            guard chapters.indices.contains(chapterIndex) else { return }
            let chapter = chapters[chapterIndex]
            if let storage = model?.environment.cacheStorage {
                try? storage.saveText(book: book, chapter: chapter, content: content)
            }
            await readBook.reloadCurrentChapter()
            refreshPage()
        }
    }

    // MARK: - The reading progress of the WebDAV server

    /// The message of the last progress sync — upstream the toast
    /// ("已同步最新阅读进度") and the log entry.
    @Published public var progressMessage: String?

    /// The progress of the server that is older than the local one — the
    /// upstream asks the user whether the local progress should be
    /// overwritten (`ReadBookActivity.sureSyncProgress`).
    @Published public var pendingRemoteProgress: BookProgress?

    /// Fetches the reading progress from the WebDAV server — upstream
    /// `ReadBookViewModel.syncBookProgress`.
    public func fetchRemoteProgress() async {
        guard let service = webDavService() else {
            progressMessage = "未配置 WebDAV"
            return
        }
        do {
            let remote = try await service.downloadProgress(
                fileName: BookProgress(book: book).fileName
            )
            let outcome = BookProgressSync.resolve(
                remote: remote,
                local: BookProgress(book: book),
                totalChapters: Int(book.simulatedTotalChapterNum())
            )
            switch outcome {
            case .same:
                progressMessage = "进度相同"
            case .remoteNewer(let progress):
                await applyRemoteProgress(progress)
                progressMessage = "已同步最新阅读进度"
            case .remoteOlder(let progress):
                // The upstream asks the user before the local progress is
                // overwritten with the older remote one.
                pendingRemoteProgress = progress
                progressMessage = "远端进度较旧"
            case .beyondTheBook:
                progressMessage = "远端进度超出章节范围"
            }
        } catch {
            progressMessage = "拉取阅读进度失败"
        }
    }

    /// Applies the progress of the server — upstream `ReadBook.setProgress`.
    public func applyRemoteProgress(_ progress: BookProgress) async {
        var changed = book
        changed.durChapterIndex = Int64(progress.durChapterIndex)
        changed.durChapterPos = Int64(progress.durChapterPos)
        changed.durChapterTitle = progress.durChapterTitle
        changed.durChapterTime = progress.durChapterTime
        book = changed
        try? environment.store.update(changed)
        await readBook.openChapter(
            index: progress.durChapterIndex,
            position: progress.durChapterPos
        )
        refreshPage()
    }

    /// Uploads the reading progress to the WebDAV server — upstream
    /// `ReadBook.uploadProgress(true)`.
    public func uploadProgress() async {
        guard let service = webDavService() else {
            progressMessage = "未配置 WebDAV"
            return
        }
        do {
            try await service.uploadProgress(BookProgress(book: book))
            progressMessage = "上传成功"
        } catch {
            progressMessage = "上传阅读进度失败"
        }
    }

    /// The WebDAV service of the reader — upstream `AppWebDav`.
    ///
    /// The upstream keeps the account of the app in the preferences
    /// (`PreferKey.webDavUrl` / `webDavAccount` / `webDavPassword`) and not
    /// in the `servers` table.
    private func webDavService() -> WebDavService? {
        let account = environment.settings.appWebDav
        guard account.isConfigured else { return nil }
        return WebDavService(
            configuration: account.serviceConfiguration,
            httpClient: environment.httpClient
        )
    }

    // MARK: - The content editor

    /// Whether the content editor is shown — upstream `ContentEditDialog`.
    @Published public var isContentEditPresented = false

    /// The content of the chapter that is edited — upstream
    /// `ContentEditViewModel.initContent`.
    ///
    /// The upstream shows the PROCESSED text without the title
    /// (`ContentProcessor.getContent(..., includeTitle = false)`).
    public var currentChapterContent: String {
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return "" }
        guard let storage = environment.cacheStorage else { return "" }
        let chapter = chapters[index]
        let titleRules = (try? environment.store.replaceRulesForTitle(
            name: book.name,
            origin: book.origin
        )) ?? []
        let contentRules = (try? environment.store.replaceRulesForContent(
            name: book.name,
            origin: book.origin
        )) ?? []
        return ContentEditService.loadContent(
            book: book,
            chapter: chapter,
            storage: storage,
            titleRules: titleRules,
            contentRules: contentRules,
            chineseConversionMode: ChineseConversionMode(
                rawValue: environment.settings.chineseConverterType
            ) ?? .off,
            scriptEngine: environment.scriptEngine
        ) ?? ""
    }

    /// The title of the chapter that is edited.
    public var currentChapterTitle: String {
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return "" }
        return chapters[index].title
    }

    /// Deletes the cached content and downloads the chapter again — upstream
    /// `ContentEditViewModel.initContent(reset = true)`.
    public func resetEditedContent() async {
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return }
        guard let storage = environment.cacheStorage else { return }
        let chapter = chapters[index]
        let source = try? environment.source(for: book)
        _ = await ContentEditService.resetContent(
            book: book,
            chapter: chapter,
            storage: storage,
            source: source ?? nil,
            dependencies: environment.dependencies()
        )
        reloadContent()
    }

    /// Saves the edited content — upstream `ContentEditDialog.saveContent`.
    public func saveEditedContent(title: String, content: String) {
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        if let storage = environment.cacheStorage {
            try? storage.saveText(book: book, chapter: chapter, content: content)
        }
        if !title.isEmpty, title != chapter.title {
            var changed = chapter
            changed.title = title
            try? environment.store.update(changed)
            if let position = chapters.firstIndex(where: { $0.url == chapter.url }) {
                chapters[position] = changed
            }
        }
        isContentEditPresented = false
        reloadContent()
    }

    /// Looks a word up in the dictionary rules — upstream `DictDialog`.
    ///
    /// The upstream shows a tab per enabled rule; the dialog performs the
    /// lookup itself, so the controller only hands over the word and the
    /// rules.
    public func lookupDictionary(_ word: String) {
        Task {
            let rules = (try? environment.store.allDictRules()) ?? []
            guard !rules.isEmpty else {
                errorMessage = "没有配置词典规则"
                return
            }
            let enabled = DictRuleManager.enabled(rules)
            guard !enabled.isEmpty else {
                errorMessage = "没有启用词典规则"
                return
            }
            dictWord = word
            dictRules = enabled
            isDictPresented = true
        }
    }

    /// Toggles the read aloud of a selection — upstream
    /// `TextActionMenu.kt:200-209` (the long press on the 朗读 action).
    ///
    /// 0 reads the selected text, 1 reads aloud from the selection to the end
    /// of the chapter.
    public func toggleReadAloudMode() {
        let mode = environment.settings.contentSelectSpeakMod
        let newMode = mode == 0 ? 1 : 0
        environment.settings.contentSelectSpeakMod = newMode
        selection.message = newMode == 1
            ? "切换为从选择的地方开始一直朗读"
            : "切换为朗读选择内容"
    }

    /// Stores the read-aloud engine of this book — upstream
    /// `Book.setTtsEngine` (`data/entities/Book.kt:241-246`).
    ///
    /// The engine of the book wins over the global one
    /// (`ReadAloud.ttsEngine`).
    public func setTtsEngine(_ engine: String?) {
        var updated = book
        var config = updated.readConfigBox
        config.ttsEngine = engine
        updated.readConfigBox = config
        try? environment.store.update(updated)
        book = updated
    }

    /// Moves the read aloud to the previous chapter — upstream
    /// `ReadAloudDialog`: `ReadBook.moveToPrevChapter(upContent = true,
    /// toLast = false)`.
    public func readAloudPreviousChapter() {
        Task {
            guard await readBook.moveToPrevChapter() else { return }
            await startReadAloud()
        }
    }

    /// Moves the read aloud to the next chapter — upstream
    /// `ReadAloudDialog`: `ReadBook.moveToNextChapter(true)`.
    public func readAloudNextChapter() {
        Task {
            guard await readBook.moveToNextChapter() else { return }
            await startReadAloud()
        }
    }

    /// Reads the selected text aloud — upstream `aloudStartSelect` /
    /// `speak(selectedText)`.    ///
    /// The upstream's preference `contentSelectSpeakMod` decides what the
    /// 朗读 action of the selection menu does
    /// (`ReadBookActivity.kt:848-854`): 0 reads the selected text alone, 1
    /// reads aloud from the selection to the end of the chapter
    /// (`ReadView.aloudStartSelect`).
    public func readAloud(selectedText: String) {
        guard !selectedText.isEmpty else { return }
        if environment.settings.contentSelectSpeakMod == 1 {
            Task { await readAloudFromSelection() }
            return
        }
        readAloud.play(
            paragraphs: [
                ReadAloudParagraph(index: 0, text: selectedText, start: 0, end: selectedText.count)
            ],
            chapterIndex: readBook.durChapterIndex
        )
    }

    /// The chapter position of the current selection.
    ///
    /// Upstream `ReadView.aloudStartSelect` uses the position of the
    /// selection inside the chapter.
    public var selectionChapterPosition: Int? {
        guard let selection = selection.selection else { return nil }
        guard let chapter = readBook.curTextChapter else { return nil }
        let index = readBook.pageIndex
        guard let page = chapter.page(at: index) else { return nil }
        return page.chapterPosition(atPageOffset: selection.range.lowerBound)
    }

    /// Reads aloud from the selection to the end of the chapter — upstream
    /// `ReadView.aloudStartSelect` → `ReadBook.readAloud(startPos)`.
    public func readAloudFromSelection() async {
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return }
        guard let position = selectionChapterPosition else {
            let text = selection.selectedText
            guard !text.isEmpty else { return }
            readAloud.play(
                paragraphs: [
                    ReadAloudParagraph(index: 0, text: text, start: 0, end: text.count)
                ],
                chapterIndex: readBook.durChapterIndex
            )
            return
        }
        let chapter = chapters[index]
        guard let content = try? await contentProvider.chapterContent(book: book, chapter: chapter),
              !content.isEmpty else {
            return
        }
        let paragraphs = ReadAloudSplitter.paragraphs(in: content)
        // The paragraph that holds the selection.
        let startIndex = paragraphs.firstIndex { $0.start <= position && position < $0.end } ?? 0
        readAloud.chapterTitle = chapter.title
        readAloud.play(paragraphs: paragraphs, chapterIndex: index, startIndex: startIndex)
    }

    // MARK: - The inline images

    /// The source of the image that is previewed — upstream `PhotoDialog`.
    @Published public var previewImageSrc: String?
    /// Whether the image preview is shown.
    @Published public var isImagePreviewPresented = false
    /// The source of the image whose menu is shown — upstream
    /// `ReadBookActivity.onImageLongPress`.
    @Published public var imageMenuSrc: String?
    /// Whether the image menu is shown.
    @Published public var isImageMenuPresented = false

    /// Opens the preview of an image — upstream `PhotoDialog(src)`.
    public func previewImage(src: String) {
        previewImageSrc = src
        isImagePreviewPresented = true
    }

    /// Downloads the image again — upstream `ReadBookViewModel.refreshImage`.
    public func refreshImage(src: String) async {
        guard let storage = environment.cacheStorage else { return }
        let absolute = NetworkUtils.absoluteURL(base: book.tocUrl, src)
        storage.deleteImage(book: book, src: absolute)
        _ = await contentProvider.chapterImages(
            book: book,
            chapter: currentChapter,
            sources: [src]
        )
        await readBook.reloadCurrentChapter()
        refreshPage()
    }

    /// Saves the image into a file — upstream `ReadBookViewModel.saveImage`.
    @discardableResult
    public func saveImage(src: String, to url: URL) -> Bool {
        let absolute = NetworkUtils.absoluteURL(base: book.tocUrl, src)
        guard let data = environment.cacheStorage?.image(book: book, src: absolute) else {
            return false
        }
        do {
            try data.write(to: url)
            return true
        } catch {
            AppLog.shared.put("保存图片失败", error: error)
            return false
        }
    }

    /// The chapter that is on screen.
    private var currentChapter: BookChapter {
        chapters.indices.contains(readBook.durChapterIndex)
            ? chapters[readBook.durChapterIndex]
            : BookChapter(url: "", title: "")
    }

    // MARK: - ReadBookDelegate

    public func readBook(_ readBook: ReadBook, didLoad chapter: TextChapter, position: Int) {
        refreshPage()
    }

    public func readBook(_ readBook: ReadBook, didChangePageIndex index: Int) {
        pageIndex = index
    }

    public func readBook(_ readBook: ReadBook, didSaveProgress book: Book) {}

    public func readBook(_ readBook: ReadBook, didFail error: Error) {
        errorMessage = error.localizedDescription
        // Upstream `ReadBookViewModel.autoChangeSource` — the reader changes
        // the source when the content of the chapter cannot be loaded.
        Task { await autoChangeSourceIfNeeded() }
    }

    // MARK: - The automatic source change

    /// Whether the source is being changed automatically.
    @Published public var isChangingSource = false

    /// Changes the source when the book has no source (or when the content
    /// cannot be loaded) — upstream `ReadBookViewModel.autoChangeSource`
    /// (`ReadBookViewModel.kt:293-327`).
    ///
    /// The upstream searches every enabled text source for the book, loads the
    /// detail page, the chapter list and the content of the current chapter,
    /// and switches to the first source that works.
    public func autoChangeSourceIfNeeded() async {
        guard environment.settings.autoChangeSource else { return }
        guard let model, !book.isLocal else { return }
        // The upstream only changes the source when the book has no source at
        // all (`ReadBook.bookSource == null`).
        guard (try? model.environment.source(for: book)) == nil else { return }
        guard !isChangingSource else { return }
        isChangingSource = true
        defer { isChangingSource = false }
        do {
            let sources = try model.environment.sources(enabledOnly: true)
            guard let candidate = await ChangeSourceService.autoChangeSource(
                book: book,
                sources: sources,
                chapterIndex: readBook.durChapterIndex,
                dependencies: model.environment.dependencies()
            ) else {
                return
            }
            guard let toc = candidate.toc else { return }
            let switched = ChangeSourceService.switchSource(
                oldBook: book,
                newBook: candidate.book,
                toc: toc
            )
            try model.environment.store.update(switched)
            // The replacement rules depend on the origin of the book — they
            // are rebuilt when the source changes.
            readBook.titleRules = (try? model.environment.store.replaceRulesForTitle(
                name: switched.name,
                origin: switched.origin
            )) ?? []
            readBook.contentRules = (try? model.environment.store.replaceRulesForContent(
                name: switched.name,
                origin: switched.origin
            )) ?? []
            book = switched
            chapters = toc
            await readBook.replaceBook(switched, chapters: toc)
            refreshPage()
            model.reloadBookshelf()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Holds the reader configuration for the state machine — the reader settings
/// change it at runtime.
final class ReaderConfigBox {
    var config = ReaderConfig()
}

/// Holds the page layout for the state machine — the page size follows the
/// screen, so the layout is replaced when the device is rotated.
final class ReaderLayoutBox {
    var layout: ReaderLayout
    init(layout: ReaderLayout) { self.layout = layout }
}

/// Persists the reading progress in the store.
final class StoreProgressPersister: ReadProgressPersisting {    let store: LegadoStore
    init(store: LegadoStore) { self.store = store }
    func saveBook(_ book: Book) throws { try store.update(book) }
    func loadChapters(bookUrl: String) throws -> [BookChapter] { try store.chapters(bookUrl: bookUrl) }
}

/// Supplies the chapter text: the cache first, then the network.
final class AppChapterContentProvider: ChapterContentProviding {

    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
    }

    func chapterContent(book: Book, chapter: BookChapter) async throws -> String? {
        if book.isLocal {
            // The local books are read from the copy in the app storage —
            // `book.bookUrl` holds its address (upstream `book.bookUrl`).
            guard let url = LocalBookReader.fileURL(for: book) else {
                throw AppEnvironmentError.bookNotFound(book.bookUrl)
            }
            return try LocalBook.content(fileURL: url, chapter: chapter)
        }
        guard let source = try environment.source(for: book) else {
            throw AppEnvironmentError.sourceNotFound(book.origin)
        }
        return try await environment.loadContent(book: book, chapter: chapter, source: source)
    }

    /// Whether the duplicated title is removed — upstream
    /// `BookHelp.removeSameTitle` (the marker file in the cache folder).
    func removesSameTitle(book: Book, chapter: BookChapter) -> Bool {
        guard let storage = environment.cacheStorage else { return true }
        return storage.isSameTitleRemoved(book: book, chapter: chapter)
    }

    /// Resolves the inline images of the chapter — upstream `ImageProvider`.
    ///
    /// The upstream downloads the image with Glide and caches it in the book
    /// cache folder (`BookHelp.writeImage`); the port reads the cache first and
    /// downloads the missing images with the HTTP client of the environment.
    ///
    /// The dictionary is keyed by the *raw* `src` of the tag, because that is
    /// what the layout engine looks up.
    func chapterImages(
        book: Book,
        chapter: BookChapter,
        sources: [String]
    ) async -> [String: ReaderImage] {
        guard !sources.isEmpty else { return [:] }
        var images: [String: ReaderImage] = [:]
        let storage = environment.cacheStorage
        for raw in sources {
            let absolute = NetworkUtils.absoluteURL(base: chapter.url, raw)
            // The cache first — upstream `BookHelp.isImageExist`.
            if let storage, let data = storage.image(book: book, src: absolute) {
                if let size = ImageSizeDetector.size(of: data) {
                    images[raw] = ReaderImage(src: absolute, size: size, data: data)
                }
                continue
            }
            guard let data = await downloadImage(url: absolute, book: book),
                  let size = ImageSizeDetector.size(of: data) else { continue }
            try? storage?.saveImage(book: book, src: absolute, data: data)
            images[raw] = ReaderImage(src: absolute, size: size, data: data)
        }
        return images
    }

    /// Downloads an image — upstream `ImageProvider.getImage`.
    private func downloadImage(url: String, book: Book) async -> Data? {
        guard !url.isEmpty, let parsed = URL(string: url), parsed.scheme != nil else { return nil }
        var request = HttpRequest(url: url)
        // The headers of the book source are used for the image as well.
        if let source = try? environment.source(for: book) {
            request.headers = source.headerMap(hasLoginHeader: false)
        }
        guard let response = try? await environment.httpClient.send(request),
              response.isSuccessful else { return nil }
        return response.data
    }
}

/// Resolves the file of a local book.
enum LocalBookReader {

    /// The file of a local book — the copy in the app storage (`book.bookUrl`).
    static func fileURL(for book: Book) -> URL? {
        if let url = URL(string: book.bookUrl), url.isFileURL {
            return url
        }
        // The name of the file inside the books directory.
        let name = book.originName.isEmpty ? book.origin : book.originName
        guard !name.isEmpty else { return nil }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let candidate = documents?.appendingPathComponent("books").appendingPathComponent(name)
        if let candidate, FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }
}

/// The reader screen.
public struct ReaderView: View {

    @ObservedObject var controller: ReaderController
    @ObservedObject var readAloud: ReadAloudService

    public init(controller: ReaderController) {
        self.controller = controller
        self.readAloud = controller.readAloud
    }

    public var body: some View {
        ReaderStatusBarHost(isHidden: controller.system.hidesStatusBar) {
            ZStack {
                ReaderBackgroundSupport(
                    preset: controller.backgroundPreset,
                    mode: controller.displayMode,
                    root: controller.backgroundRoot
                )
                VStack(spacing: 0) {
                    if controller.isLoading {
                        ProgressView("加载中")
                    } else {
                        // The header of the page — upstream `PageView.upTipStyle`.
                        tipHeader
                        GeometryReader { proxy in
                            ZStack {
                                if controller.pageTurnStyle == .scroll {
                                    // The continuous-scroll mode — upstream
                                    // `ContentTextView.drawPage` +
                                    // `ScrollPageDelegate.onScroll`.
                                    ReaderScrollContentView(
                                        pages: controller.scrollPages,
                                        titleFont: controller.resolvedFonts.title.swiftUIFont,
                                        bodyFont: controller.resolvedFonts.body.swiftUIFont,
                                        textColor: ColorHex.color(
                                            controller.backgroundPreset.textColorString(
                                                for: controller.displayMode
                                            ),
                                            fallback: .primary
                                        )
                                    )
                                    .gesture(scrollDrag)
                                } else {
                                    PageTurnContainer(
                                        style: controller.pageTurnStyle,
                                        viewWidth: Double(proxy.size.width),
                                        // The horizontal drag turns the page — upstream
                                        // `ReadView.onPageScroll`.
                                        onTurn: { direction in
                                            Task {
                                                if direction == .next {
                                                    await controller.nextPage()
                                                } else {
                                                    await controller.previousPage()
                                                }
                                            }
                                        },
                                        // The drag drives the animation — upstream
                                        // `HorizontalPageDelegate.onDraw` redraws the
                                        // pages with the offset of the finger.
                                        onProgress: { progress in
                                            controller.pageTurnProgress = progress
                                        },
                                        // The direction of the drag decides which
                                        // page is revealed by the turn.
                                        onDirection: { direction in
                                            controller.pageTurnDirection = direction
                                        }
                                    ) {
                                        PageTurnView(
                                            lines: controller.pageLines,
                                            revealedLines: controller.revealedPageLines,
                                            titleFont: controller.resolvedFonts.title.swiftUIFont,
                                            bodyFont: controller.resolvedFonts.body.swiftUIFont,
                                            style: controller.pageTurnStyle,
                                            direction: controller.pageTurnDirection,
                                            textColor: ColorHex.color(
                                                controller.backgroundPreset.textColorString(
                                                    for: controller.displayMode
                                                ),
                                                fallback: .primary
                                            ),
                                            progress: controller.pageTurnProgress,
                                            viewWidth: Double(proxy.size.width)
                                        )
                                    }
                                }
                                // The progress of the automatic page turn — upstream
                                // `AutoPager.onDraw` draws the bar at the bottom
                                // of the page (the accent colour).
                                if controller.autoPageProgress > 0 {
                                    VStack {
                                        Spacer()
                                        GeometryReader { barProxy in
                                            Rectangle()
                                                .fill(Color.accentColor)
                                                .frame(
                                                    width: barProxy.size.width * controller.autoPageProgress,
                                                    height: 2
                                                )
                                                .frame(
                                                    maxWidth: .infinity,
                                                    alignment: .leading
                                                )
                                        }
                                        .frame(height: 2)
                                    }
                                }
                                // The nine-zone tap area — upstream `ReadView.onSingleTapUp`.
                                ReaderTapArea(
                                    configuration: ReaderInteractionConfiguration.configuration(
                                        from: controller.environment.settings
                                    ),
                                    lines: controller.pageLines,
                                    lineOffsets: controller.pageLineOffsets,
                                    // A tap on an image opens the preview —
                                    // upstream `AppConfig.previewImageByClick`.
                                    previewImageByClick: controller.environment.settings.previewImageByClick
                                ) { action in
                                    controller.performClickAction(action)
                                } onLongPress: { offset in
                                    // The long press starts the text
                                    // selection — upstream
                                    // `ReadView.onLongPress`.
                                    guard controller.environment.settings.textSelectAble else { return }
                                    controller.selection.selectParagraph(
                                        around: offset,
                                        in: controller.pageText
                                    )
                                } onTapImage: { src in
                                    controller.previewImage(src: src)
                                } onLongPressImage: { src in
                                    controller.imageMenuSrc = src
                                    controller.isImageMenuPresented = true
                                }
                            }
                            .onChange(of: proxy.size) { _, size in
                                // The page size follows the screen — the layout
                                // is computed again when it changes.
                                controller.updatePageSize(CGSizeLike(
                                    width: Double(size.width),
                                    height: Double(size.height)
                                ))
                            }
                            .onChange(of: readAloud.currentParagraph) { _, _ in
                                // The paragraph that is being read is
                                // highlighted — upstream
                                // `EventBus.TTS_PROGRESS` →
                                // `TextPage.upPageAloudSpan`.
                                controller.updateReadAloudHighlight()
                            }
                        }
                        // The footer of the page — upstream `PageView.upTipStyle`.
                        tipFooter
                    }
                    readAloudBar
                    // The text selection — upstream `TextActionMenu`.
                    ReaderSelectionOverlay(
                        controller: controller.selection,
                        onReplace: { text in
                            controller.replacePattern = text
                            controller.isReplacePresented = true
                        },
                        onBookmark: { text in
                            controller.addBookmark(selectedText: text)
                        },
                        onReadAloud: { text in
                            controller.readAloud(selectedText: text)
                        },
                        onToggleReadAloudMode: {
                            controller.toggleReadAloudMode()
                        },
                        onDictionary: { text in
                            controller.lookupDictionary(text)
                        },
                        onSearchContent: { text in
                            controller.searchKeyword = text
                            controller.isSearchPresented = true
                        },
                        onBrowser: { text in
                            controller.browserURL = text
                            controller.isBrowserPresented = true
                        },
                        onShare: { text in
                            controller.sharedText = text
                            controller.isSharePresented = true
                        }
                    )
                    // The in-reader search — upstream `SearchMenu`.
                    if controller.isSearchPresented {
                        ReaderSearchBar(controller: controller) {
                            controller.isSearchPresented = false
                        } onShowResults: { keyword in
                            controller.isSearchPresented = false
                            // Upstream `ReadBookActivity.openSearchActivity` —
                            // the whole-book search screen.
                            controller.contentSearchKeyword = keyword
                            controller.isContentSearchPresented = true
                        } onShowMenu: {
                            controller.isSearchPresented = false
                            controller.isMenuPresented = true
                        }
                    }
                    footer
                }
            }
            .onAppear {
                // The upstream applies the system settings when the reader opens
                // (`BaseReadBookActivity.kt`).
                controller.system.activate()
                controller.activateMediaCommands()
                // The battery level of the tip header/footer.
                ReaderBattery.refresh()
                Task { await controller.start() }
            }
            .onDisappear {
                controller.system.deactivate()
                controller.deactivateMediaCommands()
            }
            // Upstream `ReadBookActivity.kt:288` — the back key does nothing
            // while the reader menu is hidden (`disableReturnKey`).
            .interactiveDismissDisabled(
                controller.environment.settings.disableReturnKey && !controller.isMenuPresented
            )
            .sheet(isPresented: $controller.isTocPresented) {
                if let model = controller.model {
                    NavigationStack {
                        TocView(model: model, book: controller.book) { index in
                            controller.isTocPresented = false
                            Task { await controller.jump(toChapter: index) }
                        }
                    }
                }
            }
            .sheet(isPresented: $controller.isReplacePresented) {
                if let model = controller.model {
                    NavigationStack {
                        ReaderReplaceSheet(
                            model: model,
                            book: controller.book,
                            pattern: $controller.replacePattern,
                            replacement: $controller.replaceReplacement
                        )
                    }
                }
            }
            .sheet(isPresented: $controller.isBrowserPresented) {
                NavigationStack {
                    InAppBrowserView(url: controller.browserURL)
                }
            }
            .sheet(isPresented: $controller.isSharePresented) {
                ShareSheet(items: [controller.sharedText])
            }
            .sheet(isPresented: $controller.isDictPresented) {
                if let result = controller.dictResult {
                    DictDialogView(
                        word: result.word,
                        result: result.result,
                        ruleName: result.ruleName
                    )
                } else {
                    DictDialogView(
                        word: controller.dictWord ?? "",
                        rules: controller.dictRules,
                        dependencies: controller.environment.dependencies()
                    )
                }
            }
            .sheet(isPresented: $controller.isContentEditPresented) {
                NavigationStack {
                    ContentEditView(controller: controller)
                }
            }
            // The whole-book content search — upstream
            // `SearchContentActivity`.
            .sheet(isPresented: $controller.isContentSearchPresented) {
                if let model = controller.model {
                    NavigationStack {
                        ContentSearchView(
                            model: model,
                            book: controller.book,
                            initialQuery: controller.contentSearchKeyword
                        )
                    }
                }
            }
            // The preview of an image — upstream `PhotoDialog(src)`.
            .sheet(isPresented: $controller.isImagePreviewPresented) {
                if let src = controller.previewImageSrc {
                    ImagePreviewView(controller: controller, src: src)
                }
            }
            // The menu of an image — upstream `ReadBookActivity.onImageLongPress`.
            .sheet(isPresented: $controller.isImageMenuPresented) {
                if let src = controller.imageMenuSrc {
                    ImageMenuView(controller: controller, src: src)
                }
            }
            // The bookmark editor — upstream `ReadBookActivity.menu_bookmark`
            // → `showDialogFragment(BookmarkDialog(bookmark))`.
            .sheet(item: $controller.pendingBookmark) { bookmark in
                BookmarkEditView(bookmark: bookmark) { edited in
                    try? controller.environment.store.insert(edited)
                    controller.model?.reloadBookmarks()
                }
            }
            // Upstream `ReadBookActivity.sureSyncProgress` — the remote
            // progress is older, the user decides whether to overwrite the
            // local one.
            .alert("远端进度较旧", isPresented: Binding(
                get: { controller.pendingRemoteProgress != nil },
                set: { if !$0 { controller.pendingRemoteProgress = nil } }
            )) {
                Button("覆盖本地进度") {
                    if let progress = controller.pendingRemoteProgress {
                        controller.pendingRemoteProgress = nil
                        Task { await controller.applyRemoteProgress(progress) }
                    }
                }
                Button("取消") {
                    controller.pendingRemoteProgress = nil
                }
            } message: {
                Text("是否使用远端的阅读进度覆盖本地进度？")
            }
        }
    }

    /// The vertical drag of the continuous-scroll mode — upstream
    /// `ScrollPageDelegate.onScroll`.
    private var scrollDrag: DragGestureModifier {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                controller.scrollDragChanged(translation: Double(value.translation.height))
            }
            .onEnded { _ in
                controller.scrollDragEnded()
            }
    }

    /// The header of the page — upstream `PageView.upTipStyle` (the tip row
    /// above the text).
    @ViewBuilder
    private var tipHeader: some View {        let layout = controller.config.tipLayout
        if controller.config.showHeader && layout.headerMode.isVisible(statusBarVisible: false) {
            ReaderTipView(
                row: layout.header,
                context: controller.tipContext,
                textColor: tipColor
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
    }

    /// The footer of the page — upstream `PageView.upTipStyle` (the tip row
    /// below the text).
    @ViewBuilder
    private var tipFooter: some View {
        let layout = controller.config.tipLayout
        if controller.config.showFooter && layout.footerMode.isVisible() {
            ReaderTipView(
                row: layout.footer,
                context: controller.tipContext,
                textColor: tipColor
            )
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
        }
    }

    /// The colour of the tips — upstream `ReadBookConfig.tipColor` (0 = the
    /// text colour of the reader).
    private var tipColor: Color {
        if controller.config.tipColor > 0 {
            return ColorHex.color(
                String(format: "#%06X", controller.config.tipColor),
                fallback: .secondary
            )
        }
        return ColorHex.color(
            controller.backgroundPreset.textColorString(for: controller.displayMode),
            fallback: .secondary
        )
    }

    /// The read-aloud bar — upstream `ReadAloudDialog`.
    @ViewBuilder
    private var readAloudBar: some View {
        if readAloud.state != .stopped {
            VStack(spacing: 4) {
                // The live timer — upstream `BaseReadAloudService.timeMinute`
                // (the seek bar of `dialog_read_aloud`).
                if readAloud.remainingMinutes > 0 {
                    HStack {
                        Text("剩余 \(readAloud.remainingMinutes) 分钟")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Spacer()
                        // Upstream `BaseReadAloudService.addTimer` — ten more
                        // minutes.
                        Button("+10 分钟") {
                            readAloud.addTimer()
                        }
                        .font(.system(size: 11))
                    }
                }
                HStack {
                    // Upstream `ReadAloudDialog`: `tvPre` / `tvNext` jump to
                    // the previous / the next chapter.
                    Button("上一章") {
                        controller.readAloudPreviousChapter()
                    }
                    Button("上一段") {
                        readAloud.previousParagraph()
                    }
                    Spacer()
                    Button(readAloud.state == .playing ? "暂停" : "继续") {
                        if readAloud.state == .playing {
                            readAloud.pause()
                        } else {
                            readAloud.resume()
                        }
                    }
                    Spacer()
                    Button("下一段") {
                        readAloud.nextParagraph()
                    }
                    Button("下一章") {
                        controller.readAloudNextChapter()
                    }
                    Spacer()
                    Button("停止") {
                        readAloud.stop()
                    }
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var footer: some View {
        HStack {
            Button("上一页") {
                Task { await controller.previousPage() }
            }
            Spacer()
            Button("朗读") {
                Task { await controller.startReadAloud() }
            }
            Spacer()
            Button(controller.isAutoPaging ? "停止翻页" : "自动翻页") {
                controller.toggleAutoPage()
            }
            Spacer()
            Text("\(controller.chapterIndex + 1) / \(controller.chapters.count)")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Button("菜单") {
                controller.isMenuPresented = true
            }
            Spacer()
            Button("下一页") {
                Task { await controller.nextPage() }
            }
        }
        .padding(16)
        .sheet(isPresented: $controller.isMenuPresented) {
            ReaderMenuView(controller: controller)
        }
    }
}
