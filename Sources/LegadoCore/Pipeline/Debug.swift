//
//  Debug.swift
//  LegadoCore
//
//  The port of app/src/main/java/io/legado/app/model/Debug.kt.
//
//  Upstream the debug output is a stream of log lines that the web debug
//  sockets forward to the browser. Every line is prefixed with the elapsed
//  time `[mm:ss.SSS]` and carries one of the markers ︾ (start), ︽ (done),
//  ⇒ (result) and ≡ (info). The line state tells the socket whether the
//  session is over: 1 = normal, -1 = error, 1000 = end.
//
//  The port keeps the same protocol so that a browser (or the port's own
//  WebSocket server) can render the debug output unchanged.
//

import Foundation

// MARK: - The log

/// The state of a debug log line — upstream `Debug.Callback.printLog`.
public enum DebugLogState: Int, Sendable {
    /// A normal line.
    case normal = 1
    /// An error line; the debug session is over.
    case error = -1
    /// The last line of the session.
    case end = 1000
}

/// The states that are never printed (upstream `notPrintState`).
public let debugNotPrintedStates: Set<Int> = [10, 20, 30, 40]

/// The receiver of the debug output.
public protocol DebugLogSink: AnyObject {
    /// Called for every log line.
    func printLog(state: Int, message: String)
}

/// A sink that forwards the lines to a closure.
public final class ClosureDebugSink: DebugLogSink {

    private let handler: (Int, String) -> Void

    /// Creates a sink.
    public init(_ handler: @escaping (Int, String) -> Void) {
        self.handler = handler
    }

    public func printLog(state: Int, message: String) {
        handler(state, message)
    }
}

// MARK: - The debugger

/// The source debugger — upstream `Debug`.
public final class SourceDebugger {

    /// The marker of a "start" line.
    public static let startMarker = "︾"
    /// The marker of a "done" line.
    public static let doneMarker = "︽"
    /// The marker of a "result" line.
    public static let resultMarker = "⇒"
    /// The marker of an "info" line.
    public static let infoMarker = "≡"

    /// The sink the log lines are sent to.
    ///
    /// Upstream `Debug.callback` is a strong reference, so the sink is held
    /// strongly here too — a weak sink would vanish before the first line.
    public var sink: DebugLogSink?

    /// The source that is being debugged.
    public private(set) var sourceUrl: String?

    /// The moment the debug started; the log lines show the elapsed time.
    public private(set) var startTime: Date

    private let dateProvider: () -> Date

    /// Creates a debugger.
    ///
    /// - Parameters:
    ///   - sink: the receiver of the log lines.
    ///   - dateProvider: the clock (the tests inject a fixed one).
    public init(sink: DebugLogSink? = nil, dateProvider: @escaping () -> Date = { Date() }) {
        self.sink = sink
        self.dateProvider = dateProvider
        self.startTime = dateProvider()
    }

    /// Restarts the clock.
    public func resetClock() {
        startTime = dateProvider()
    }

    /// Formats the elapsed time — upstream `SimpleDateFormat("[mm:ss.SSS]")`.
    public func elapsedText() -> String {
        let interval = max(0, dateProvider().timeIntervalSince(startTime))
        let totalMilliseconds = Int((interval * 1000).rounded())
        let minutes = (totalMilliseconds / 60_000) % 60
        let seconds = (totalMilliseconds / 1_000) % 60
        let milliseconds = totalMilliseconds % 1_000
        return String(format: "[%02d:%02d.%03d]", minutes, seconds, milliseconds)
    }

    /// Writes a log line.
    ///
    /// - Parameters:
    ///   - message: the message.
    ///   - state: the state of the line.
    ///   - showTime: whether the elapsed time is prefixed.
    public func log(_ message: String, state: Int = DebugLogState.normal.rawValue, showTime: Bool = true) {
        guard let sink else { return }
        let text = showTime ? "\(elapsedText()) \(message)" : message
        sink.printLog(state: state, message: text)
    }

    /// Writes a log line for a specific source.
    public func log(
        _ message: String,
        sourceUrl: String,
        state: Int = DebugLogState.normal.rawValue,
        showTime: Bool = true
    ) {
        self.sourceUrl = sourceUrl
        log(message, state: state, showTime: showTime)
    }

    // MARK: - The book source debug

    /// Debugs a book source — upstream `Debug.startDebug(scope, bookSource, key)`.
    ///
    /// The key decides what is parsed:
    /// - an absolute URL → the detail page,
    /// - a URL containing `::` → the explore page,
    /// - a key starting with `++` → the table of contents,
    /// - a key starting with `--` → the chapter content,
    /// - anything else → the search page.
    ///
    /// - Returns: the state of the last line.
    @discardableResult
    public func debugBookSource(
        _ source: BookSource,
        key: String,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async -> Int {
        sourceUrl = source.bookSourceUrl
        resetClock()
        let dependencies = capturing(dependencies)
        if key.hasPrefix("http://") || key.hasPrefix("https://") {
            var book = Book()
            book.origin = source.bookSourceUrl
            book.bookUrl = key
            log("\(Self.resultMarker)开始访问详情页:\(key)", sourceUrl: source.bookSourceUrl)
            return await debugInfo(source: source, book: book, dependencies: dependencies)
        }
        if key.contains("::") {
            let url = String(key[key.range(of: "::")!.upperBound...])
            log("\(Self.resultMarker)开始访问发现页:\(url)", sourceUrl: source.bookSourceUrl)
            return await debugExplore(source: source, url: url, dependencies: dependencies)
        }
        if key.hasPrefix("++") {
            let url = String(key.dropFirst(2))
            var book = Book()
            book.origin = source.bookSourceUrl
            book.tocUrl = url
            log("\(Self.resultMarker)开始访目录页:\(url)", sourceUrl: source.bookSourceUrl)
            return await debugToc(source: source, book: book, dependencies: dependencies)
        }
        if key.hasPrefix("--") {
            let url = String(key.dropFirst(2))
            var book = Book()
            book.origin = source.bookSourceUrl
            log("\(Self.resultMarker)开始访正文页:\(url)", sourceUrl: source.bookSourceUrl)
            var chapter = BookChapter()
            chapter.title = "调试"
            chapter.url = url
            return await debugContent(
                source: source,
                book: book,
                chapter: chapter,
                nextChapterUrl: nil,
                dependencies: dependencies
            )
        }
        log("\(Self.resultMarker)开始搜索关键字:\(key)", sourceUrl: source.bookSourceUrl)
        return await debugSearch(source: source, key: key, dependencies: dependencies)
    }

    /// Wraps the dependencies so that the raw HTML of every fetched page is
    /// written to the log with the upstream's states (10 = the search page,
    /// 20 = the detail page, 30 = the table of contents, 40 = the chapter
    /// content) — upstream `Debug.log(sourceUrl, body, state = 10/20/30/40)`.
    ///
    /// The upstream's `BookSourceDebugModel` intercepts those states and shows
    /// them in the "原始HTML" dialogs instead of the log list.
    private func capturing(_ dependencies: AnalyzeUrlDependencies) -> AnalyzeUrlDependencies {
        var dependencies = dependencies
        let previous = dependencies.debugCapture
        dependencies.debugCapture = { [weak self] state, body in
            previous?(state, body)
            self?.log(body, state: state)
        }
        return dependencies
    }

    private func debugSearch(
        source: BookSource,
        key: String,
        dependencies: AnalyzeUrlDependencies
    ) async -> Int {
        log("\(Self.startMarker)开始解析搜索页", sourceUrl: source.bookSourceUrl)
        do {
            let books = try await WebBook.searchBook(
                bookSource: source,
                key: key,
                dependencies: dependencies
            )
            guard let first = books.first else {
                log("\(Self.doneMarker)未获取到书籍", state: DebugLogState.error.rawValue)
                return DebugLogState.error.rawValue
            }
            log("\(Self.doneMarker)搜索页解析完成")
            log("", showTime: false)
            return await debugInfo(source: source, book: first.toBook(), dependencies: dependencies)
        } catch {
            log(error.debugDescription, state: DebugLogState.error.rawValue)
            return DebugLogState.error.rawValue
        }
    }

    private func debugExplore(
        source: BookSource,
        url: String,
        dependencies: AnalyzeUrlDependencies
    ) async -> Int {
        log("\(Self.startMarker)开始解析发现页", sourceUrl: source.bookSourceUrl)
        do {
            let books = try await WebBook.exploreBook(
                bookSource: source,
                url: url,
                dependencies: dependencies
            )
            guard let first = books.first else {
                log("\(Self.doneMarker)未获取到书籍", state: DebugLogState.error.rawValue)
                return DebugLogState.error.rawValue
            }
            log("\(Self.doneMarker)发现页解析完成")
            log("", showTime: false)
            return await debugInfo(source: source, book: first.toBook(), dependencies: dependencies)
        } catch {
            log(error.debugDescription, state: DebugLogState.error.rawValue)
            return DebugLogState.error.rawValue
        }
    }

    private func debugInfo(
        source: BookSource,
        book: Book,
        dependencies: AnalyzeUrlDependencies
    ) async -> Int {
        if !book.tocUrl.isEmpty {
            log("\(Self.infoMarker)已获取目录链接,跳过详情页", sourceUrl: source.bookSourceUrl)
            log("", showTime: false)
            return await debugToc(source: source, book: book, dependencies: dependencies)
        }
        log("\(Self.startMarker)开始解析详情页", sourceUrl: source.bookSourceUrl)
        do {
            // The upstream mutates the book in place; Swift returns a copy, so
            // the parsed book has to be used for the following steps.
            let parsed = try await WebBook.getBookInfo(
                bookSource: source,
                book: book,
                dependencies: dependencies
            )
            log("\(Self.doneMarker)详情页解析完成")
            log("", showTime: false)
            if parsed.isWebFile {
                log("\(Self.infoMarker)文件类书源跳过解析目录", state: DebugLogState.end.rawValue)
                return DebugLogState.end.rawValue
            }
            return await debugToc(source: source, book: parsed, dependencies: dependencies)
        } catch {
            log(error.debugDescription, state: DebugLogState.error.rawValue)
            return DebugLogState.error.rawValue
        }
    }

    private func debugToc(
        source: BookSource,
        book: Book,
        dependencies: AnalyzeUrlDependencies
    ) async -> Int {
        log("\(Self.startMarker)开始解析目录页", sourceUrl: source.bookSourceUrl)
        do {
            let result = try await WebBook.getChapterList(
                bookSource: source,
                book: book,
                dependencies: dependencies
            )
            log("\(Self.doneMarker)目录页解析完成")
            log("", showTime: false)
            let toc = result.chapters.filter { !($0.isVolume && $0.url.hasPrefix($0.title)) }
            guard let first = toc.first else {
                log("\(Self.infoMarker)没有正文章节")
                return DebugLogState.normal.rawValue
            }
            let nextChapterUrl = toc.count > 1 ? toc[1].url : first.url
            return await debugContent(
                source: source,
                book: result.book,
                chapter: first,
                nextChapterUrl: nextChapterUrl,
                dependencies: dependencies
            )
        } catch {
            log(error.debugDescription, state: DebugLogState.error.rawValue)
            return DebugLogState.error.rawValue
        }
    }

    private func debugContent(
        source: BookSource,
        book: Book,
        chapter: BookChapter,
        nextChapterUrl: String?,
        dependencies: AnalyzeUrlDependencies
    ) async -> Int {
        log("\(Self.startMarker)开始解析正文页", sourceUrl: source.bookSourceUrl)
        do {
            _ = try await WebBook.getContent(
                bookSource: source,
                book: book,
                bookChapter: chapter,
                nextChapterUrl: nextChapterUrl,
                dependencies: dependencies
            )
            log("\(Self.doneMarker)正文页解析完成", state: DebugLogState.end.rawValue)
            return DebugLogState.end.rawValue
        } catch {
            log(error.debugDescription, state: DebugLogState.error.rawValue)
            return DebugLogState.error.rawValue
        }
    }

    // MARK: - The RSS source debug

    /// Debugs an RSS source — upstream `Debug.startDebug(scope, rssSource)`.
    ///
    /// - Returns: the state of the last line.
    @discardableResult
    public func debugRssSource(
        _ source: RssSource,
        key: String? = nil,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies(),
        scriptEngine: RuleScriptEngine? = nil
    ) async -> Int {
        sourceUrl = source.sourceUrl
        resetClock()
        let dependencies = capturing(dependencies)
        log("\(Self.startMarker)开始解析", sourceUrl: source.sourceUrl)
        let sortUrl = source.sortUrl ?? source.sourceUrl
        do {
            let page = try await Rss.articles(
                sortName: source.sourceName,
                sortUrl: sortUrl,
                rssSource: source,
                page: 1,
                dependencies: dependencies,
                scriptEngine: scriptEngine
            )
            if page.articles.isEmpty {
                log("\(Self.resultMarker)列表页解析成功，为空", sourceUrl: source.sourceUrl)
                log("\(Self.doneMarker)解析完成", state: DebugLogState.end.rawValue)
                return DebugLogState.end.rawValue
            }
            let ruleContent = source.ruleContent ?? ""
            let hasArticlesRule = !(source.ruleArticles ?? "").isEmpty
            let hasDescriptionRule = !(source.ruleDescription ?? "").isEmpty
            if hasArticlesRule && !hasDescriptionRule {
                log("\(Self.doneMarker)列表页解析完成", sourceUrl: source.sourceUrl)
                log("", showTime: false)
                if ruleContent.isEmpty {
                    log("\(Self.resultMarker)内容规则为空，默认获取整个网页", state: DebugLogState.end.rawValue)
                    return DebugLogState.end.rawValue
                }
                return await debugRssContent(
                    source: source,
                    article: page.articles[0],
                    ruleContent: ruleContent,
                    dependencies: dependencies,
                    scriptEngine: scriptEngine
                )
            }
            log("\(Self.resultMarker)存在描述规则，不解析内容页", sourceUrl: source.sourceUrl)
            log("\(Self.doneMarker)解析完成", state: DebugLogState.end.rawValue)
            return DebugLogState.end.rawValue
        } catch {
            log(error.debugDescription, state: DebugLogState.error.rawValue)
            return DebugLogState.error.rawValue
        }
    }

    private func debugRssContent(
        source: RssSource,
        article: RssArticle,
        ruleContent: String,
        dependencies: AnalyzeUrlDependencies,
        scriptEngine: RuleScriptEngine?
    ) async -> Int {
        log("\(Self.startMarker)开始解析内容页", sourceUrl: source.sourceUrl)
        do {
            let content = try await Rss.content(
                article: article,
                ruleContent: ruleContent,
                rssSource: source,
                dependencies: dependencies,
                scriptEngine: scriptEngine
            )
            log(content, sourceUrl: source.sourceUrl)
            log("\(Self.doneMarker)内容页解析完成", state: DebugLogState.end.rawValue)
            return DebugLogState.end.rawValue
        } catch {
            log(error.debugDescription, state: DebugLogState.error.rawValue)
            return DebugLogState.error.rawValue
        }
    }
}

// MARK: - Helpers

extension Error {
    /// The description of the error — upstream `stackTraceStr`.
    ///
    /// The port's own errors carry their message in the associated value, so
    /// they are printed verbatim instead of the generic `NSError` text.
    var debugDescription: String {
        switch self {
        case let error as PipelineError:
            return String(describing: error)
        case let error as RssError:
            return String(describing: error)
        case let error as HttpError:
            return String(describing: error)
        default:
            let nsError = self as NSError
            return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
        }
    }
}
