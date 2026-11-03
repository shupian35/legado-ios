//
//  Selection.swift
//  LegadoCore
//
//  The port of the upstream text selection.
//
//  Upstream `ui/book/read/page/ContentTextView.kt` keeps the selection as
//  two character offsets (`selStart` / `selEnd`), expands a long press to
//  the whole paragraph and then snaps the ends to the word boundaries that
//  `java.text.BreakIterator` reports. The port reproduces the model with a
//  small word breaker: a Latin word is a run of letters/digits, a CJK
//  character is a word on its own.
//

import Foundation

/// A character range selection inside a page.
public struct ReaderSelection: Equatable, Sendable {
    /// The first selected character.
    public var start: Int
    /// The character after the last selected one.
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }

    /// Whether nothing is selected.
    public var isEmpty: Bool { start >= end }

    /// The selection as a range, normalised so that `start <= end`.
    public var range: Range<Int> {
        let lower = min(start, end)
        let upper = max(start, end)
        return lower..<upper
    }

    /// The selected text.
    public func text(in text: String) -> String {
        guard !isEmpty else { return "" }
        let characters = Array(text)
        let lower = max(0, min(range.lowerBound, characters.count))
        let upper = max(lower, min(range.upperBound, characters.count))
        return String(characters[lower..<upper])
    }
}

/// The word and paragraph helpers of the selection.
public enum SelectionEngine {

    /// The words of the text, as the ranges the port can select.
    public static func wordRanges(in text: String) -> [Range<Int>] {
        let characters = Array(text)
        var ranges: [Range<Int>] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard isWordCharacter(character) else {
                index += 1
                continue
            }
            if isCJK(character) {
                // A CJK character is a word on its own.
                ranges.append(index..<(index + 1))
                index += 1
                continue
            }
            let start = index
            while index < characters.count,
                  isWordCharacter(characters[index]),
                  !isCJK(characters[index]) {
                index += 1
            }
            ranges.append(start..<index)
        }
        return ranges
    }

    /// The range of the word around `index` (the upstream long press).
    public static func wordRange(around index: Int, in text: String) -> Range<Int>? {
        let characters = Array(text)
        guard !characters.isEmpty else { return nil }
        let clamped = max(0, min(index, characters.count - 1))
        guard isWordCharacter(characters[clamped]) else { return clamped..<(clamped + 1) }
        if isCJK(characters[clamped]) { return clamped..<(clamped + 1) }
        var start = clamped
        while start > 0,
              isWordCharacter(characters[start - 1]),
              !isCJK(characters[start - 1]) {
            start -= 1
        }
        var end = clamped
        while end < characters.count,
              isWordCharacter(characters[end]),
              !isCJK(characters[end]) {
            end += 1
        }
        return start..<end
    }

    /// The range of the paragraph around `index`.
    ///
    /// The upstream expands the long press to the whole paragraph before it
    /// snaps the ends to the words.
    public static func paragraphRange(containing index: Int, in text: String) -> Range<Int> {
        let characters = Array(text)
        guard !characters.isEmpty else { return 0..<0 }
        let clamped = max(0, min(index, characters.count - 1))
        var start = clamped
        while start > 0, !isParagraphBreak(characters[start - 1]) { start -= 1 }
        var end = clamped
        while end < characters.count, !isParagraphBreak(characters[end]) { end += 1 }
        return start..<end
    }

    /// Snaps the ends of the selection to the word boundaries.
    public static func snap(_ selection: ReaderSelection, in text: String) -> ReaderSelection {
        guard !selection.isEmpty else { return selection }
        let range = selection.range
        let characters = Array(text)
        guard !characters.isEmpty else { return ReaderSelection(start: 0, end: 0) }
        let lower = max(0, min(range.lowerBound, characters.count - 1))
        let upper = max(lower, min(range.upperBound, characters.count))
        let wordStart = wordRange(around: lower, in: text)?.lowerBound ?? lower
        let wordEnd = wordRange(around: max(lower, upper - 1), in: text)?.upperBound ?? upper
        return ReaderSelection(start: wordStart, end: max(wordStart, wordEnd))
    }

    /// The selection of the whole paragraph around `index`.
    public static func paragraphSelection(containing index: Int, in text: String) -> ReaderSelection {
        let range = paragraphRange(containing: index, in: text)
        return ReaderSelection(start: range.lowerBound, end: range.upperBound)
    }

    /// Whether the character belongs to a word.
    public static func isWordCharacter(_ character: Character) -> Bool {
        if character.isLetter || character.isNumber { return true }
        if character == "'" || character == "-" { return true }
        return isCJK(character)
    }

    /// Whether the character is a CJK ideograph or a kana.
    public static func isCJK(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xF900...0xFAFF, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }

    /// Whether the character ends a paragraph.
    static func isParagraphBreak(_ character: Character) -> Bool {
        character == "\n" || character == "\r"
    }
}
