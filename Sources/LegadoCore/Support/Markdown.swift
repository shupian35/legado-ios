//
//  Markdown.swift
//  LegadoCore
//
//  A small Markdown parser — the port of the upstream's Markwon rendering.
//
//  Upstream renders the Markdown documents with Markwon
//  (`app/src/main/java/io/legado/app/ui/widget/dialog/TextDialog.kt:73-87`):
//  the about screen shows `updateLog.md`, `LICENSE.md`, `disclaimer.md` and
//  `privacyPolicy.md` and the update dialog shows the release notes.
//
//  The parser covers the subset of Markdown that the upstream's documents
//  use: the headings, the paragraphs, the bullet and the numbered lists, the
//  block quotes, the fenced code blocks, the horizontal rules and the inline
//  links.
//

import Foundation

/// A block of a Markdown document.
public enum MarkdownBlock: Equatable, Sendable {

    /// A heading — `#` … `######`.
    case heading(level: Int, text: String)
    /// A paragraph.
    case paragraph(String)
    /// A bullet of a list — `-`, `*` or `+`.
    case bullet(String)
    /// An item of an ordered list.
    case numbered(Int, String)
    /// A block quote — `>`.
    case quote(String)
    /// A fenced code block.
    case code(String)
    /// A horizontal rule — `---` or `***`.
    case divider
    /// A link — `[the text](the url)`.
    case link(text: String, url: String)
}

/// The Markdown parser.
public enum Markdown {

    /// Parses a document into its blocks.
    public static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var code: [String] = []
        var inCode = false
        var orderedIndex = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            paragraph.removeAll()
            guard !text.isEmpty else { return }
            if let link = inlineLink(text) {
                blocks.append(.link(text: link.text, url: link.url))
            } else {
                blocks.append(.paragraph(text))
            }
        }

        for rawLine in source.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(code.joined(separator: "\n")))
                    code.removeAll()
                    inCode = false
                } else {
                    flushParagraph()
                    inCode = true
                }
                continue
            }
            if inCode {
                code.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushParagraph()
                orderedIndex = 0
                continue
            }

            // A horizontal rule.
            let ruleCharacters = Set(line)
            if line.count >= 3, !line.isEmpty,
                (ruleCharacters == ["-"] || ruleCharacters == ["*"] || ruleCharacters == ["_"]) {
                flushParagraph()
                blocks.append(.divider)
                continue
            }

            // A heading.
            if line.hasPrefix("#") {
                let hashes = line.prefix(while: { $0 == "#" }).count
                if hashes <= 6 {
                    flushParagraph()
                    let text = String(line.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(level: hashes, text: text))
                    continue
                }
            }

            // A block quote.
            if line.hasPrefix(">") {
                flushParagraph()
                let text = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                blocks.append(.quote(text))
                continue
            }

            // A bullet.
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                flushParagraph()
                blocks.append(.bullet(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces)))
                continue
            }

            // A numbered item.
            if let item = numberedItem(line) {
                flushParagraph()
                orderedIndex = item.number
                blocks.append(.numbered(item.number, item.text))
                continue
            }
            if orderedIndex > 0 {
                // A lazy continuation of the previous item.
                if let last = blocks.last, case .numbered(let number, var text) = last {
                    text += "\n" + line
                    blocks.removeLast()
                    blocks.append(.numbered(number, text))
                    continue
                }
            }

            paragraph.append(line)
        }
        flushParagraph()
        if inCode && !code.isEmpty {
            blocks.append(.code(code.joined(separator: "\n")))
        }
        return blocks
    }

    /// The plain text of a document — the markdown without its markup.
    public static func plainText(_ source: String) -> String {
        parse(source).map { block in
            switch block {
            case .heading(_, let text), .paragraph(let text), .bullet(let text),
                 .quote(let text), .code(let text):
                return text
            case .numbered(_, let text):
                return text
            case .link(let text, _):
                return text
            case .divider:
                return ""
            }
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// Parses a numbered item — `1. the text`.
    private static func numberedItem(_ line: String) -> (number: Int, text: String)? {
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let numberText = String(line[line.startIndex..<dot])
        guard !numberText.isEmpty, numberText.allSatisfy({ $0.isNumber }) else { return nil }
        let rest = line[line.index(after: dot)...]
        guard rest.hasPrefix(" ") else { return nil }
        guard let number = Int(numberText) else { return nil }
        return (number, String(rest).trimmingCharacters(in: .whitespaces))
    }

    /// Parses an inline link — `[the text](the url)`.
    private static func inlineLink(_ text: String) -> (text: String, url: String)? {
        guard let open = text.firstIndex(of: "["),
              let close = text[open...].firstIndex(of: "]") else { return nil }
        let afterClose = text.index(after: close)
        guard afterClose < text.endIndex, text[afterClose] == "(" else { return nil }
        guard let end = text[afterClose...].firstIndex(of: ")") else { return nil }
        let label = String(text[text.index(after: open)..<close])
        let url = String(text[text.index(after: afterClose)..<end]).trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty else { return nil }
        return (label, url)
    }
}
