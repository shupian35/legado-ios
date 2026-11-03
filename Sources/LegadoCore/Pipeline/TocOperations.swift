//
//  TocOperations.swift
//  LegadoCore
//
//  The table-of-contents operations of the upstream TOC screen
//  (`ui/book/toc/TocViewModel.kt`).
//
//  Upstream `TocViewModel.reverseToc` flips `book.reverseToc`, reverses the
//  chapter list and re-indexes it; `saveBookmark` / `saveBookmarkMd` export
//  the bookmarks of the book as JSON / Markdown.
//

import Foundation

/// The table-of-contents operations.
public enum TocOperations {

    /// Upstream `TocViewModel.reverseToc` — the chapters are reversed and
    /// re-indexed from 0.
    public static func reverse(chapters: [BookChapter]) -> [BookChapter] {
        chapters.reversed().enumerated().map { index, chapter in
            var changed = chapter
            changed.index = Int64(index)
            return changed
        }
    }

    /// Upstream `TocViewModel.saveBookmark` — the bookmarks of the book as
    /// JSON. The upstream file name is `bookmark-<name> <author>.json`.
    public static func bookmarkFileName(book: Book, fileExtension: String = "json") -> String {
        "bookmark-\(book.name) \(book.author).\(fileExtension)"
    }

    /// The bookmarks of the book as JSON.
    public static func bookmarkJSON(book: Book, bookmarks: [Bookmark]) -> String {
        let rows = bookmarks
            .filter { $0.bookName == book.name && $0.bookAuthor == book.author }
            .map { bookmark -> [String: JSONValue] in
                [
                    "bookName": .string(bookmark.bookName),
                    "bookAuthor": .string(bookmark.bookAuthor),
                    "chapterName": .string(bookmark.chapterName),
                    "chapterIndex": .number(Double(bookmark.chapterIndex)),
                    "chapterPos": .number(Double(bookmark.chapterPos)),
                    "time": .number(Double(bookmark.time))
                ]
            }
        return JSONValue.array(rows.map { JSONValue.object($0) }).jsonString
    }

    /// The bookmarks of the book as Markdown — upstream `saveBookmarkMd`.
    ///
    /// The upstream writes the bookmark name as the heading and the chapter
    /// position as the body.
    public static func bookmarkMarkdown(book: Book, bookmarks: [Bookmark]) -> String {
        let rows = bookmarks
            .filter { $0.bookName == book.name && $0.bookAuthor == book.author }
            .sorted { $0.chapterIndex < $1.chapterIndex }
        var lines: [String] = []
        for bookmark in rows {
            lines.append("## \(bookmark.chapterName)")
            lines.append("")
            lines.append("- 书籍：\(book.name)")
            lines.append("- 作者：\(book.author)")
            lines.append("- 章节：\(bookmark.chapterIndex)")
            lines.append("- 位置：\(bookmark.chapterPos)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// The chapter list with the search filter — upstream
    /// `ChapterListFragment` filters by the chapter name.
    public static func filter(chapters: [BookChapter], keyword: String) -> [BookChapter] {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return chapters }
        return chapters.filter { $0.title.localizedCaseInsensitiveContains(trimmed) }
    }

    // MARK: - The TOC rule and the long chapters

    /// The result of re-parsing the table of contents.
    public struct ReparsedToc {
        /// The new chapter list.
        public var chapters: [BookChapter]
        /// The rule that was used (the upstream stores it in `book.tocUrl`).
        public var rule: String
        /// The number of words of the book.
        public var wordCount: Int

        public init(chapters: [BookChapter], rule: String, wordCount: Int) {
            self.chapters = chapters
            self.rule = rule
            self.wordCount = wordCount
        }
    }

    /// Re-parses the table of contents of a local TXT book with a new rule —
    /// upstream `TocViewModel.upBookTocRule`.
    ///
    /// The upstream writes the rule into `book.tocUrl`, re-reads the chapter
    /// list of the local book and replaces the stored chapters.
    public static func reparse(
        book: Book,
        rule: String,
        fileURL: URL,
        splitLongChapter: Bool = false
    ) throws -> ReparsedToc {
        let textBook = TextBook(fileURL: fileURL, splitLongChapter: splitLongChapter)
        let parsed = try textBook.chapterList(tocRules: [], ruleOverride: rule)
        guard !parsed.chapters.isEmpty else { throw TocOperationsError.emptyToc }
        var chapters = LocalBook.normalize(chapters: parsed.chapters, bookUrl: book.bookUrl)
        // Upstream `TextFile.getChapterList` gives every chapter the URL
        // `md5Encode16(originName + index + title)`.
        for index in chapters.indices where chapters[index].url.isEmpty {
            chapters[index].url = ScriptDigest.md5Encode16(
                "\(book.originName)\(index)\(chapters[index].title)"
            )
        }
        return ReparsedToc(
            chapters: chapters,
            rule: parsed.tocPattern ?? rule,
            wordCount: parsed.wordCount
        )
    }

    /// The chapters with the long ones split — upstream
    /// `Book.setSplitLongChapter`.
    ///
    /// The flag is kept in the read configuration of the book; the split
    /// itself happens when the local book is parsed again.
    public static func setSplitLongChapter(_ enabled: Bool, book: Book) -> Book {
        var changed = book
        var config = changed.readConfigBox
        config.splitLongChapter = enabled
        changed.readConfigBox = config
        return changed
    }
}

/// The errors of the table-of-contents operations.
public enum TocOperationsError: Error, Equatable {
    /// The rule did not produce a single chapter.
    case emptyToc
}
