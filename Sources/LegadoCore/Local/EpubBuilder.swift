//
//  EpubBuilder.swift
//  LegadoCore
//
//  The EPUB 2.0 writer used by the book export.
//
//  Upstream vendors `epublib` (`modules/book`); the port writes the container
//  directly. The layout mirrors what `EpubWriter` produced:
//
//      mimetype                     (stored, first entry)
//      META-INF/container.xml       -> OEBPS/content.opf
//      OEBPS/<resource href>
//      OEBPS/content.opf
//      OEBPS/toc.ncx
//

import Foundation

// MARK: - Templates

/// The default page templates — upstream `assets/epub/*.html`.
enum EpubTemplates {

    static let chapter = """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
            <title>Chapter</title>
            <link href="../Styles/fonts.css" type="text/css" rel="stylesheet"/>
            <link href="../Styles/main.css" type="text/css" rel="stylesheet"/>
        </head>
        <body>
        <h2 class="head">{title}</h2>
        {content}
        </body>
        </html>
        """

    static let cover = """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
            <title>Cover</title>
            <style type="text/css">
        \t\t.pic {
        \t\t\tmargin: 50% 30% 0 30%;
        \t\t\tpadding: 2px 2px;
        \t\t\tborder: 1px solid #f5f5dc;
        \t\t\tbackground-color: rgba(250,250,250, 0);
        \t\t\tborder-radius: 1px;
        \t\t}
            </style>
        </head>
        <body style="text-align: center;">
        <div class="pic"><img src="../Images/cover.jpg" style="width: 100%; height: auto;"/></div>
        <h1 style="margin-top: 5%; font-size: 110%;">{name}</h1>
        <div class="author" style="margin-top: 0;"><b>{author}</b> <span style="font-size: smaller;">/ 著</span></div>
        </body>
        </html>
        """

    static let intro = """
        <?xml version="1.0" encoding="utf-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh-CN">
        <head>
            <title>Intro</title>
            <link href="../Styles/fonts.css" type="text/css" rel="stylesheet" />
            <link href="../Styles/main.css" type="text/css" rel="stylesheet" />
        </head>
        <body>
        <h1 class="head" style="margin-bottom:2em;">内容简介</h1>{intro}</body>
        </html>
        """

    /// The default stylesheet. Upstream ships `assets/epub/{fonts,main}.css`
    /// (about 23 KB); the port embeds the rules the templates actually use.
    static let stylesheet = """
        body {
            margin: 0 4%;
            line-height: 1.6;
            text-align: justify;
            word-wrap: break-word;
        }
        h1, h2, h3 { font-weight: bold; line-height: 1.4; text-align: center; }
        h2.head { margin: 0.8em 0; font-size: 1.15em; }
        p { text-indent: 2em; margin: 0.35em 0; }
        .chapter-sequence-number { font-size: 0.85em; color: #666; }
        .duokan-image-single { text-align: center; text-indent: 0; }
        .picture-80 { width: 80%; height: auto; }
        .author { text-align: center; }
        """

    /// A chapter page — upstream `ResourceUtil.createChapterResource`.
    static func chapterPage(title: String, content: String, model: String = chapter) -> String {
        var heading = title
        // Upstream `title.replaceFirst("\\s+", "</span><br />")`: the first
        // whitespace run becomes a line break, which is then wrapped.
        if let expression = try? NSRegularExpression(pattern: "\\s+"),
           let match = expression.firstMatch(
               in: heading,
               options: [],
               range: NSRange(heading.startIndex..<heading.endIndex, in: heading)
           ),
           let range = Range(match.range, in: heading) {
            heading.replaceSubrange(range, with: "</span><br />")
        }
        if heading.contains("</span>") {
            heading = "<span class=\"chapter-sequence-number\">" + heading
        }
        return model
            .replacingOccurrences(of: "{title}", with: heading)
            .replacingOccurrences(of: "{ori_title}", with: title)
            .replacingOccurrences(of: "{content}", with: formatHtml(content))
    }

    /// A cover / intro page — upstream `ResourceUtil.createPublicResource`.
    static func publicPage(
        name: String,
        author: String,
        intro: String,
        kind: String?,
        wordCount: String?,
        model: String,
        href: String
    ) -> String {
        model
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{author}", with: author)
            .replacingOccurrences(of: "{kind}", with: kind ?? "")
            .replacingOccurrences(of: "{wordCount}", with: wordCount ?? "")
            .replacingOccurrences(of: "{intro}", with: formatHtml(intro))
    }

    /// Formats paragraphs as XHTML — upstream `StringUtil.formatHtml`.
    static func formatHtml(_ text: String) -> String {
        var body = ""
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            if let image = singleImageTag(in: line) {
                body += "<div class=\"duokan-image-single\">"
                    + "<img class=\"picture-80\" \(image)/></div>"
            } else {
                body += "<p>\(line)</p>"
            }
        }
        return body
    }

    private static let singleImageSource = "(?i)^<img\\s([^>]+)/?>$"
    private static let singleImageExpression = try? NSRegularExpression(
        pattern: singleImageSource
    )

    private static func singleImageTag(in line: String) -> String? {
        guard let expression = singleImageExpression else { return nil }
        let range = NSRange(location: 0, length: (line as NSString).length)
        guard let match = expression.firstMatch(in: line, options: [], range: range),
              match.numberOfRanges > 1,
              match.range(at: 1).location != NSNotFound else { return nil }
        return (line as NSString).substring(with: match.range(at: 1))
    }
}

// MARK: - Images

enum EpubImages {

    struct Fixed {
        let text: String
        let images: [EpubWriteResource]
    }

    /// Rewrites the image URLs of a chapter to archive-relative paths and
    /// collects the pictures — upstream `ExportBookService.fixPic`.
    static func fix(
        content: String,
        chapterURL: String,
        provider: ((String) -> Data?)?
    ) -> Fixed {
        guard let expression = try? NSRegularExpression(
            pattern: RulePatterns.imgPattern
        ) else {
            return Fixed(text: content, images: [])
        }
        var images: [EpubWriteResource] = []
        var seen = Set<String>()
        var lines: [String] = []

        for line in content.components(separatedBy: "\n") {
            var rewritten = line
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            for match in expression.matches(in: line, options: [], range: range) {
                guard match.numberOfRanges > 1,
                      match.range(at: 1).location != NSNotFound else { continue }
                let source = nsLine.substring(with: match.range(at: 1))
                let absolute = NetworkUtils.absoluteURL(base: chapterURL, source)
                let suffix = BookExporter.imageSuffix(for: absolute)
                let href = "Images/\(ScriptDigest.md5Encode16(absolute)).\(suffix)"
                if seen.insert(href).inserted {
                    if let data = provider?(absolute) {
                        images.append(EpubWriteResource(href: href, data: data))
                    }
                }
                rewritten = rewritten.replacingOccurrences(
                    of: source,
                    with: "../\(href)"
                )
            }
            lines.append(rewritten)
        }

        return Fixed(text: lines.joined(separator: "\n"), images: images)
    }
}

// MARK: - Resources

/// One file inside the EPUB.
struct EpubWriteResource: Equatable {
    let href: String
    let data: Data

    init(href: String, data: Data) {
        self.href = href
        self.data = data
    }

    init(href: String, string: String) {
        self.init(href: href, data: Data(string.utf8))
    }

    /// The OPF manifest id — epublib derives it from the href.
    var identifier: String {
        var result = ""
        for scalar in href.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else {
                result.append("_")
            }
        }
        return result
    }

    var mediaType: String {
        switch (href as NSString).pathExtension.lowercased() {
        case "xhtml", "html", "htm": return "application/xhtml+xml"
        case "css": return "text/css"
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "svg": return "image/svg+xml"
        case "ncx": return "application/x-dtbncx+xml"
        case "ttf": return "application/x-font-ttf"
        case "otf": return "application/x-font-opentype"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Builder

/// Collects the sections of an EPUB and writes the archive.
final class EpubBuilder {
    private let book: Book
    private var resources: [EpubWriteResource] = []
    /// The reading order: (title, href, isVolume).
    private var spine: [(title: String, href: String, isVolume: Bool)] = []
    private var cover: EpubWriteResource?

    init(book: Book) {
        self.book = book
    }

    func addStylesheet() {
        addResource(
            EpubWriteResource(href: "Styles/fonts.css", string: EpubTemplates.stylesheet)
        )
        addResource(
            EpubWriteResource(href: "Styles/main.css", string: EpubTemplates.stylesheet)
        )
    }

    func addSection(title: String, href: String, html: String) {
        addResource(EpubWriteResource(href: href, string: html))
        spine.append((title: title, href: href, isVolume: false))
    }

    func addChapter(
        title: String,
        content: String,
        isVolume: Bool,
        href: String,
        images: [EpubWriteResource]
    ) {
        let page = EpubTemplates.chapterPage(title: title, content: content)
        addResource(EpubWriteResource(href: href, string: page))
        for image in images where !resources.contains(image) {
            addResource(image)
        }
        spine.append((title: title, href: href, isVolume: isVolume))
    }

    func setCover(data: Data, href: String) {
        cover = EpubWriteResource(href: href, data: data)
    }

    private func addResource(_ resource: EpubWriteResource) {
        if !resources.contains(where: { $0.href == resource.href }) {
            resources.append(resource)
        }
    }

    // MARK: Writing

    func build() throws -> Data {
        var entries: [ZipWriteEntry] = [
            ZipWriteEntry(name: "mimetype", string: "application/epub+zip"),
            ZipWriteEntry(name: "META-INF/container.xml", string: Self.container)
        ]

        for resource in resources {
            entries.append(
                ZipWriteEntry(name: "OEBPS/\(resource.href)", data: resource.data)
            )
        }
        if let cover {
            entries.append(
                ZipWriteEntry(name: "OEBPS/\(cover.href)", data: cover.data)
            )
        }

        entries.append(
            ZipWriteEntry(name: "OEBPS/content.opf", string: contentOPF())
        )
        entries.append(
            ZipWriteEntry(name: "OEBPS/toc.ncx", string: tocNCX())
        )

        return try ZipWriter.archive(entries)
    }

    private static let container = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
        \t<rootfiles>
        \t\t<rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
        \t</rootfiles>
        </container>
        """

    private func uniqueIdentifier() -> String {
        let hex = Array(ScriptDigest.md5Hex("\(book.name)_\(book.author)"))
        func piece(_ range: Range<Int>) -> String {
            String(hex[range])
        }
        return "urn:uuid:\(piece(0..<8))-\(piece(8..<12))-\(piece(12..<16))"
            + "-\(piece(16..<20))-\(piece(20..<32))"
    }

    private func contentOPF() -> String {
        var manifest = """
                <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>

            """
        for resource in resources {
            manifest += "    <item id=\"\(resource.identifier)\" "
                + "href=\"\(resource.href)\" "
                + "media-type=\"\(resource.mediaType)\"/>\n"
        }
        if let cover {
            manifest += "    <item id=\"\(cover.identifier)\" "
                + "href=\"\(cover.href)\" "
                + "media-type=\"\(cover.mediaType)\"/>\n"
        }

        var itemRefs = ""
        for section in spine {
            itemRefs += "    <itemref idref=\"\(identifier(for: section.href))\"/>\n"
        }

        var coverMeta = ""
        if let cover {
            coverMeta = "    <meta name=\"cover\" content=\"\(cover.identifier)\"/>\n"
        }

        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" unique-identifier="BookId" version="2.0">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:opf="http://www.idpf.org/2007/opf">
                <dc:title>\(escape(book.name))</dc:title>
                <dc:creator opf:role="aut">\(escape(BookExporter.realAuthor(of: book)))</dc:creator>
                <dc:language>zh</dc:language>
                <dc:date>\(Self.dateString())</dc:date>
                <dc:publisher>Legado</dc:publisher>
                <dc:description>\(escape(BookExporter.displayIntro(of: book)))</dc:description>
                <dc:identifier id="BookId">\(uniqueIdentifier())</dc:identifier>
            \(coverMeta)  </metadata>
              <manifest>
            \(manifest)  </manifest>
              <spine toc="ncx">
            \(itemRefs)  </spine>
            </package>
            """
    }

    private func tocNCX() -> String {
        var navPoints = ""
        var playOrder = 0
        var openVolume = false
        var depth = 1

        for section in spine {
            playOrder += 1
            if section.isVolume {
                if openVolume { navPoints += "    </navPoint>\n" }
                navPoints += """
                        <navPoint id="navPoint-\(playOrder)" playOrder="\(playOrder)">
                          <navLabel><text>\(escape(section.title))</text></navLabel>
                          <content src="\(section.href)"/>

                    """
                openVolume = true
                depth = 2
            } else if openVolume {
                navPoints += """
                              <navPoint id="navPoint-\(playOrder)" playOrder="\(playOrder)">
                                <navLabel><text>\(escape(section.title))</text></navLabel>
                                <content src="\(section.href)"/>
                              </navPoint>

                    """
            } else {
                navPoints += """
                        <navPoint id="navPoint-\(playOrder)" playOrder="\(playOrder)">
                          <navLabel><text>\(escape(section.title))</text></navLabel>
                          <content src="\(section.href)"/>
                        </navPoint>

                    """
            }
        }
        if openVolume { navPoints += "    </navPoint>\n" }

        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
              <head>
                <meta name="dtb:uid" content="\(uniqueIdentifier())"/>
                <meta name="dtb:depth" content="\(depth)"/>
                <meta name="dtb:totalPageCount" content="0"/>
                <meta name="dtb:maxPageNumber" content="0"/>
              </head>
              <docTitle><text>\(escape(book.name))</text></docTitle>
              <navMap>
            \(navPoints)  </navMap>
            </ncx>
            """
    }

    private func identifier(for href: String) -> String {
        EpubWriteResource(href: href, data: Data()).identifier
    }

    private func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func dateString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: Date())
    }
}
