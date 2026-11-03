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
public final class ReaderController: NSObject, ObservableObject, ReadBookDelegate {

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

    /// Whether the reader menu is shown.
    @Published public var isMenuPresented = false

    /// The selection of the text — upstream `ContentTextView`.
    public let selection = ReaderSelectionController()

    /// Whether the in-reader search is shown — upstream `SearchMenu`.
    @Published public var isSearchPresented = false

    /// Whether the table of contents is shown inside the reader — upstream
    /// `ReadMenu` opens the chapter list of the running reader.
    @Published public var isTocPresented = false

    /// The result of the dictionary lookup — upstream `DictDialog`.
    @Published public var dictResult: DictLookupResult?

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
            chineseConversionMode: ChineseConversionMode(
                rawValue: environment.settings.chineseConverterType
            ) ?? .off
        )
        super.init()
        readBook.delegate = self
        readBook.persister = StoreProgressPersister(store: environment.store)
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
    public func checkForNewChapters() async {
        let environment = self.environment
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
        autoPager.onTurn = { [weak self] direction in
            guard let self else { return false }
            Task { await self.nextPage() }
            return true
        }
        autoPager.start()
        scheduleAutoPageTick()
    }

    /// Stops the auto pager — upstream `AutoPager.stop()`.
    public func stopAutoPage() {
        isAutoPaging = false
        autoPager.stop()
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
    private func scheduleAutoPageTick() {
        autoPageTask?.cancel()
        let seconds = autoPager.speed
        autoPageTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds) * 1_000_000_000)
                guard let self, self.isAutoPaging else { return }
                self.autoPager.tick(elapsed: TimeInterval(seconds))
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

    /// Starts the read aloud of the current chapter.
    ///
    /// Upstream `ReadAloud.play(pageIndex, startPos)` reads the chapter that
    /// is on screen; the spoken unit is the paragraph.
    public func startReadAloud() async {
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        guard let content = try? await contentProvider.chapterContent(book: book, chapter: chapter),
              !content.isEmpty else {
            return
        }
        let paragraphs = ReadAloudSplitter.paragraphs(in: content)
        readAloud.chapterTitle = chapter.title
        readAloud.play(paragraphs: paragraphs, chapterIndex: index, startIndex: 0)
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
    }

    /// Removes the lock-screen and headset buttons.
    public func deactivateMediaCommands() {
        mediaCommands?.clearNowPlaying()
        mediaCommands = nil
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
            Task { await nextPage() }
        case .prevPage:
            Task { await previousPage() }
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
            errorMessage = "暂不支持编辑内容"
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
        try? environment.store.insert(bookmark)
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
        try? environment.store.insert(bookmark)
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

    /// Reloads the content of the current chapter — upstream
    /// `ReadBook.loadContent(false)` after a content option changed.
    private func reloadContent() {
        Task {
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
    private func webDavService() -> WebDavService? {
        guard let credentials = try? environment.store.webDavCredentials(),
              credentials.isConfigured else { return nil }
        return WebDavService(
            configuration: credentials.serviceConfiguration(),
            httpClient: environment.httpClient
        )
    }

    // MARK: - The content editor

    /// Whether the content editor is shown — upstream `ContentEditDialog`.
    @Published public var isContentEditPresented = false

    /// The content of the chapter that is edited — upstream
    /// `ContentEditViewModel.initContent`.
    public var currentChapterContent: String {
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return "" }
        guard let storage = environment.cacheStorage else { return "" }
        return storage.content(book: book, chapter: chapters[index]) ?? ""
    }

    /// The title of the chapter that is edited.
    public var currentChapterTitle: String {
        let index = readBook.durChapterIndex
        guard chapters.indices.contains(index) else { return "" }
        return chapters[index].title
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
    public func lookupDictionary(_ word: String) {
        Task {
            let rules = (try? environment.store.allDictRules()) ?? []
            guard !rules.isEmpty else {
                errorMessage = "没有配置词典规则"
                return
            }
            do {
                let result = try await DictSearcher.search(
                    word: word,
                    rules: rules,
                    dependencies: environment.dependencies()
                )
                guard !result.text.isEmpty else {
                    errorMessage = "没有查到结果"
                    return
                }
                dictResult = DictLookupResult(
                    word: word,
                    result: result.text,
                    ruleName: result.ruleName
                )
                isDictPresented = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Reads the selected text aloud — upstream `aloudStartSelect` /
    /// `speak(selectedText)`.
    public func readAloud(selectedText: String) {
        guard !selectedText.isEmpty else { return }
        readAloud.play(
            paragraphs: [
                ReadAloudParagraph(index: 0, text: selectedText, start: 0, end: selectedText.count)
            ],
            chapterIndex: readBook.durChapterIndex
        )
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
                                }
                            ) {
                                ZStack {
                                    PageTurnView(
                                        lines: controller.pageLines,
                                        titleFont: controller.resolvedFonts.title.swiftUIFont,
                                        bodyFont: controller.resolvedFonts.body.swiftUIFont,
                                        style: controller.pageTurnStyle,
                                        direction: controller.pageTurnDirection,
                                        textColor: ColorHex.color(
                                            controller.backgroundPreset.textColorString(
                                                for: controller.displayMode
                                            ),
                                            fallback: .primary
                                        )
                                    )
                                    // The nine-zone tap area — upstream `ReadView.onSingleTapUp`.
                                    ReaderTapArea(
                                        configuration: ReaderInteractionConfiguration.configuration(
                                            from: controller.environment.settings
                                        ),
                                        lines: controller.pageLines,
                                        lineOffsets: controller.pageLineOffsets
                                    ) { action in
                                        controller.performClickAction(action)
                                    } onLongPress: { offset in
                                        // The long press starts the text
                                        // selection — upstream
                                        // `ReadView.onLongPress`.
                                        controller.selection.selectParagraph(
                                            around: offset,
                                            in: controller.pageText
                                        )
                                    }
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
                        } onShowResults: { _ in
                            controller.isSearchPresented = false
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
                }
            }
            .sheet(isPresented: $controller.isContentEditPresented) {
                NavigationStack {
                    ContentEditView(
                        book: controller.book,
                        chapterIndex: controller.chapterIndex,
                        chapterTitle: controller.currentChapterTitle,
                        content: controller.currentChapterContent
                    ) { title, content in
                        controller.saveEditedContent(title: title, content: content)
                    }
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

    /// The header of the page — upstream `PageView.upTipStyle` (the tip row
    /// above the text).
    @ViewBuilder
    private var tipHeader: some View {
        let layout = controller.config.tipLayout
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
            HStack {
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
                Spacer()
                Button("停止") {
                    readAloud.stop()
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
