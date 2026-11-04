//
//  BookmarkExport.swift
//  LegadoCore
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/bookmark/AllBookmarkViewModel.kt:24-65
//  (exportBookmark / exportBookmarkMd).
//
//  The bookmarks can be exported as the JSON of the upstream format and as a
//  Markdown document that groups the bookmarks by book.
//

import Foundation

/// The export of the bookmarks — upstream `AllBookmarkViewModel`.
public enum BookmarkExport {

    /// The name of the file — upstream "bookmark-yyMMddHHmmss.json" /
    /// ".md" (the date format is `SimpleDateFormat("yyMMddHHmmss")`).
    public static func fileName(_ date: Date, markdown: Bool) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyMMddHHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return "bookmark-\(formatter.string(from: date)).\(markdown ? "md" : "json")"
    }

    /// The bookmarks as the JSON array of the upstream format — the same
    /// shape the store keeps them in.
    public static func json(_ bookmarks: [Bookmark]) -> String {
        DocumentExport.json(bookmarks, row: { $0.row })
    }

    /// The bookmarks as a Markdown document — upstream
    /// `AllBookmarkViewModel.exportBookmarkMd`.
    ///
    /// The heading of a book is only written when the book or the author
    /// changed, the chapter and the two texts follow it.
    public static func markdown(_ bookmarks: [Bookmark]) -> String {
        var result = ""
        var name = ""
        var author = ""
        for bookmark in bookmarks {
            if bookmark.bookName != name || bookmark.bookAuthor != author {
                name = bookmark.bookName
                author = bookmark.bookAuthor
                result += "## \(bookmark.bookName) \(bookmark.bookAuthor)\n\n"
            }
            result += "#### \(bookmark.chapterName)\n\n"
            result += "###### 原文\n \(bookmark.bookText)\n\n"
            result += "###### 摘要\n \(bookmark.content)\n\n"
        }
        return result
    }
}
