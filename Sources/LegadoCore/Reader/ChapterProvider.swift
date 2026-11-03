//
//  ChapterProvider.swift
//  LegadoCore
//
//  Port of the layout-driving part of
//  `app/src/main/java/io/legado/app/ui/book/read/page/provider/ChapterProvider.kt`
//  and `app/src/main/java/io/legado/app/help/book/ContentProcessor.kt`.
//
//  Upstream keeps the paints and metrics in `object ChapterProvider` (static
//  state) because the Android views read them from many places. The port keeps
//  the same split — `ChapterProvider.style` holds the measurements — but the
//  actual pagination work is a pure function of
//  (book, chapter, content, config, layout) so it can be unit tested.
//

import Foundation

/// Supplies the raw text of a chapter.
///
/// Upstream reads the cache directory first (`BookHelp.getContent`), then falls
/// back to `LocalBook` for local books and to the network for web books.
/// The iOS app injects the same chain from the outside so the core stays
/// free of platform I/O.
public protocol ChapterContentProviding: AnyObject {
    /// Returns the raw (unprocessed) text of `chapter`, or `nil` when the
    /// chapter has no text yet (for example a volume title chapter).
    func chapterContent(book: Book, chapter: BookChapter) async throws -> String?
}

public enum ChapterProviderError: Error, Equatable {
    case emptyContent
    case cancelled
}

/// Builds the paginated `TextChapter` for one chapter.
public enum ChapterProvider {
    /// The measurements the Android `object ChapterProvider` exposes as
    /// static fields. Filled by `updateStyle`.
    public struct Style {
        public var layout: ReaderLayout
        public var config: ReaderConfig
        public init(layout: ReaderLayout, config: ReaderConfig) {
            self.layout = layout
            self.config = config
        }
    }

    /// Loads the chapter content, runs the replace/purify pipeline and
    /// paginates it.
    ///
    /// - Parameters:
    ///   - book: the owning book (used for the duplicated-title removal and
    ///     the per-book replace-rule setting).
    ///   - chapter: the chapter to lay out.
    ///   - chaptersSize: the number of chapters in the book (`chapterSize` of
    ///     the `TextChapter`, used by `readProgress`).
    ///   - contentProvider: where the raw text comes from.
    ///   - titleRules/contentRules: the enabled replace rules.
    ///   - scriptEngine: evaluates `@js:` replacements, may be `nil`.
    ///   - config/layout/measurer: the reader measurements.
    public static func textChapter(
        book: Book,
        chapter: BookChapter,
        chaptersSize: Int,
        contentProvider: ChapterContentProviding,
        titleRules: [ReplaceRule] = [],
        contentRules: [ReplaceRule] = [],
        scriptEngine: RuleScriptEngine? = nil,
        config: ReaderConfig,
        layout: ReaderLayout,
        measurer: TextMeasuring,
        chineseConversionMode: ChineseConversionMode = .off,
        converter: ChineseConverting = DefaultChineseConverter()
    ) async throws -> TextChapter {
        let raw = try await contentProvider.chapterContent(book: book, chapter: chapter) ?? ""

        let processed = try ReplaceRuleEngine.processContent(
            book: book,
            chapter: chapter,
            content: raw,
            // Upstream passes `includeTitle = false`: the title is laid out
            // separately by `TextChapterLayout` (ReadBook.kt:712).
            includeTitle: false,
            useReplace: book.useReplaceRule,
            // Upstream keeps the default `chineseConvert = true`, so the
            // conversion follows `AppConfig.chineseConverterType`.
            chineseConvert: chineseConversionMode != .off,
            reSegment: book.reSegment,
            titleRules: titleRules,
            contentRules: contentRules,
            paragraphIndent: config.paragraphIndent,
            conversionMode: chineseConversionMode,
            converter: converter,
            scriptEngine: scriptEngine
        )

        let textChapter = TextChapter(
            chapter: chapter,
            position: Int(chapter.index),
            title: chapter.title,
            chaptersSize: chaptersSize,
            sameTitleRemoved: processed.sameTitleRemoved,
            isVip: chapter.isVip,
            isPay: chapter.isPay,
            effectiveReplaceRules: processed.effectiveReplaceRules
        )

        let layoutEngine = TextChapterLayout(
            chapter: textChapter,
            content: processed.contents.joined(separator: "\n"),
            config: config,
            layout: layout,
            measurer: measurer
        )
        // `paginate()` appends the pages to the chapter it was created with.
        _ = layoutEngine.paginate()
        textChapter.isCompleted = true
        return textChapter
    }

    /// Applies only the display title (used when a chapter has no body yet).
    public static func displayTitle(
        book: Book,
        chapter: BookChapter,
        titleRules: [ReplaceRule],
        scriptEngine: RuleScriptEngine?,
        config: ReaderConfig
    ) -> String {
        let title = (try? ReplaceRuleEngine.displayTitle(
            chapter,
            replaceRules: titleRules,
            useReplace: book.useReplaceRule,
            chineseConvert: false,
            scriptEngine: scriptEngine
        )) ?? chapter.title
        return config.titleMode == 2 ? "" : title
    }
}
