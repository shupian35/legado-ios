import Foundation

/// The tip types of the reader's header and footer.
///
/// Upstream: `app/src/main/java/io/legado/app/help/config/ReadTipConfig.kt`
/// (the constants `none`, `chapterTitle`, `time`, `battery`,
/// `batteryPercentage`, `page`, `totalProgress`, `pageAndTotal`, `bookName`,
/// `timeBattery`, `timeBatteryPercentage` and `totalProgress1`).
public enum ReaderTipType: Int, CaseIterable, Sendable, Identifiable {
    /// Nothing.
    case none = 0
    /// The name of the book.
    case bookName = 7
    /// The title of the chapter.
    case chapterTitle = 1
    /// The clock.
    case time = 2
    /// The battery level (a number).
    case battery = 3
    /// The battery level in percent.
    case batteryPercentage = 10
    /// The page number.
    case page = 4
    /// The progress of the whole book in percent.
    case totalProgress = 5
    /// The chapter number, `chapterIndex/chapterSize`.
    case totalProgress1 = 11
    /// The page number and the progress.
    case pageAndTotal = 6
    /// The clock and the battery level.
    case timeBattery = 8
    /// The clock and the battery level in percent.
    case timeBatteryPercentage = 9

    public var id: Int { rawValue }

    /// The order of the picker — upstream `ReadTipConfig.tipValues`.
    public static let pickerOrder: [ReaderTipType] = [
        .none, .bookName, .chapterTitle, .time, .battery, .batteryPercentage,
        .page, .totalProgress, .totalProgress1, .pageAndTotal, .timeBattery,
        .timeBatteryPercentage
    ]

    /// The name of the tip in the picker — upstream `R.array.read_tip`.
    public var displayName: String {
        switch self {
        case .none: return "空白"
        case .bookName: return "书名"
        case .chapterTitle: return "章节名"
        case .time: return "时间"
        case .battery: return "电量"
        case .batteryPercentage: return "电量%"
        case .page: return "页码"
        case .totalProgress: return "进度(%)"
        case .totalProgress1: return "进度(xx/yyy)"
        case .pageAndTotal: return "页码和进度"
        case .timeBattery: return "时间和电量"
        case .timeBatteryPercentage: return "时间和电量%"
        }
    }
}

/// The visibility of the header or the footer.
///
/// Upstream `ReadTipConfig.headerMode` / `footerMode`: the header has three
/// states (hidden while the status bar is visible, always visible, never
/// visible) and the footer two (visible, hidden).
public enum ReaderTipMode: Int, CaseIterable, Sendable, Identifiable {
    /// The header: hidden while the status bar is visible. The footer: shown.
    case automatic = 0
    /// Always visible.
    case always = 1
    /// Never visible.
    case never = 2

    public var id: Int { rawValue }

    /// The name in the picker.
    public var displayName: String {
        switch self {
        case .automatic: return "跟随状态栏"
        case .always: return "显示"
        case .never: return "隐藏"
        }
    }

    /// Whether the tip is drawn.
    ///
    /// - Parameter statusBarVisible: whether the system status bar is visible
    ///   (the header only).
    public func isVisible(statusBarVisible: Bool = false) -> Bool {
        switch self {
        case .automatic: return !statusBarVisible
        case .always: return true
        case .never: return false
        }
    }
}

/// The values the tips are rendered from.
public struct ReaderTipContext: Sendable, Equatable {
    /// The name of the book — upstream `ReadBook.book?.name`.
    public var bookName: String
    /// The title of the chapter — upstream `textPage.title`.
    public var chapterTitle: String
    /// The index of the page (0 based) — upstream `textPage.index`.
    public var pageIndex: Int
    /// The number of the pages of the chapter — upstream `textPage.pageSize`.
    public var pageSize: Int
    /// The index of the chapter (0 based) — upstream `textPage.chapterIndex`.
    public var chapterIndex: Int
    /// The number of the chapters — upstream `textPage.chapterSize`.
    public var chapterSize: Int
    /// The progress of the whole book — upstream `textPage.readProgress`.
    public var readProgress: String
    /// Whether the chapter is completely loaded — upstream
    /// `textChapter.isCompleted`. The page count is only exact then.
    public var isChapterCompleted: Bool
    /// The current time.
    public var time: Date
    /// The battery level in percent.
    public var batteryLevel: Int

    public init(
        bookName: String = "",
        chapterTitle: String = "",
        pageIndex: Int = 0,
        pageSize: Int = 0,
        chapterIndex: Int = 0,
        chapterSize: Int = 0,
        readProgress: String = "",
        isChapterCompleted: Bool = true,
        time: Date = Date(),
        batteryLevel: Int = 100
    ) {
        self.bookName = bookName
        self.chapterTitle = chapterTitle
        self.pageIndex = pageIndex
        self.pageSize = pageSize
        self.chapterIndex = chapterIndex
        self.chapterSize = chapterSize
        self.readProgress = readProgress
        self.isChapterCompleted = isChapterCompleted
        self.time = time
        self.batteryLevel = batteryLevel
    }
}

/// Renders the reader's header and footer tips.
///
/// Upstream `app/src/main/java/io/legado/app/ui/book/read/page/PageView.kt`:
/// `setProgress` (the book name, the title, the progress, the chapter number
/// and the page number), `upTime` (the clock), `upBattery` (the battery level
/// and its percentage) and `upTimeBattery` (the two together).
public enum ReaderTipRenderer {

    /// The clock format — upstream `AppConst.timeFormat` = `HH:mm`.
    public static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// The page number of a page.
    ///
    /// Upstream `PageView.setProgress`: the exact count when the chapter is
    /// completely loaded, `~count` while it is still loading and `-` when the
    /// count is not known yet.
    public static func pageText(index: Int, pageSize: Int, isChapterCompleted: Bool) -> String {
        if isChapterCompleted {
            return "\(index + 1)/\(pageSize)"
        }
        if pageSize <= 0 {
            return "\(index + 1)/-"
        }
        return "\(index + 1)/~\(pageSize)"
    }

    /// The progress of the whole book — upstream `TextPage.readProgress`
    /// (the `DecimalFormat("0.0%")` of the upstream: one decimal and a
    /// percent sign).
    ///
    /// - Parameters:
    ///   - chapterIndex: the index of the chapter (0 based).
    ///   - chapterSize: the number of the chapters.
    ///   - pageIndex: the index of the page (0 based).
    ///   - pageSize: the number of the pages of the chapter.
    public static func readProgress(
        chapterIndex: Int,
        chapterSize: Int,
        pageIndex: Int,
        pageSize: Int
    ) -> String {
        guard chapterSize > 0, !(pageSize == 0 && chapterIndex == 0) else { return "0.0%" }
        if pageSize == 0 {
            return percent(Double(chapterIndex + 1) / Double(chapterSize))
        }
        let value = Double(chapterIndex) / Double(chapterSize)
            + 1.0 / Double(chapterSize) * Double(pageIndex + 1) / Double(pageSize)
        var text = percent(value)
        // The upstream clamps the progress to 99.9 % when the book is not
        // completely read yet.
        if text == "100.0%" && (chapterIndex + 1 != chapterSize || pageIndex + 1 != pageSize) {
            text = "99.9%"
        }
        return text
    }

    /// Formats a ratio as the upstream's `DecimalFormat("0.0%")`.
    private static func percent(_ value: Double) -> String {
        let scaled = (value * 1000).rounded() / 10
        return String(format: "%.1f%%", scaled)
    }

    /// The text of a tip.
    ///
    /// - Returns: `nil` for the `none` tip.
    public static func text(for type: ReaderTipType, context: ReaderTipContext) -> String? {
        switch type {
        case .none:
            return nil
        case .bookName:
            return context.bookName
        case .chapterTitle:
            return context.chapterTitle
        case .time:
            return formatTime(context.time)
        case .battery:
            return "\(context.batteryLevel)"
        case .batteryPercentage:
            return "\(context.batteryLevel)%"
        case .page:
            return pageText(
                index: context.pageIndex,
                pageSize: context.pageSize,
                isChapterCompleted: context.isChapterCompleted
            )
        case .totalProgress:
            return context.readProgress
        case .totalProgress1:
            return "\(context.chapterIndex + 1)/\(context.chapterSize)"
        case .pageAndTotal:
            return "\(pageText(index: context.pageIndex, pageSize: context.pageSize, isChapterCompleted: context.isChapterCompleted))  \(context.readProgress)"
        case .timeBattery:
            return "\(formatTime(context.time))  \(context.batteryLevel)"
        case .timeBatteryPercentage:
            return "\(formatTime(context.time)) \(context.batteryLevel)%"
        }
    }

    /// The three tips of a row — the left, the middle and the right.
    ///
    /// Upstream `PageView.upTipStyle`: every one of the six slots (the header
    /// and the footer, each with a left / middle / right) holds one tip type.
    public struct Row: Sendable, Equatable {
        public var left: ReaderTipType
        public var middle: ReaderTipType
        public var right: ReaderTipType

        public init(left: ReaderTipType = .none, middle: ReaderTipType = .none, right: ReaderTipType = .none) {
            self.left = left
            self.middle = middle
            self.right = right
        }
    }

    /// The header and the footer of the reader.
    public struct Layout: Sendable, Equatable {
        public var headerMode: ReaderTipMode
        public var footerMode: ReaderTipMode
        public var header: Row
        public var footer: Row

        public init(
            headerMode: ReaderTipMode = .automatic,
            footerMode: ReaderTipMode = .always,
            header: Row = Row(),
            footer: Row = Row()
        ) {
            self.headerMode = headerMode
            self.footerMode = footerMode
            self.header = header
            self.footer = footer
        }

        /// Whether the header is drawn.
        public func showsHeader(statusBarVisible: Bool = false) -> Bool {
            headerMode.isVisible(statusBarVisible: statusBarVisible)
        }

        /// Whether the footer is drawn.
        public func showsFooter() -> Bool {
            footerMode.isVisible()
        }
    }
}
