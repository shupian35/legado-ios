//
//  ContentEdit.swift
//  LegadoCore
//
//  The content editor of the reader — upstream
//  `ui/book/read/ContentEditDialog.kt` (170 lines).
//
//  The upstream dialog shows the PROCESSED content of the current chapter
//  (the title is NOT included — `includeTitle = false`), lets the user edit
//  it and saves it back into the cache:
//
//    * 保存 — `BookHelp.saveText(book, chapter, content)` + the chapter is
//      reloaded;
//    * 重置 — the cached content is deleted, the chapter is downloaded again
//      (only for a book that comes from a source) and the content is shown
//      again;
//    * 复制全部 — the title and the content go to the clipboard;
//    * the title of the toolbar edits the title of the chapter.
//
//  The port reproduces that behaviour; the view lives in `LegadoUI`.
//

import Foundation

/// The content editor of the reader.
public enum ContentEditService {

    /// The content of a chapter as the editor shows it — the processed text
    /// without the title.
    ///
    /// - Parameters:
    ///   - book: the book.
    ///   - chapter: the chapter.
    ///   - storage: the cache that holds the downloaded chapters.
    ///   - titleRules: the replace rules of the titles.
    ///   - contentRules: the replace rules of the content.
    /// - Returns: the content, or `nil` when the chapter was never
    ///   downloaded.
    public static func loadContent(
        book: Book,
        chapter: BookChapter,
        storage: BookCacheStorage,
        titleRules: [ReplaceRule] = [],
        contentRules: [ReplaceRule] = [],
        chineseConversionMode: ChineseConversionMode = .off,
        scriptEngine: RuleScriptEngine? = nil
    ) -> String? {
        guard let raw = storage.content(book: book, chapter: chapter) else { return nil }
        let processed = (try? ReplaceRuleEngine.processContent(
            book: book,
            chapter: chapter,
            content: raw,
            includeTitle: false,
            useReplace: book.useReplaceRule,
            chineseConvert: chineseConversionMode != .off,
            reSegment: false,
            titleRules: titleRules,
            contentRules: contentRules,
            conversionMode: chineseConversionMode,
            converter: DefaultChineseConverter(),
            scriptEngine: scriptEngine
        ))?.contents.joined(separator: "\n") ?? raw
        return processed
    }

    /// Saves the edited content into the cache — upstream `BookHelp.saveText`.
    ///
    /// The edited text is the PROCESSED text; the port stores it as it is
    /// (the reader processes it again, which is harmless — the same title is
    /// not added twice).
    public static func saveContent(
        book: Book,
        chapter: BookChapter,
        content: String,
        storage: BookCacheStorage
    ) throws {
        try storage.saveText(book: book, chapter: chapter, content: content)
    }

    /// Deletes the cached content and downloads the chapter again — upstream
    /// `ContentEditViewModel.initContent(reset = true)`.
    ///
    /// - Returns: the new content, or `nil` when the chapter could not be
    ///   downloaded.
    public static func resetContent(
        book: Book,
        chapter: BookChapter,
        storage: BookCacheStorage,
        source: BookSource?,
        dependencies: AnalyzeUrlDependencies = AnalyzeUrlDependencies()
    ) async -> String? {
        storage.deleteContent(book: book, chapter: chapter)
        if !book.isLocal, let source {
            // Upstream `WebBook.getContentAwait(bookSource, book, chapter)`.
            let content = try? await WebBook.getContent(
                bookSource: source,
                book: book,
                bookChapter: chapter,
                dependencies: dependencies
            )
            if let content {
                try? storage.saveText(book: book, chapter: chapter, content: content)
                return content
            }
        }
        return storage.content(book: book, chapter: chapter)
    }
}
