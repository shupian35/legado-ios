//
//  MobiLocalBook.swift
//  LegadoCore
//
//  The MOBI / AZW local book — the port of
//  app/src/main/java/io/legado/app/model/localBook/MobiFile.kt.
//
//  The upstream keeps one `MobiFile` per book (a singleton) and derives the
//  chapters from the table of contents of the MOBI file; the content of a
//  chapter is the HTML of the section (plus the sections that follow it
//  until the next chapter starts).
//

import Foundation
import SwiftSoup

/// The MOBI local book.
public struct MobiLocalBook {

    /// The parsed MOBI file.
    public let book: MobiBook

    private init(book: MobiBook) {
        self.book = book
    }

    /// Opens a MOBI file — upstream `MobiFile.readMobi`.
    public static func open(url: URL) throws -> MobiLocalBook {
        MobiLocalBook(book: try MobiBook.read(url: url))
    }

    // MARK: - The chapters

    /// The chapter list — upstream `MobiFile.getChapterList`.
    public func chapterList(bookUrl: String) -> [BookChapter] {
        var chapters: [BookChapter] = []

        // A book without a table of contents gets the first section as its
        // only chapter — upstream `getChapterListKF6` / `getChapterListKF8`.
        if book.sectionIdMap[0] == nil {
            let href: String?
            let text: String
            if book.isKF8 {
                let section = book.kf8Sections?.first { !$0.href.isEmpty }
                href = section?.href
                text = section.map { book.kf8SectionText($0) } ?? ""
            } else {
                let section = book.kf6Sections?.first
                href = section?.href
                text = section.map { book.kf6SectionText($0) } ?? ""
            }
            if let href {
                var chapter = BookChapter()
                chapter.bookUrl = bookUrl
                chapter.title = MobiLocalBook.title(in: text) ?? "卷首"
                chapter.url = "0:" + href
                chapters.append(chapter)
            }
        }

        func append(_ item: MobiTOC) {
            var chapter = BookChapter()
            chapter.bookUrl = bookUrl
            chapter.title = item.label
            chapter.url = "\(chapters.count):\(item.href)"
            chapter.isVolume = item.subitems != nil
            if let last = chapters.last {
                if last.isVolume, MobiLocalBook.href(of: last.url) == MobiLocalBook.href(of: chapter.url) {
                    // The upstream marks the duplicated volume so that its
                    // content is skipped.
                    chapters[chapters.count - 1].url = "skip:" + chapters[chapters.count - 1].url
                }
                chapters[chapters.count - 1].variableBox.putVariable("nextUrl", chapter.url)
            }
            chapters.append(chapter)
            item.subitems?.forEach(append)
        }

        book.toc?.forEach(append)
        return chapters
    }

    /// The href of a chapter URL (`<index>:<href>`).
    private static func href(of url: String) -> String {
        guard let range = url.range(of: ":") else { return url }
        return String(url[range.upperBound...])
    }

    // MARK: - The content

    /// The content of a chapter — upstream `MobiFile.getContent`.
    public func content(chapter: BookChapter) -> String? {
        if chapter.isVolume, chapter.url.hasPrefix("skip:") { return "" }
        let href = MobiLocalBook.href(of: chapter.url)
        let nextHref = chapter.variableBox.getVariable("nextUrl").map(MobiLocalBook.href(of:))
        var html = ""

        if book.isKF8 {
            guard let section = book.kf8Section(byHref: href) else { return nil }
            html += book.kf8Text(byHref: href, nextHref: nextHref ?? "")
            let nextPos = nextHref.flatMap { book.kf8Pos(href: $0) }
            var current: MobiKF8Section? = section
            while let active = current {
                if let nextPos, active.frags.contains(where: { $0.index == nextPos.fid }) { break }
                guard let next = active.next else { break }
                if !next.linear { current = next; continue }
                if let nextHref, next.href == nextHref { break }
                if book.sectionIdMap[next.index] != nil { break }
                html += book.kf8SectionText(next)
                current = next
            }
        } else {
            guard let section = book.kf6Section(byHref: href) else { return nil }
            html += book.kf6SectionText(section)
            var current: MobiKF6Section? = section.next
            while let active = current {
                if let nextHref, active.href == nextHref { break }
                if book.sectionIdMap[active.index] != nil { break }
                html += book.kf6SectionText(active)
                current = active.next
            }
        }

        return MobiLocalBook.clean(html)
    }

    /// The HTML cleanup — upstream `MobiFile.getContent` + `format`.
    private static func clean(_ html: String) -> String {
        guard let document = try? SwiftSoup.parse(html), let body = document.body() else {
            return format(html)
        }
        if let titles = try? body.select("title") {
            for title in titles { try? title.remove() }
        }
        if let hidden = try? body.select("[style*=display:none]") {
            for element in hidden { try? element.remove() }
        }
        // The upstream rewrites the `recindex` images so that the reader can
        // load them from the book.
        if let images = try? body.select("img[recindex]") {
            for image in images {
                let recindex = (try? image.attr("recindex")) ?? ""
                guard let replacement = try? SwiftSoup.parseBodyFragment(
                    "<img src=\"recindex:\(recindex)\" />"
                ).body()?.child(0) else { continue }
                try? image.replaceWith(replacement)
            }
        }
        let html = (try? body.outerHtml()) ?? ""
        return format(html)
    }

    private static func format(_ html: String) -> String {
        var text = TextFormat.formatKeepImg(html)
        if let range = text.range(of: "<?xml", options: .regularExpression) {
            // The upstream removes the XML declaration with a regex.
            var end = range.upperBound
            while end < text.endIndex, text[end] != ">" { end = text.index(after: end) }
            if end < text.endIndex { end = text.index(after: end) }
            text.removeSubrange(range.lowerBound..<end)
        }
        if let range = text.range(of: "<!DOCTYPE", options: .regularExpression) {
            var end = range.upperBound
            while end < text.endIndex, text[end] != ">" { end = text.index(after: end) }
            if end < text.endIndex { end = text.index(after: end) }
            text.removeSubrange(range.lowerBound..<end)
        }
        return text
    }

    /// The title of a section — upstream `soup.getElementsByTag("title").first()`.
    private static func title(in html: String) -> String? {
        guard let document = try? SwiftSoup.parse(html),
              let title = try? document.select("title").first()
        else { return nil }
        return try? title.text()
    }

    // MARK: - The images

    /// The image of a `recindex:` / `kindle:embed:` href — upstream
    /// `MobiFile.getImage`.
    public func image(href: String) -> [UInt8]? {
        if book.isKF8 {
            return book.kf8Resource(byHref: href)
        }
        return book.kf6Resource(byHref: href)
    }

    // MARK: - The book info

    /// Fills the book with the metadata of the MOBI file — upstream
    /// `MobiFile.upBookInfo`.
    public func upBookInfo(_ book: inout Book) {
        let metadata = self.book.metadata
        book.name = metadata.title
        if book.name.isEmpty {
            book.name = book.originName.replacingOccurrences(
                of: "(?i)\\.(mobi|azw3|azw)$",
                with: "",
                options: .regularExpression
            )
        }
        if let author = metadata.author.first, !author.isEmpty {
            book.author = author
        }
        if !metadata.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            book.intro = TextFormat.formatKeepImg(metadata.description)
        }
    }

    // MARK: - The import

    /// Imports a MOBI file — upstream `LocalBook.getChapterList` for a MOBI.
    public static func importFile(fileURL: URL, bookUrl: String?) throws -> LocalBook.ImportedBook {
        let local = try MobiLocalBook.open(url: fileURL)
        let fileName = fileURL.lastPathComponent
        let nameAuthor = LocalBook.analyzeNameAuthor(fileName: fileName)
        var book = Book()
        book.bookUrl = bookUrl ?? fileURL.absoluteString
        book.originName = fileName
        book.name = nameAuthor.name
        book.author = nameAuthor.author
        book.type = BookType.text | BookType.local
        book.origin = BookType.localTag
        local.upBookInfo(&book)
        if book.name.isEmpty {
            book.name = nameAuthor.name
        }
        if book.author.isEmpty {
            book.author = nameAuthor.author
        }

        let chapters = LocalBook.normalize(chapters: local.chapterList(bookUrl: book.bookUrl), bookUrl: book.bookUrl)
        guard !chapters.isEmpty else { throw LocalBook.LocalBookError.tocEmpty }
        book.totalChapterNum = Int64(chapters.count)
        book.latestChapterTime = Int64(Date().timeIntervalSince1970 * 1000)

        var wordCount = 0
        for chapter in chapters {
            wordCount += (local.content(chapter: chapter)?.count ?? 0)
        }
        book.wordCount = TextFormat.wordCountFormat(wordCount)

        return LocalBook.ImportedBook(
            book: book,
            chapters: chapters,
            intro: book.intro,
            wordCount: wordCount,
            tocPattern: nil
        )
    }
}
