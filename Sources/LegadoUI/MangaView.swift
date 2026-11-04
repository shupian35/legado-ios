#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import Foundation
import LegadoCore

/// The manga (image) reader — upstream `ui/book/manga/ReadMangaActivity.kt`.
public final class MangaReaderController: ObservableObject {

    @Published public var chapter: MangaChapter?
    @Published public var isLoading = false
    @Published public var errorMessage: String?
    @Published public var zoom: Double = MangaMode.Zoom.defaultRate
    /// The index of the visible page — upstream `MangaMenu.upSeekBar`.
    @Published public var pageIndex: Int = 0
    /// Whether the menu is shown — upstream `MangaMenu.runMenuIn`.
    @Published public var isMenuVisible = false
    /// Whether the pages turn automatically — upstream
    /// `ReadMangaActivity.enableAutoScrollPage` (`mScrollTimer.isEnabledPage`).
    ///
    /// The upstream keeps the flag in the activity, so it is not persisted.
    @Published public var isAutoPage = false
    /// Whether the pages scroll automatically — upstream
    /// `ReadMangaActivity.enableAutoScroll` (`mScrollTimer.isEnabled`).
    @Published public var isAutoScroll = false
    /// Whether the pages scroll horizontally — upstream
    /// `AppConfig.enableMangaHorizontalScroll`.
    @Published public var isHorizontalScroll = false

    public let environment: AppEnvironment
    public let book: Book
    public let chapters: [BookChapter]
    public var currentChapterIndex: Int = 0
    /// The app model — the menu opens the book info with it.
    public weak var model: LegadoAppModel?
    /// The screen integration (the brightness) — upstream
    /// `MangaMenu.upBrightnessVwPos`.
    public let system: ReaderSystemIntegration

    public init(environment: AppEnvironment, book: Book, chapters: [BookChapter]) {
        self.environment = environment
        self.book = book
        self.chapters = chapters
        self.system = ReaderSystemIntegration(settings: environment.settings)
    }

    /// The title of the current chapter.
    public var chapterTitle: String {
        if let chapter { return chapter.title }
        return chapters.indices.contains(currentChapterIndex)
            ? chapters[currentChapterIndex].title
            : ""
    }

    /// The address of the current chapter — upstream `tvChapterUrl`.
    public var chapterURL: String {
        chapters.indices.contains(currentChapterIndex) ? chapters[currentChapterIndex].url : ""
    }

    /// The number of the pages of the current chapter.
    public var pageCount: Int {
        chapter?.imageCount ?? 0
    }

    /// The text of the page indicator — upstream `upInfoBar`.
    public var pageText: String {
        footerText(pageIndex: pageIndex)
    }

    /// Jumps to a page — upstream `MangaMenu.CallBack.skipToPage`.
    public func skipToPage(_ index: Int) {
        guard index >= 0, index < max(pageCount, 1) else { return }
        pageIndex = index
    }

    /// Goes to the next chapter — upstream `ReadManga.moveToNextChapter`.
    public func moveToNextChapter() async {
        guard currentChapterIndex + 1 < chapters.count else { return }
        await loadChapter(at: currentChapterIndex + 1)
        pageIndex = 0
    }

    /// Goes to the previous chapter — upstream `ReadManga.moveToPrevChapter`.
    public func moveToPrevChapter() async {
        guard currentChapterIndex > 0 else { return }
        await loadChapter(at: currentChapterIndex - 1)
        pageIndex = 0
    }

    /// The brightness the manga reader applies.
    public var brightnessPercent: Int {
        system.brightnessPercent
    }

    // MARK: - The display settings

    /// The colour filter — upstream `AppConfig.mangaColorFilter`.
    @Published public var colorFilter = MangaColorFilter()
    /// Whether the pages are shown in grey — upstream
    /// `AppConfig.enableMangaGray` (`GrayscaleTransformation`).
    @Published public var isGray = false
    /// Whether the pages are shown as on an e-ink screen — upstream
    /// `AppConfig.enableMangaEInk` (`EpaperTransformation`).
    @Published public var isEInk = false
    /// The threshold of the e-ink mode — upstream
    /// `AppConfig.mangaEInkThreshold` (150).
    @Published public var eInkThreshold = 150
    /// Whether the chapter title is hidden — upstream
    /// `AppConfig.hideMangaTitle`.
    @Published public var hideTitle = false

    /// Reads the display settings — upstream `ReadMangaActivity.onCreate`
    /// (`AppConfig.mangaColorFilter` / `enableMangaGray` / `enableMangaEInk`).
    public func refreshDisplay() {
        colorFilter = MangaSettings.colorFilter(environment.settings)
        isGray = environment.settings.bool(.enableMangaGray, default: false)
        isEInk = environment.settings.bool(.enableMangaEInk, default: false)
        eInkThreshold = environment.settings.int(.mangaEInkThreshold, default: 150)
        hideTitle = environment.settings.bool(.hideMangaTitle, default: false)
        isHorizontalScroll = environment.settings.bool(.enableMangaHorizontalScroll, default: false)
    }

    // MARK: - The automatic page / the automatic scroll

    /// Turns the automatic page on or off — upstream
    /// `ReadMangaActivity.onCompatOptionsItemSelected` (`menu_enable_auto_page`):
    /// the automatic scroll is turned off, the two are exclusive.
    public func setAutoPage(_ enabled: Bool) {
        isAutoPage = enabled
        if enabled {
            isAutoScroll = false
        }
        restartAutoTimer()
    }

    /// Turns the automatic scroll on or off — upstream
    /// `ReadMangaActivity.onCompatOptionsItemSelected` (`menu_enable_auto_scroll`):
    /// the automatic page is turned off, the two are exclusive.
    public func setAutoScroll(_ enabled: Bool) {
        isAutoScroll = enabled
        if enabled {
            isAutoPage = false
        }
        restartAutoTimer()
    }

    /// The task of the automatic page / scroll — upstream `ScrollTimer`
    /// (`ui/book/manga/recyclerview/ScrollTimer.kt`): the page is turned every
    /// `mangaAutoPageSpeed` seconds.
    private var autoTask: Task<Void, Never>?

    /// Starts or stops the timer — upstream `ScrollTimer.isEnabledPage`.
    private func restartAutoTimer() {
        autoTask?.cancel()
        autoTask = nil
        guard isAutoPage || isAutoScroll else { return }
        let speed = max(1, environment.settings.int(.mangaAutoPageSpeed, default: 3))
        autoTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(speed) * 1_000_000_000)
                if Task.isCancelled { break }
                self?.autoTick()
            }
        }
    }

    /// One tick of the timer — upstream `ScrollTimer.startScrollPage`
    /// (`callback.scrollPage()`).
    private func autoTick() {
        guard let chapter else { return }
        if pageIndex + 1 < chapter.imageCount {
            pageIndex += 1
        } else if currentChapterIndex + 1 < chapters.count {
            Task { await moveToNextChapter() }
        }
    }

    /// Stops the timer when the reader is closed.
    public func stopAutoTimer() {
        autoTask?.cancel()
        autoTask = nil
    }

    // MARK: - The display toggles

    /// Turns the e-ink mode on or off — upstream `menu_epaper_manga`: the
    /// grey mode is turned off, the two are exclusive.
    public func setEInk(_ enabled: Bool) {
        environment.settings.set(enabled, for: .enableMangaEInk)
        if enabled {
            environment.settings.set(false, for: .enableMangaGray)
        }
        refreshDisplay()
    }

    /// Turns the grey mode on or off — upstream `menu_gray_manga`: the e-ink
    /// mode is turned off, the two are exclusive.
    public func setGray(_ enabled: Bool) {
        environment.settings.set(enabled, for: .enableMangaGray)
        if enabled {
            environment.settings.set(false, for: .enableMangaEInk)
        }
        refreshDisplay()
    }

    /// Changes the threshold of the e-ink mode — upstream
    /// `MangaEpaperDialog` (`callback.updateEepaper(value)`).
    public func setEInkThreshold(_ value: Int) {
        environment.settings.set(max(0, min(255, value)), for: .mangaEInkThreshold)
        refreshDisplay()
    }

    /// Changes the zoom — upstream `WebtoonRecyclerView` (the pinch gesture).
    public func setZoom(_ rate: Double) {
        zoom = MangaMode.Zoom.clamp(rate)
    }

    /// Reloads the current chapter — upstream
    /// `ReadMangaActivity.viewModel.refreshContentDur`.
    public func reloadChapter() async {
        await loadChapter(at: currentChapterIndex)
    }

    /// Changes the screen brightness.
    public func setBrightness(percent: Int) {
        Task { @MainActor in system.setBrightness(percent: percent) }
    }

    /// Loads the chapter — upstream `ReadMangaActivity.loadChapterImages`.
    public func loadChapter(at index: Int) async {
        guard index >= 0, index < chapters.count else { return }
        currentChapterIndex = index
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let content = try await loadContent(of: chapters[index])
            chapter = MangaAssembler.chapter(
                chapters[index],
                chapterSize: chapters.count,
                content: content,
                hideTitle: environment.settings.bool(SettingsKey.hideMangaTitle, default: false)
            )
        } catch {
            errorMessage = error.localizedDescription
            chapter = nil
        }
    }

    /// The content of a chapter — the image tags survive the content
    /// processing because upstream `HtmlFormatter.formatKeepImg` keeps them.
    private func loadContent(of chapter: BookChapter) async throws -> String {
        if let cached = environment.cacheStorage?.content(book: book, chapter: chapter), !cached.isEmpty {
            return cached
        }
        guard let source = try environment.source(for: book) else {
            throw AppEnvironmentError.sourceNotFound(book.origin)
        }
        return try await environment.loadContent(book: book, chapter: chapter, source: source)
    }

    /// The footer text — upstream `ReadMangaActivity.upInfoBar`.
    ///
    /// The parts that the footer configuration hides are left out — upstream
    /// `MangaFooterConfig`.
    public func footerText(pageIndex: Int) -> String {
        guard let chapter, chapter.imageCount > 0 else { return "" }
        let config = MangaSettings.footerConfig(environment.settings)
        if config.hideFooter { return "" }
        var parts: [String] = []
        if !config.hideChapter, !config.hideChapterName {
            parts.append(chapter.title)
        }
        if !config.hidePageNumber {
            parts.append("\(pageIndex + 1)/\(chapter.imageCount)")
        }
        parts.append("\(currentChapterIndex + 1)/\(chapters.count)")
        if !config.hideProgressRatio {
            parts.append(MangaAssembler.footerText(
                chapterTitle: chapter.title,
                chapterIndex: currentChapterIndex,
                chapterSize: chapters.count,
                chapterPos: pageIndex,
                imageCount: chapter.imageCount,
                isLastItem: currentChapterIndex == chapters.count - 1
            ).split(separator: " ").last.map(String.init) ?? "")
        }
        return parts.joined(separator: "  ")
    }

    /// Handles a tap — upstream `WebtoonFrame`:
    /// the middle opens the menu, the bottom left goes back, the bottom right
    /// goes forward.
    public func handleTap(x: Double, y: Double, width: Double, height: Double) -> MangaTapAction {
        switch MangaMode.TapZone.zone(x: x, y: y, width: width, height: height) {
        case .middle: return .menu
        case .bottomLeft: return .previous
        case .bottomRight: return .next
        case .other: return .none
        }
    }
}

/// The action of a tap in the manga reader.
public enum MangaTapAction: Equatable {
    case none
    case menu
    case previous
    case next
}

/// The manga reader view.
public struct MangaReaderView: View {

    @ObservedObject var controller: MangaReaderController
    @State private var showsMenu = false

    public init(controller: MangaReaderController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            if controller.isLoading {
                ProgressView("加载中")
            } else if let chapter = controller.chapter {
                GeometryReader { proxy in
                    ScrollViewReader { scrollProxy in
                        ScrollView(controller.isHorizontalScroll ? .horizontal : .vertical) {
                            ForEach(Array(chapter.pages.enumerated()), id: \.offset) { index, page in
                                MangaPageView(
                                    page: page,
                                    zoom: controller.zoom,
                                    colorFilter: controller.colorFilter,
                                    isGray: controller.isGray,
                                    isEInk: controller.isEInk,
                                    eInkThreshold: controller.eInkThreshold
                                )
                                    .id(index)
                            }
                        }
                        .onTapGesture { position in
                            // Upstream `WebtoonFrame` — the middle opens the
                            // menu, the bottom left goes back, the bottom right
                            // goes forward.
                            switch controller.handleTap(
                                x: Double(position.x),
                                y: Double(position.y),
                                width: Double(proxy.size.width),
                                height: Double(proxy.size.height)
                            ) {
                            case .menu:
                                controller.isMenuVisible.toggle()
                            case .previous:
                                Task { await controller.moveToPrevChapter() }
                            case .next:
                                Task { await controller.moveToNextChapter() }
                            case .none:
                                break
                            }
                        }
                        // The page turn scrolls to the page — upstream
                        // `ReadManga.scrollToPage`.
                        .onChange(of: controller.pageIndex) { _, index in
                            scrollToPage(index, proxy: scrollProxy)
                        }
                        // The pinch zoom — upstream `WebtoonRecyclerView.onScale`.
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    guard !controller.environment.settings.bool(.disableMangaScale, default: true) else { return }
                                    if pinchBase == nil {
                                        pinchBase = controller.zoom
                                    }
                                    controller.setZoom((pinchBase ?? controller.zoom) * Double(value.magnification))
                                }
                                .onEnded { _ in
                                    pinchBase = nil
                                }
                        )
                    }
                }
            } else {
                EmptyState(text: controller.errorMessage ?? "没有可显示的图片")
            }
            footer
        }
        .overlay(alignment: .bottom) {
            // The menu of the manga reader — upstream `MangaMenu`.
            if controller.isMenuVisible {
                MangaMenuView(
                    controller: controller,
                    onClose: { controller.isMenuVisible = false },
                    onShowBookInfo: { showsBookInfo = true }
                )
            }
        }
        .sheet(isPresented: $showsBookInfo) {
            if let model = controller.model {
                NavigationStack {
                    BookDetailView(model: model, book: controller.book)
                }
            }
        }
        .onAppear {
            controller.refreshDisplay()
            Task {
                await controller.loadChapter(at: controller.currentChapterIndex)
            }
        }
    }

    /// Whether the book info is shown — upstream
    /// `MangaMenu.CallBack.openBookInfoActivity`.
    @State private var showsBookInfo = false
    /// The zoom at the start of the pinch gesture — upstream
    /// `WebtoonRecyclerView.onScale` (the scale is relative to the start).
    @State private var pinchBase: Double?

    /// Scrolls to the page — upstream `ReadManga.scrollToPage`.
    ///
    /// The automatic scroll scrolls smoothly, the automatic page jumps.
    private func scrollToPage(_ index: Int, proxy: ScrollViewProxy) {
        if controller.isAutoScroll {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo(index, anchor: .leading)
            }
        } else {
            proxy.scrollTo(index, anchor: .leading)
        }
    }

    private var footer: some View {
        HStack {
            Button("上一章") {
                Task { await controller.moveToPrevChapter() }
            }
            Spacer()
            Text(controller.footerText(pageIndex: controller.pageIndex))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Button("下一章") {
                Task { await controller.moveToNextChapter() }
            }
        }
        .padding(16)
    }
}

/// One page of the manga reader.
struct MangaPageView: View {

    let page: MangaPage
    let zoom: Double
    /// The colour filter — upstream `MangaAdapter.setImageColorFilter`.
    var colorFilter = MangaColorFilter()
    /// Whether the page is grey — upstream `GrayscaleTransformation`.
    var isGray = false
    /// Whether the page is shown as on an e-ink screen — upstream
    /// `EpaperTransformation`.
    var isEInk = false
    /// The threshold of the e-ink mode.
    var eInkThreshold = 128

    var body: some View {
        Group {
            if let url = page.imageURL, let remote = URL(string: url) {
                AsyncImage(url: remote) { phase in
                    if case let .success(image) = phase {
                        return AnyView(scaled(filtered(image), by: zoom))
                    } else {
                        return AnyView(
                            Text("加载中")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        )
                    }
                }
            } else {
                Text(title)
                    .font(.system(size: 16))
                    .padding(.vertical, 24)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// The page with the filters of the manga reader.
    @ViewBuilder
    private func filtered(_ image: Image) -> some View {
        if isEInk {
            // The upstream binarises the pixels (below the threshold → black);
            // the SwiftUI contrast with the pivot at the mid grey is the
            // closest equivalent.
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .grayscale(1)
                .contrast(Self.contrast(threshold: eInkThreshold))
        } else if isGray {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .grayscale(1)
        } else if !colorFilter.isIdentity {
            let multipliers = colorFilter.multipliers
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
                .colorMultiply(
                    Color(
                        red: multipliers.red,
                        green: multipliers.green,
                        blue: multipliers.blue
                    )
                )
        } else {
            image
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    /// The contrast that approximates the binarisation at the threshold.
    static func contrast(threshold: Int) -> Double {
        let normalized = Double(threshold) / 255.0
        let distance = abs(normalized - 0.5)
        return max(1, min(12, 0.5 / max(distance, 0.04)))
    }

    private var title: String {
        if case let .loading(title, _) = page.kind { return title }
        return ""
    }
}
