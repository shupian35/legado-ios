import Foundation

/// The manga (image) mode — upstream `ui/book/manga/*` and
/// `model/ReadManga.kt`.
///
/// An image book (upstream `Book.isImage`) is read as a list of images: every
/// `<img>` of a chapter is one page.
public enum MangaMode {

    /// The zoom limits — upstream `WebtoonRecyclerView`:
    /// `MIN_RATE = 0.5f`, `DEFAULT_RATE = 1f`, `MAX_SCALE_RATE = 3f`,
    /// the double tap zooms to 2×, the zoom animation lasts 200 ms and the
    /// fling factor is 0.4.
    public enum Zoom {
        public static let minRate = 0.5
        public static let defaultRate = 1.0
        public static let maxRate = 3.0
        public static let doubleTapRate = 2.0
        public static let animationDuration = 0.2
        public static let flingFactor = 0.4

        /// Clamps a scale factor to the allowed range.
        public static func clamp(_ rate: Double) -> Double {
            min(maxRate, max(minRate, rate))
        }
    }

    /// The tap zones of the manga reader — upstream `WebtoonFrame.onSizeChanged`:
    /// the middle third (0.33…0.66) shows the menu, the bottom left goes to
    /// the previous page and the bottom right to the next page.
    public enum TapZone: String, CaseIterable, Sendable {
        case middle
        case bottomLeft
        case bottomRight
        case other

        /// The zone of a tap.
        public static func zone(x: Double, y: Double, width: Double, height: Double) -> TapZone {
            guard width > 0, height > 0 else { return .other }
            let fx = x / width
            let fy = y / height
            if fx > 0.33, fx < 0.66, fy > 0.33, fy < 0.66 { return .middle }
            if fx <= 0.33, fy >= 0.66 { return .bottomLeft }
            if fx >= 0.66, fy >= 0.66 { return .bottomRight }
            return .other
        }
    }
}

/// The kind of a manga page — upstream `BaseMangaPage` / `ReaderLoading`.
public enum MangaPageKind: Equatable, Sendable {
    /// An image page — upstream `MangaPage`.
    case image(url: String)
    /// A title page — upstream `ReaderLoading` (the "阅读 <chapter>" header
    /// and the "已读完 <chapter>" footer).
    case loading(title: String, isVolume: Bool = false)
}

/// A page of the manga reader.
public struct MangaPage: Equatable, Sendable {
    /// The kind of the page.
    public var kind: MangaPageKind
    /// The index of the chapter the page belongs to.
    public var chapterIndex: Int64
    /// The index of the page inside the chapter.
    public var index: Int
    /// The number of the images of the chapter.
    public var imageCount: Int
    /// The title of the chapter.
    public var chapterName: String

    public init(
        kind: MangaPageKind,
        chapterIndex: Int64,
        index: Int,
        imageCount: Int,
        chapterName: String
    ) {
        self.kind = kind
        self.chapterIndex = chapterIndex
        self.index = index
        self.imageCount = imageCount
        self.chapterName = chapterName
    }

    /// The image URL, if the page is an image.
    public var imageURL: String? {
        if case let .image(url) = kind { return url }
        return nil
    }
}

/// A chapter of the manga reader — upstream `MangaChapter`.
public struct MangaChapter: Equatable, Sendable {
    public var chapterIndex: Int64
    public var title: String
    public var pages: [MangaPage]
    public var imageCount: Int

    public init(chapterIndex: Int64, title: String, pages: [MangaPage], imageCount: Int) {
        self.chapterIndex = chapterIndex
        self.title = title
        self.pages = pages
        self.imageCount = imageCount
    }
}

/// The manga assembler — upstream `ReadManga.getManageChapter`.
public enum MangaAssembler {

    /// The image URLs of a chapter.
    ///
    /// Upstream `BookHelp.flowImages` resolves every `<img src>` against the
    /// chapter URL; `ReadManga.getManageChapter` then drops the **consecutive**
    /// duplicates (`distinctUntilChanged`).
    public static func imageURLs(in content: String, chapterURL: String) -> [String] {
        var urls: [String] = []
        for source in BookCacheStorage.imageSources(in: content, chapterURL: chapterURL) {
            let absolute = NetworkUtils.absoluteURL(base: chapterURL, source)
            if urls.last == absolute { continue }
            urls.append(absolute)
        }
        return urls
    }

    /// The pages of a chapter.
    ///
    /// - Parameters:
    ///   - chapter: the chapter.
    ///   - chapterSize: the number of the chapters of the book.
    ///   - content: the content of the chapter.
    ///   - hideTitle: the upstream pref `hideMangaTitle`.
    public static func chapter(
        _ chapter: BookChapter,
        chapterSize: Int,
        content: String,
        hideTitle: Bool = false
    ) -> MangaChapter {
        let urls = imageURLs(in: content, chapterURL: chapter.url)
        let imageCount = urls.count
        var pages: [MangaPage] = urls.enumerated().map { index, url in
            MangaPage(
                kind: .image(url: url),
                chapterIndex: chapter.index,
                index: index,
                imageCount: imageCount,
                chapterName: chapter.title
            )
        }
        if hideTitle, imageCount > 0 {
            return MangaChapter(
                chapterIndex: chapter.index,
                title: chapter.title,
                pages: pages,
                imageCount: imageCount
            )
        }
        if imageCount == 0, chapter.isVolume {
            pages = [
                MangaPage(
                    kind: .loading(title: chapter.title, isVolume: true),
                    chapterIndex: chapter.index,
                    index: -1,
                    imageCount: 0,
                    chapterName: chapter.title
                )
            ]
            return MangaChapter(
                chapterIndex: chapter.index,
                title: chapter.title,
                pages: pages,
                imageCount: 0
            )
        }
        pages.insert(
            MangaPage(
                kind: .loading(title: "阅读 \(chapter.title)"),
                chapterIndex: chapter.index,
                index: -1,
                imageCount: imageCount,
                chapterName: chapter.title
            ),
            at: 0
        )
        pages.append(
            MangaPage(
                kind: .loading(title: "已读完 \(chapter.title)"),
                chapterIndex: chapter.index,
                index: imageCount,
                imageCount: imageCount,
                chapterName: chapter.title
            )
        )
        return MangaChapter(
            chapterIndex: chapter.index,
            title: chapter.title,
            pages: pages,
            imageCount: imageCount
        )
    }

    /// The progress of the manga reader.
    ///
    /// Upstream `ReadMangaActivity.upInfoBar`:
    /// `chapterIndex * 1.0f / chapterSize + 1.0f / chapterSize * (chapterPos + 1) / imageCount`.
    public static func progressRatio(
        chapterIndex: Int,
        chapterSize: Int,
        chapterPos: Int,
        imageCount: Int
    ) -> Double {
        guard chapterSize > 0 else { return 0 }
        let base = Double(chapterIndex) / Double(chapterSize)
        guard imageCount > 0 else { return base }
        return base + Double(chapterPos + 1) / Double(chapterSize) / Double(imageCount)
    }

    /// The footer text of the manga reader — upstream `upInfoBar`.
    ///
    /// The percent is clamped to "99.9%" when it would print "100.0%" but the
    /// book is not finished.
    public static func footerText(
        chapterTitle: String,
        chapterIndex: Int,
        chapterSize: Int,
        chapterPos: Int,
        imageCount: Int,
        isLastItem: Bool
    ) -> String {
        let ratio = progressRatio(
            chapterIndex: chapterIndex,
            chapterSize: chapterSize,
            chapterPos: chapterPos,
            imageCount: imageCount
        )
        var percent = ratio * 100
        if percent >= 100, !isLastItem {
            percent = 99.9
        }
        let percentText = String(format: "%.1f%%", percent)
        return "\(chapterTitle)  \(chapterPos + 1)/\(imageCount)  \(chapterIndex + 1)/\(chapterSize)  \(percentText)"
    }
}

/// The colour filter of the manga reader — upstream
/// `ui/book/manga/config/MangaColorFilterConfig.kt`.
///
/// The values are applied as the matrix `(255 - x) / 255` per channel.
public struct MangaColorFilter: Equatable, Sendable {
    public var r: Int
    public var g: Int
    public var b: Int
    public var a: Int
    public var l: Int

    public init(r: Int = 0, g: Int = 0, b: Int = 0, a: Int = 0, l: Int = 0) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
        self.l = l
    }

    /// Whether the filter changes anything — upstream `toJson()` returns ""
    /// when all the values are zero.
    public var isIdentity: Bool {
        r == 0 && g == 0 && b == 0 && a == 0 && l == 0
    }

    /// The 4×5 colour matrix — upstream `MangaAdapter.applyColorFilter`.
    public var matrix: [Double] {
        let scale = 1.0 / 255.0
        return [
            (255 - Double(r)) * scale, 0, 0, 0, Double(r),
            0, (255 - Double(g)) * scale, 0, 0, Double(g),
            0, 0, (255 - Double(b)) * scale, 0, Double(b),
            0, 0, 0, (255 - Double(a)) * scale, Double(a)
        ]
    }

    /// The multipliers of the channels — `(255 - x) / 255`.
    public var multipliers: (red: Double, green: Double, blue: Double, alpha: Double) {
        (
            Double(255 - r) / 255.0,
            Double(255 - g) / 255.0,
            Double(255 - b) / 255.0,
            Double(255 - a) / 255.0
        )
    }

    /// The JSON of the configuration — upstream `MangaColorFilterConfig.toJson()`
    /// (an empty string when the filter does nothing).
    public func jsonString() -> String {
        if isIdentity { return "" }
        let object: [String: JSONValue] = [
            "r": .number(Double(r)),
            "g": .number(Double(g)),
            "b": .number(Double(b)),
            "a": .number(Double(a)),
            "l": .number(Double(l))
        ]
        return JSONValue.object(object).jsonString
    }

    /// Reads the configuration — upstream `GSON.fromJsonObject`.
    public static func parse(_ text: String?) -> MangaColorFilter {
        guard let text, !text.isEmpty else { return MangaColorFilter() }
        guard let value = try? JSONValue.parse(text), let object = value.objectValue else {
            return MangaColorFilter()
        }
        func number(_ key: String) -> Int {
            guard let raw = object[key] else { return 0 }
            switch raw {
            case let .number(value): return Int(value)
            case let .string(value): return Int(value) ?? 0
            default: return 0
            }
        }
        return MangaColorFilter(
            r: number("r"),
            g: number("g"),
            b: number("b"),
            a: number("a"),
            l: number("l")
        )
    }
}

/// The e-ink filter of the manga reader — upstream
/// `ui/book/manga/entities/EpaperTransformation.kt`.
///
/// The image is desaturated first and then binarised: a pixel whose gray
/// value is below the threshold becomes black, otherwise white.
public struct MangaEpaperFilter: Equatable, Sendable {
    /// The threshold (0…255) — upstream `AppConfig.mangaEInkThreshold` (150).
    public var threshold: Int

    public init(threshold: Int = 150) {
        self.threshold = max(0, min(255, threshold))
    }

    /// Whether a pixel becomes black.
    public func isBlack(red: Int, green: Int, blue: Int) -> Bool {
        let gray = (red * 299 + green * 587 + blue * 114) / 1000
        return gray < threshold
    }
}
