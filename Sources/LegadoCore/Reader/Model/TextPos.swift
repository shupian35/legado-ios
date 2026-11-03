//
//  TextPos.swift
//  LegadoCore
//
//  The position of a character inside the rendered chapter.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/read/page/entities/TextPos.kt
//

import Foundation

/// The position of a character — upstream `TextPos`.
///
/// `relativePagePos` is the offset of the page relative to the current one
/// (-1 = the previous page, 0 = the current page, 1 = the next page).
public struct TextPos: Equatable {
    public var relativePagePos: Int
    public var lineIndex: Int
    public var columnIndex: Int

    public init(relativePagePos: Int = 0, lineIndex: Int = -1, columnIndex: Int = -1) {
        self.relativePagePos = relativePagePos
        self.lineIndex = lineIndex
        self.columnIndex = columnIndex
    }

    public mutating func update(relativePos: Int, lineIndex: Int, charIndex: Int) {
        self.relativePagePos = relativePos
        self.lineIndex = lineIndex
        self.columnIndex = charIndex
    }

    public mutating func update(_ pos: TextPos) {
        self.relativePagePos = pos.relativePagePos
        self.lineIndex = pos.lineIndex
        self.columnIndex = pos.columnIndex
    }

    /// Compares two positions — upstream `TextPos.compare(pos)`.
    ///
    /// The result is -3 / 3 for a different page, -2 / 2 for a different line
    /// and -1 / 1 for a different column.
    public func compare(_ pos: TextPos) -> Int {
        if relativePagePos < pos.relativePagePos { return -3 }
        if relativePagePos > pos.relativePagePos { return 3 }
        if lineIndex < pos.lineIndex { return -2 }
        if lineIndex > pos.lineIndex { return 2 }
        if columnIndex < pos.columnIndex { return -1 }
        if columnIndex > pos.columnIndex { return 1 }
        return 0
    }

    /// Compares with the individual components — upstream `TextPos.compare(…)`.
    public func compare(relativePos: Int, lineIndex: Int, charIndex: Int) -> Int {
        if self.relativePagePos < relativePos { return -3 }
        if self.relativePagePos > relativePos { return 3 }
        if self.lineIndex < lineIndex { return -2 }
        if self.lineIndex > lineIndex { return 2 }
        if self.columnIndex < charIndex { return -1 }
        if self.columnIndex > charIndex { return 1 }
        return 0
    }

    public mutating func reset() {
        relativePagePos = 0
        lineIndex = -1
        columnIndex = -1
    }

    /// Whether the position points at a character — upstream `isSelected()`.
    public var isSelected: Bool {
        lineIndex >= 0 && columnIndex >= 0
    }
}
