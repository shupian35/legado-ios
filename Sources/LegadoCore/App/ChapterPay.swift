import Foundation

/// The result of the chapter purchase — upstream
/// `ReadBookActivity.payAction()` (`ui/book/read/ReadBookActivity.kt:1274`).
public enum ChapterPayResult: Equatable, Sendable {
    /// The script returned an absolute URL — the web view is opened.
    case openURL(String)
    /// The script returned "true" — the purchase succeeded and the table of
    /// contents is reloaded.
    case refreshTableOfContents
    /// The script returned something else — the upstream does nothing.
    case ignored(String)
}

/// The errors of the chapter purchase.
public enum ChapterPayError: Error, Equatable {
    /// The source has no `payAction` script.
    case noPayAction
}

/// The chapter purchase — upstream `ReadBookActivity.payAction()`.
///
/// The source's `contentRule.payAction` script is evaluated with the chapter
/// as the context (the base URL is the chapter's URL, the `chapter` and the
/// `book` variables are bound); an absolute URL opens the web view, "true"
/// means the purchase succeeded.
public enum ChapterPay {

    /// Runs the purchase script of the source.
    ///
    /// - Parameters:
    ///   - source: the source the book came from.
    ///   - book: the book.
    ///   - chapter: the chapter that is bought.
    ///   - dependencies: the script engine and the network.
    public static func pay(
        source: BookSource,
        book: Book,
        chapter: BookChapter,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) throws -> ChapterPayResult {
        let script = source.contentRule?.payAction ?? ""
        guard !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChapterPayError.noPayAction
        }
        let analyzeRule = AnalyzeRule(content: .text(""), baseUrl: chapter.url)
        analyzeRule.source = source.variableBox
        analyzeRule.chapter = chapter.variableBox
        analyzeRule.chapterInfo = chapter
        analyzeRule.bookInfo = book
        analyzeRule.bookName = book.name
        analyzeRule.chapterTitle = chapter.title
        analyzeRule.scriptEngine = dependencies.scriptEngine
        let value = try analyzeRule.evalJS(script, nil)
        let text = value.textValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if NetworkUtils.isAbsUrl(text) {
            return .openURL(text)
        }
        if text == "true" {
            return .refreshTableOfContents
        }
        return .ignored(text)
    }
}
