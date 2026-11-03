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

    public let environment: AppEnvironment
    public let book: Book
    public let chapters: [BookChapter]
    public var currentChapterIndex: Int = 0

    public init(environment: AppEnvironment, book: Book, chapters: [BookChapter]) {
        self.environment = environment
        self.book = book
        self.chapters = chapters
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
    public func footerText(pageIndex: Int) -> String {
        guard let chapter, chapter.imageCount > 0 else { return "" }
        return MangaAssembler.footerText(
            chapterTitle: chapter.title,
            chapterIndex: currentChapterIndex,
            chapterSize: chapters.count,
            chapterPos: pageIndex,
            imageCount: chapter.imageCount,
            isLastItem: currentChapterIndex == chapters.count - 1
        )
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
    @State private var pageIndex = 0
    @State private var showsMenu = false

    public init(controller: MangaReaderController) {
        self.controller = controller
    }

    public var body: some View {
        VStack(spacing: 0) {
            if controller.isLoading {
                ProgressView("加载中")
            } else if let chapter = controller.chapter {
                ScrollView {
                    ForEach(Array(chapter.pages.enumerated()), id: \.offset) { index, page in
                        MangaPageView(page: page, zoom: controller.zoom)
                            .id(index)
                    }
                }
            } else {
                EmptyState(text: controller.errorMessage ?? "没有可显示的图片")
            }
            footer
        }
        .onAppear {
            Task {
                await controller.loadChapter(at: controller.currentChapterIndex)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("上一章") {
                Task {
                    await controller.loadChapter(at: max(0, controller.currentChapterIndex - 1))
                    pageIndex = 0
                }
            }
            Spacer()
            Text(controller.footerText(pageIndex: pageIndex))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer()
            Button("下一章") {
                Task {
                    await controller.loadChapter(
                        at: min(controller.chapters.count - 1, controller.currentChapterIndex + 1)
                    )
                    pageIndex = 0
                }
            }
        }
        .padding(16)
    }
}

/// One page of the manga reader.
struct MangaPageView: View {

    let page: MangaPage
    let zoom: Double

    var body: some View {
        Group {
            if let url = page.imageURL, let remote = URL(string: url) {
                AsyncImage(url: remote) { phase in
                    if case let .success(image) = phase {
                        return AnyView(image.resizable().aspectRatio(contentMode: .fit))
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

    private var title: String {
        if case let .loading(title, _) = page.kind { return title }
        return ""
    }
}
