//
//  EpubBook.swift
//  LegadoCore
//
//  A minimal EPUB 2 / EPUB 3 reader.
//
//  The Android app reads EPUB files with the vendored `me.ag2s:epublib` fork
//  (`modules/book`), driven by `model/localBook/EpubFile.kt`. This is a
//  self-contained Swift implementation of the parts Legado actually uses:
//
//    * `META-INF/container.xml`  → the package document (OPF)
//    * the OPF `<metadata>`      → title, author, description
//    * the OPF `<manifest>`      → the resources
//    * the OPF `<spine>`         → the reading order
//    * the NCX (`toc.ncx`)       → the navigation tree used for the chapter list
//    * EPUB 3 `nav.xhtml`        → the navigation tree when there is no NCX
//

import Foundation
import SwiftSoup

/// One item of the OPF manifest.
public struct EpubResource: Equatable {
    public let id: String
    /// The href relative to the OPF directory.
    public let href: String
    /// The path of the resource inside the archive (the href resolved against
    /// the package directory).
    public let path: String
    public let mediaType: String

    public init(id: String, href: String, path: String, mediaType: String) {
        self.id = id
        self.href = href
        self.path = path
        self.mediaType = mediaType
    }
}

/// One node of the navigation tree (the NCX `navPoint` or the EPUB 3 `li`).
public struct EpubTocReference: Equatable {
    public let title: String
    /// The path inside the archive, including the fragment identifier.
    public let href: String
    public let fragmentId: String?
    public let children: [EpubTocReference]

    public init(title: String, href: String, fragmentId: String?, children: [EpubTocReference]) {
        self.title = title
        self.href = href
        self.fragmentId = fragmentId
        self.children = children
    }
}

public enum EpubError: Error, Equatable {
    case missingContainer
    case missingPackage
    case missingSpine
    case malformed(String)
}

/// The parsed content of an EPUB archive.
public final class EpubBook {
    public let title: String
    public let authors: [String]
    public let description: String?
    public let language: String?
    /// The manifest resources, in spine order (upstream `epubBook.contents`).
    public let contents: [EpubResource]
    /// The navigation tree — empty when the book has neither an NCX nor a nav document.
    public let tableOfContents: [EpubTocReference]
    /// The directory of the package document inside the archive.
    public let packageDirectory: String
    private let archive: ZipArchive

    public init(archive: ZipArchive) throws {
        self.archive = archive

        guard let containerEntry = archive.entry(named: "META-INF/container.xml") else {
            throw EpubError.missingContainer
        }
        let container = try SwiftSoup.parse(String(decoding: try archive.data(for: containerEntry), as: UTF8.self))
        guard let opfPath = EpubBook.matches(container, "rootfile").first.map { EpubBook.attr($0, "full-path") },
              !opfPath.isEmpty
        else {
            throw EpubError.missingPackage
        }
        packageDirectory = (opfPath as NSString).deletingLastPathComponent

        guard let packageEntry = archive.entry(named: opfPath) else {
            throw EpubError.missingPackage
        }
        let package = try SwiftSoup.parse(String(decoding: try archive.data(for: packageEntry), as: UTF8.self))

        // MARK: metadata
        //
        // The Dublin Core elements carry a namespace prefix (`dc:title`). SwiftSoup's
        // query parser does not understand `:` in a tag name, so the namespaced
        // elements are looked up by their literal tag name instead.
        let metadata = EpubBook.matches(package, "metadata").first
        title = EpubBook.metadataValue(metadata, tag: "title") ?? ""
        authors = EpubBook.metadataValues(metadata, tag: "creator")
        description = EpubBook.metadataValue(metadata, tag: "description")
        language = EpubBook.metadataValue(metadata, tag: "language")

        // MARK: manifest
        var manifest: [String: EpubResource] = [:]
        var manifestOrder: [EpubResource] = []
        for item in EpubBook.matches(package, "manifest > item") {
            let id = EpubBook.attr(item, "id")
            let href = EpubBook.attr(item, "href")
            let mediaType = EpubBook.attr(item, "media-type")
            guard !id.isEmpty, !href.isEmpty else { continue }
            let resource = EpubResource(
                id: id,
                href: href,
                path: EpubBook.resolve(href, relativeTo: packageDirectory),
                mediaType: mediaType
            )
            manifest[id] = resource
            manifestOrder.append(resource)
        }

        // MARK: spine
        var contents: [EpubResource] = []
        for itemRef in EpubBook.matches(package, "spine > itemref") {
            let idref = EpubBook.attr(itemRef, "idref")
            if let resource = manifest[idref] {
                contents.append(resource)
            }
        }
        if contents.isEmpty {
            // A malformed spine — fall back to the manifest order, like a tolerant reader.
            contents = manifestOrder.filter { $0.mediaType.contains("html") || $0.mediaType.contains("htm") }
        }
        guard !contents.isEmpty else { throw EpubError.missingSpine }
        self.contents = contents

        // MARK: navigation
        tableOfContents = EpubBook.parseNavigation(
            archive: archive,
            manifestOrder: manifestOrder,
            packageDirectory: packageDirectory
        )
    }

    /// The bytes of the manifest resource with `href` (relative to the package directory).
    public func data(for href: String) throws -> Data {
        let path = EpubBook.resolve(href, relativeTo: packageDirectory)
        guard let entry = archive.entry(named: path) else {
            throw EpubError.malformed("missing resource \(path)")
        }
        return try archive.data(for: entry)
    }

    /// The text of the manifest resource with `href`.
    public func text(for href: String) throws -> String {
        String(decoding: try data(for: href), as: UTF8.self)
    }

    /// The bytes of an archive path (as used by the navigation tree).
    public func data(atArchivePath path: String) throws -> Data {
        let name = path.split(separator: "#").first.map(String.init) ?? path
        guard let entry = archive.entry(named: name) else {
            throw EpubError.malformed("missing resource \(name)")
        }
        return try archive.data(for: entry)
    }

    /// The text of an archive path (as used by the navigation tree).
    public func text(atArchivePath path: String) throws -> String {
        String(decoding: try data(atArchivePath: path), as: UTF8.self)
    }

    /// The cover image bytes — the `cover-image` manifest item, else `cover.jpg`.
    public func coverImageData() -> Data? {
        let candidates = ["cover.jpg", "cover.jpeg", "cover.png"]
        for candidate in candidates {
            let path = EpubBook.resolve(candidate, relativeTo: packageDirectory)
            if let entry = archive.entry(named: path), let data = try? archive.data(for: entry) {
                return data
            }
        }
        return nil
    }

    // MARK: - Metadata helpers

    private static func metadataValue(_ metadata: Element?, tag: String) -> String? {
        guard let metadata else { return nil }
        var elements = matches(metadata, "> \(tag)")
        if elements.isEmpty { elements = matches(metadata, tag) }
        if elements.isEmpty { elements = matchesByTag(metadata, "dc:\(tag)") }
        guard let element = elements.first else { return nil }
        let value = text(element).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func metadataValues(_ metadata: Element?, tag: String) -> [String] {
        guard let metadata else { return [] }
        var elements = matches(metadata, "> \(tag)")
        if elements.isEmpty { elements = matches(metadata, tag) }
        if elements.isEmpty { elements = matchesByTag(metadata, "dc:\(tag)") }
        return elements
            .map { text($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Navigation

    private static func parseNavigation(
        archive: ZipArchive,
        manifestOrder: [EpubResource],
        packageDirectory: String
    ) -> [EpubTocReference] {
        // EPUB 2 — the NCX document.
        if let ncx = manifestOrder.first(where: { $0.mediaType == "application/x-dtbncx+xml" }) {
            let path = resolve(ncx.href, relativeTo: packageDirectory)
            if let entry = archive.entry(named: path),
               let data = try? archive.data(for: entry),
               let document = try? SwiftSoup.parse(String(decoding: data, as: UTF8.self)) {
                let directory = (path as NSString).deletingLastPathComponent
                let refs = matches(document, "navMap > navPoint").compactMap { parseNavPoint($0, directory: directory) }
                if !refs.isEmpty { return refs }
            }
        }

        // EPUB 3 — the navigation document.
        if let nav = manifestOrder.first(where: { $0.mediaType == "application/xhtml+xml" && $0.href.contains("nav") }) {
            let path = resolve(nav.href, relativeTo: packageDirectory)
            if let entry = archive.entry(named: path),
               let data = try? archive.data(for: entry),
               let document = try? SwiftSoup.parse(String(decoding: data, as: UTF8.self)) {
                let directory = (path as NSString).deletingLastPathComponent
                let navElement = matches(document, "nav").first { nav in
                    EpubBook.attr(nav, "epub:type").contains("toc") || EpubBook.attr(nav, "id") == "toc"
                }
                if let list = navElement.flatMap({ matches($0, "ol").first }) {
                    let refs = matches(list, "li").compactMap { parseNavListItem($0, directory: directory) }
                    if !refs.isEmpty { return refs }
                }
            }
        }
        return []
    }

    private static func parseNavPoint(_ point: Element, directory: String) -> EpubTocReference? {
        let label = matches(point, "navLabel > text").first.map { EpubBook.text($0) } ?? ""
        let src = matches(point, "content").first.map { EpubBook.attr($0, "src") } ?? ""
        let href = resolve(src, relativeTo: directory)
        let fragment = src.contains("#") ? String(src.split(separator: "#").last ?? "") : nil
        // NOTE: `select("navPoint")` also matches the element itself (SwiftSoup's
        // descendant search includes the context node), which would recurse forever.
        // The upstream reader walks the child nodes, so do the same here.
        let children = point.children()
            .filter { $0.tagName().lowercased() == "navpoint" }
            .compactMap { parseNavPoint($0, directory: directory) }
        guard !href.isEmpty else { return nil }
        return EpubTocReference(
            title: label.trimmingCharacters(in: .whitespacesAndNewlines),
            href: href,
            fragmentId: fragment,
            children: children
        )
    }

    private static func parseNavListItem(_ item: Element, directory: String) -> EpubTocReference? {
        let anchor = matches(item, "a").first
        let href = anchor.map { EpubBook.attr($0, "href") } ?? ""
        let title = anchor.map { EpubBook.text($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        let children = matches(item, "ol > li").compactMap { parseNavListItem($0, directory: directory) }
        guard !href.isEmpty else {
            return children.isEmpty ? nil : EpubTocReference(title: title, href: "", fragmentId: nil, children: children)
        }
        let resolved = resolve(href, relativeTo: directory)
        let fragment = href.contains("#") ? String(href.split(separator: "#").last ?? "") : nil
        return EpubTocReference(title: title, href: resolved, fragmentId: fragment, children: children)
    }

    // MARK: - Helpers

    /// A non-throwing text — SwiftSoup's text() throws.
    static func text(_ element: Element) -> String {
        (try? element.text()) ?? ""
    }

    /// A non-throwing attr — SwiftSoup's attr() throws.
    static func attr(_ element: Element, _ name: String) -> String {
        (try? element.attr(name)) ?? ""
    }

    /// A non-throwing select — SwiftSoup's select throws and returns an optional.
    static func matches(_ element: Element, _ query: String) -> [Element] {
        guard let found = try? element.select(query) else { return [] }
        return Array(found)
    }

    /// A non-throwing lookup by the literal tag name (used for the namespaced
    /// Dublin Core elements, whose `:` SwiftSoup's query parser rejects).
    static func matchesByTag(_ element: Element, _ tag: String) -> [Element] {
        guard let found = try? element.getElementsByTag(tag) else { return [] }
        return Array(found)
    }

    /// Resolve `href` against `directory` the way a URI reference is resolved.
    public static func resolve(_ href: String, relativeTo directory: String) -> String {
        if href.hasPrefix("/") { return String(href.dropFirst()) }
        var parts: [String] = []
        if !directory.isEmpty {
            parts = directory.split(separator: "/").map(String.init)
        }
        for component in href.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                if !parts.isEmpty { parts.removeLast() }
            default:
                parts.append(String(component))
            }
        }
        var result = parts.joined(separator: "/")
        // Percent escapes in hrefs (EPUB allows them).
        result = result.removingPercentEncoding ?? result
        return result
    }
}
