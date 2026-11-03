//
//  BookReadConfig.swift
//  LegadoCore
//
//  The per-book read configuration — upstream `data/entities/Book.ReadConfig`.
//
//

import Foundation

/// The per-book read configuration.
///
/// It is stored as JSON in the `readConfig` column of the `books` table.
public struct BookReadConfig: Equatable {
    /// Whether the chapter list is stored in reverse order.
    public var reverseToc: Bool = false
    /// The page animation of the book.
    public var pageAnim: Int?
    /// Whether the paragraphs are re-segmented.
    public var reSegment: Bool = false
    /// The image display style of a comic book.
    public var imageStyle: String?
    /// Whether the replace / purify rules are applied to the content.
    public var useReplaceRule: Bool?
    /// The bit mask of the tags to remove.
    public var delTag: Int64 = 0
    /// The TTS engine.
    public var ttsEngine: String?
    /// Whether a very long chapter is split.
    public var splitLongChapter: Bool = true
    /// Whether the reading progress is simulated.
    public var readSimulating: Bool = false
    /// The day the simulated reading started.
    public var startDate: String?
    /// The chapter the simulated reading starts at.
    public var startChapter: Int?
    /// The number of chapters read per day in the simulation.
    public var dailyChapters: Int = 3

    public init(
        reverseToc: Bool = false,
        pageAnim: Int? = nil,
        reSegment: Bool = false,
        imageStyle: String? = nil,
        useReplaceRule: Bool? = nil,
        delTag: Int64 = 0,
        ttsEngine: String? = nil,
        splitLongChapter: Bool = true,
        readSimulating: Bool = false,
        startDate: String? = nil,
        startChapter: Int? = nil,
        dailyChapters: Int = 3
    ) {
        self.reverseToc = reverseToc
        self.pageAnim = pageAnim
        self.reSegment = reSegment
        self.imageStyle = imageStyle
        self.useReplaceRule = useReplaceRule
        self.delTag = delTag
        self.ttsEngine = ttsEngine
        self.splitLongChapter = splitLongChapter
        self.readSimulating = readSimulating
        self.startDate = startDate
        self.startChapter = startChapter
        self.dailyChapters = dailyChapters
    }
}
