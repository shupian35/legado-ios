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
    public let book: Book
    /// The chapter list.
    public let chapters: [BookChapter]
    /// The state machine.
    public private(set) var readBook: ReadBook

    /// The text of the current page.
    @Published public var pageText: String = ""

    /// The laid-out lines of the current page — upstream `TextPage.textLines`.
    @Published public var pageLines: [TextLine] = []
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

    /// Whether the system is in dark mode — it decides the night colours of
    /// the reader background (upstream `AppConfig.isNightTheme`).
    public var systemNightMode = false

    /// The background preset of the reader (upstream `ReadBookConfig`).
    public var backgroundPreset: ReaderBackgroundPreset {
        environment.backgroundManager.current
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

    /// The task that drives the auto pager.
    private var autoPageTask: Task<Void, Never>?

    /// The reader configuration (upstream `ReadBookConfig`).
    public var config: ReaderConfig

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
        let config = ReaderConfig()
        self.config = config
        configBox.config = config
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
            await readBook.openChapter(index: index)
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

    // MARK: - The reader settings

    /// Changes the reader configuration and lays the chapter out again —
    /// upstream `ReadBookActivity` re-reads the configuration when the font
    /// size or the spacing changes.
    public func updateReaderStyle(_ mutate: (inout ReaderConfig) -> Void) async {
        mutate(&config)
        configBox.config = config
        await readBook.openChapter(index: readBook.durChapterIndex)
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
    public var pageTurnStyle: PageTurnStyle = .slide

    /// The direction of the last page turn — the reader animates the page
    /// that is being left behind.
    public var pageTurnDirection: PageTurnDirection = .next

    /// The selection overlay state — upstream `ContentTextView`.
    public let selection = ReaderSelectionController()

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
        } else {
            pageText = ""
            pageLines = []
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
            break
        case .toggleReplaceRule:
            break
        case .chapterList:
            isMenuPresented = true
        case .searchContent:
            isMenuPresented = true
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
                                        direction: controller.pageTurnDirection
                                    )
                                    // The nine-zone tap area — upstream `ReadView.onSingleTapUp`.
                                    ReaderTapArea(
                                        configuration: ReaderInteractionConfiguration.configuration(
                                            from: controller.environment.settings
                                        )
                                    ) { action in
                                        controller.performClickAction(action)
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
                    }
                    readAloudBar
                    ReaderSelectionOverlay(controller: controller.selection)
                    footer
                }
            }
            .onAppear {
                // The upstream applies the system settings when the reader opens
                // (`BaseReadBookActivity.kt`).
                controller.system.activate()
                controller.activateMediaCommands()
                Task { await controller.start() }
            }
            .onDisappear {
                controller.system.deactivate()
                controller.deactivateMediaCommands()
            }
        }
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
