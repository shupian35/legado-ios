//
//  EpubFile.swift
//  LegadoCore
//
//  The Swift port of `app/src/main/java/io/legado/app/model/localBook/EpubFile.kt`
//  (the Android app drives the vendored `me.ag2s:epublib` fork through it).
//
//  Faithful details that are reproduced on purpose:
//    * the chapter list comes from the NCX navigation tree; when the book has no
//      NCX the spine is used instead;
//    * the resources before the first navigation entry become "front matter"
//      chapters (`parseFirstPage`);
//    * a navigation entry with children is a volume (`isVolume = true`);
//    * every chapter stores the URL of the NEXT chapter in its variables
//      (`putVariable("nextUrl", …)`) — the content reader uses it to decide
//      where a chapter ends;
//    * the `<title>` element is removed from the rendered content;
//    * a chapter is sliced by its fragment identifiers when one XHTML file
//      holds several chapters.
//

import Foundation
import SwiftSoup

public enum EpubFileError: Error, Equatable {
    case missingResource(String)
    case emptyBook
}

/// Reads the chapters and the content of an EPUB book.
public final class EpubFile {
    private let book: EpubBook

    public init(book: EpubBook) {
        self.book = book
    }

    public convenience init(archive: ZipArchive) throws {
        self.init(book: try EpubBook(archive: archive))
    }

    /// The book metadata (title, author, description).
    public var title: String { book.title }
    public var authors: [String] { book.authors }
    public var description: String? { book.description }

    // MARK: - Chapters

    /// The chapter list — upstream `EpubFile.getChapterList()`.
    public func chapterList() throws -> [BookChapter] {
        let refs = book.tableOfContents
        var chapters: [BookChapter] = []

        if refs.isEmpty {
            // No navigation tree — use the spine (upstream `epubBook.spine.spineReferences`).
            for (index, resource) in book.contents.enumerated() {
                var chapter = BookChapter()
                chapter.index = Int64(index)
                chapter.url = resource.path
                var title = ""
                if let text = try? book.text(atArchivePath: resource.path) {
                    let document = try? SwiftSoup.parse(text)
                    title = document.flatMap { EpubFile.matches($0, "title").first }.map { EpubFile.text($0) } ?? ""
                }
                if index == 0 && title.isEmpty {
                    chapter.title = "封面"
                } else {
                    chapter.title = title
                }
                chapters.append(chapter)
            }
        } else {
            parseFirstPage(&chapters, refs)
            parseMenu(&chapters, refs)
            for index in chapters.indices {
                chapters[index].index = Int64(index)
            }
        }

        // Every chapter points at the next one (upstream `putVariable("nextUrl", …)`).
        for index in chapters.indices {
            let next = index + 1 < chapters.count ? chapters[index + 1].url : ""
            chapters[index].variableBox.putVariable("nextUrl", next)
        }
        return chapters
    }

    /// The resources before the first navigation entry — upstream `parseFirstPage`.
    private func parseFirstPage(_ chapters: inout [BookChapter], _ refs: [EpubTocReference]) {
        guard let firstRef = refs.first(where: { !$0.href.isEmpty }) else { return }
        let firstHref = firstRef.href.split(separator: "#").first.map(String.init) ?? firstRef.href
        for content in book.contents {
            guard content.mediaType.contains("htm") else { continue }
            if firstHref == content.path { break }
            var chapter = BookChapter()
            var title = ""
            if let text = try? book.text(atArchivePath: content.path),
               let document = try? SwiftSoup.parse(text) {
                title = EpubFile.matches(document, "title").first.map { EpubFile.text($0) } ?? ""
            }
            if title.isEmpty { title = "--卷首--" }
            chapter.title = title
            chapter.url = content.path
            if content.path.contains("#") {
                chapter.startFragmentId = String(content.path.split(separator: "#").last ?? "")
                chapters[chapters.count - 1].endFragmentId = chapter.startFragmentId
            }
            chapters.append(chapter)
        }
    }

    /// The navigation tree — upstream `parseMenu`.
    private func parseMenu(_ chapters: inout [BookChapter], _ refs: [EpubTocReference]) {
        for ref in refs {
            if !ref.href.isEmpty {
                var chapter = BookChapter()
                chapter.title = ref.title
                chapter.url = ref.href
                chapter.startFragmentId = ref.fragmentId
                if !chapters.isEmpty {
                    chapters[chapters.count - 1].endFragmentId = ref.fragmentId
                }
                chapters.append(chapter)
            }
            if !ref.children.isEmpty {
                if !chapters.isEmpty {
                    chapters[chapters.count - 1].isVolume = true
                }
                parseMenu(&chapters, ref.children)
            }
        }
    }

    // MARK: - Content

    /// The content of a chapter — upstream `EpubFile.getContent(chapter)`.
    public func content(chapter: BookChapter) throws -> String {
        let nextHref = (chapter.variableBox.getVariable("nextUrl") ?? "")
            .split(separator: "#").first.map(String.init) ?? ""
        let currentHref = chapter.url.split(separator: "#").first.map(String.init) ?? chapter.url
        let isLastChapter = nextHref.isEmpty
        let startFragmentId = chapter.startFragmentId
        let endFragmentId = chapter.endFragmentId
        let includeNextChapterResource = !(endFragmentId?.isEmpty ?? true)

        var bodies: [SwiftSoup.Element] = []
        var foundCurrent = false
        for resource in book.contents {
            if !foundCurrent {
                if currentHref != resource.path { continue }
                foundCurrent = true
                if let body = body(of: resource, startFragmentId: startFragmentId, endFragmentId: endFragmentId) {
                    bodies.append(body)
                }
                if !isLastChapter, resource.path == nextHref { break }
                continue
            }
            if nextHref != resource.path {
                if let body = body(of: resource, startFragmentId: nil, endFragmentId: nil) {
                    bodies.append(body)
                }
            } else {
                if includeNextChapterResource {
                    if let body = body(of: resource, startFragmentId: nil, endFragmentId: endFragmentId) {
                        bodies.append(body)
                    }
                }
                break
            }
        }

        // Upstream cleanup: drop the <title>, the hidden elements and the extra covers.
        let joined = bodies.compactMap { try? $0.outerHtml() }.joined()
        guard let document = try? SwiftSoup.parse("<html><body>\(joined)</body></html>"),
              let elements = document.body()
        else {
            return TextFormat.formatKeepImg(joined)
        }
        for title in EpubFile.matches(elements, "title") { try? title.remove() }
        for hidden in EpubFile.matches(elements, "[style*=display:none]") { try? hidden.remove() }
        var coverIndex = 0
        for image in EpubFile.matches(elements, "img[src=cover.jpeg]") {
            if coverIndex > 0 { try? image.remove() }
            coverIndex += 1
        }
        // Upstream keeps only the `src` attribute of an image.
        for image in EpubFile.matches(elements, "img") {
            guard let attributes = image.getAttributes(), attributes.size() > 1 else { continue }
            let src = EpubFile.attr(image, "src")
            guard let replacement = try? SwiftSoup.parseBodyFragment("<img src=\"\(src)\" />").body()?.child(0) else {
                continue
            }
            try? image.replaceWith(replacement)
        }

        let html = (try? elements.outerHtml()) ?? ""
        return TextFormat.formatKeepImg(html)
    }

    /// The body of one XHTML resource — upstream `EpubFile.getBody(res, start, end)`.
    private func body(of resource: EpubResource, startFragmentId: String?, endFragmentId: String?) -> SwiftSoup.Element? {
        // The cover / title page is replaced by the cover image.
        if resource.path.contains("titlepage.xhtml") || resource.path.contains("cover") {
            let element = try? SwiftSoup.parseBodyFragment("<img src=\"cover.jpeg\" />")
            return element?.body()?.child(0)
        }

        guard let text = try? book.text(atArchivePath: resource.path) else { return nil }
        guard let document = try? SwiftSoup.parse(text) else { return nil }
        var bodyElement = document.body() ?? document
        for script in EpubFile.matches(bodyElement, "script") { try? script.remove() }
        for style in EpubFile.matches(bodyElement, "style") { try? style.remove() }

        // Slice the body by the fragment identifiers.
        if let startFragmentId, !startFragmentId.isEmpty,
           let startElement = EpubFile.matches(bodyElement, "#\(startFragmentId)").first,
           let outer = try? startElement.outerHtml() {
            let tagStart = outer.components(separatedBy: "\n").first ?? outer
            var html = (try? bodyElement.outerHtml()) ?? ""
            if let range = html.range(of: tagStart) {
                html = String(html[range.lowerBound...])
            }
            bodyElement = (try? SwiftSoup.parse(html).body()) ?? bodyElement
        }
        if let endFragmentId, !endFragmentId.isEmpty, endFragmentId != startFragmentId,
           let endElement = EpubFile.matches(bodyElement, "#\(endFragmentId)").first,
           let outer = try? endElement.outerHtml() {
            let tagStart = outer.components(separatedBy: "\n").first ?? outer
            var html = (try? bodyElement.outerHtml()) ?? ""
            if let range = html.range(of: tagStart) {
                html = String(html[..<range.lowerBound])
            }
            bodyElement = (try? SwiftSoup.parse(html).body()) ?? bodyElement
        }

        // `<image xlink:href="…">` → `<img src="…">`.
        for image in EpubFile.matches(bodyElement, "image") {
            try? image.tagName("img")
            _ = try? image.attr("src", EpubBook.attr(image, "xlink:href"))
        }
        // Resolve the image URLs against the resource path.
        for image in EpubFile.matches(bodyElement, "img") {
            let src = EpubBook.attr(image, "src").trimmingCharacters(in: .whitespaces)
            let resolved = EpubFile.resolveImageURL(src, relativeTo: resource.path)
            _ = try? image.attr("src", resolved)
        }
        return bodyElement
    }

    /// Resolve an image `src` against the href of the resource it lives in.
    static func resolveImageURL(_ src: String, relativeTo href: String) -> String {
        guard !src.isEmpty else { return src }
        if src.hasPrefix("data:") || src.contains("://") { return src }
        let directory = (href as NSString).deletingLastPathComponent
        let resolved = EpubBook.resolve(src, relativeTo: directory)
        return resolved.removingPercentEncoding ?? resolved
    }

    // MARK: - Helpers

    static func matches(_ element: SwiftSoup.Element, _ query: String) -> [SwiftSoup.Element] {
        guard let found = try? element.select(query) else { return [] }
        return Array(found)
    }

    static func text(_ element: SwiftSoup.Element) -> String {
        (try? element.text()) ?? ""
    }

    static func attr(_ element: SwiftSoup.Element, _ name: String) -> String {
        (try? element.attr(name)) ?? ""
    }
}
