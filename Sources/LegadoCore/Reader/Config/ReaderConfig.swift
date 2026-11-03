//
//  ReaderConfig.swift
//  LegadoCore
//
//  The layout configuration of the reader — the part of the upstream
//  `ReadBookConfig` that the pagination needs.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/help/config/ReadBookConfig.kt
//  app/src/main/java/io/legado/app/ui/book/read/page/provider/ChapterProvider.kt
//

import Foundation

/// The style of the reader — upstream `ReadBookConfig.Config`.
public struct ReaderConfig: Equatable {
    /// The page background colour.
    public var backgroundColor: String = "#FFFFFF"
    /// The opacity of the background, in percent — upstream `Config.bgAlpha`.
    public var backgroundAlpha: Int = 100
    /// The night mode background colour.
    public var backgroundColorNight: String = "#000000"
    /// The e-ink mode background colour.
    public var backgroundColorEInk: String = "#000000"
    /// The text colour.
    public var textColor: String = "#000000"
    /// The night mode text colour.
    public var textColorNight: String = "#FFFFFF"
    /// The e-ink mode text colour.
    public var textColorEInk: String = "#000000"
    /// The page turn animation — 0 none, 1 cover, 2 slide, 3 simulation, 4 scroll.
    public var pageAnim: Int = 0
    /// The body font size, in sp.
    public var textSize: Double = 20
    /// The title font size, in sp.
    public var titleSize: Double = 20
    /// The extra letter spacing.
    public var letterSpacing: Double = 0.1
    /// The extra line spacing — the upstream value is divided by 10.
    public var lineSpacingExtra: Double = 12
    /// The space between two paragraphs.
    public var paragraphSpacing: Double = 2
    /// The title mode — 0 left, 1 centre, 2 hidden.
    public var titleMode: Int = 0
    /// The space above the title.
    public var titleTopSpacing: Double = 10
    /// The space below the title.
    public var titleBottomSpacing: Double = 10
    /// The indent of the first line of a paragraph.
    public var paragraphIndent: String = "　　"
    /// The top padding of the page.
    public var paddingTop: Double = 6
    /// The bottom padding of the page.
    public var paddingBottom: Double = 6
    /// The left padding of the page.
    public var paddingLeft: Double = 16
    /// The right padding of the page.
    public var paddingRight: Double = 16
    /// Whether the text is justified to the bottom of the page.
    public var textBottomJustify: Bool = false
    /// Whether the Chinese layout rules are used.
    public var useZhLayout: Bool = false
    /// Whether the title is centred — the upstream derives it from the title
    /// mode (`ReadBookConfig.kt:310`: `val isMiddleTitle get() = titleMode == 1`).
    public var isMiddleTitle: Bool = false
    /// Whether the text is fully justified.
    public var textFullJustify: Bool = false
    /// Whether the page shows two columns.
    public var doublePage: Bool = false
    /// Whether the text is underlined.
    public var underline: Bool = false
    /// Whether the text is bold — 0 normal, 1 bold, 2 light.
    public var textBold: Int = 0
    /// Whether the header is shown.
    public var showHeader: Bool = false
    /// Whether the footer is shown.
    public var showFooter: Bool = true
    /// The index of the selected read style — upstream
    /// `ReadBookConfig.styleSelect` (`PreferKey.readStyleSelect`).
    public var styleIndex: Int = 0
    /// The tip of the left header slot — upstream `ReadBookConfig.tipHeaderLeft`
    /// (`ReadTipConfig.kt:574`).
    public var tipHeaderLeft: Int = ReaderTipType.time.rawValue
    /// The tip of the middle header slot — upstream `ReadBookConfig.tipHeaderMiddle`.
    public var tipHeaderMiddle: Int = ReaderTipType.none.rawValue
    /// The tip of the right header slot — upstream `ReadBookConfig.tipHeaderRight`.
    public var tipHeaderRight: Int = ReaderTipType.battery.rawValue
    /// The tip of the left footer slot — upstream `ReadBookConfig.tipFooterLeft`.
    public var tipFooterLeft: Int = ReaderTipType.chapterTitle.rawValue
    /// The tip of the middle footer slot — upstream `ReadBookConfig.tipFooterMiddle`.
    public var tipFooterMiddle: Int = ReaderTipType.none.rawValue
    /// The tip of the right footer slot — upstream `ReadBookConfig.tipFooterRight`.
    public var tipFooterRight: Int = ReaderTipType.pageAndTotal.rawValue
    /// The colour of the tips — 0 the colour of the content, otherwise a
    /// colour value — upstream `ReadBookConfig.tipColor`.
    public var tipColor: Int = 0
    /// The colour of the dividers — -1 the default — upstream
    /// `ReadBookConfig.tipDividerColor`.
    public var tipDividerColor: Int = -1
    /// The visibility of the header — upstream `ReadBookConfig.headerMode`.
    public var headerMode: Int = 0
    /// The visibility of the footer — upstream `ReadBookConfig.footerMode`.
    public var footerMode: Int = 0

    public init() {}

    /// The style of the body text.
    public var contentStyle: ReaderTextStyle {
        ReaderTextStyle(
            fontSize: textSize,
            letterSpacing: letterSpacing,
            isBold: textBold == 1,
            isItalic: false
        )
    }

    /// The style of the title.
    public var titleStyle: ReaderTextStyle {
        ReaderTextStyle(
            fontSize: titleSize,
            letterSpacing: letterSpacing,
            isBold: true,
            isItalic: false
        )
    }

    /// The header and the footer layout — upstream `ReadTipConfig`.
    public var tipLayout: ReaderTipRenderer.Layout {
        ReaderTipRenderer.Layout(
            headerMode: ReaderTipMode(rawValue: headerMode) ?? .automatic,
            footerMode: ReaderTipMode(rawValue: footerMode) ?? .always,
            header: ReaderTipRenderer.Row(
                left: ReaderTipType(rawValue: tipHeaderLeft) ?? .none,
                middle: ReaderTipType(rawValue: tipHeaderMiddle) ?? .none,
                right: ReaderTipType(rawValue: tipHeaderRight) ?? .none
            ),
            footer: ReaderTipRenderer.Row(
                left: ReaderTipType(rawValue: tipFooterLeft) ?? .none,
                middle: ReaderTipType(rawValue: tipFooterMiddle) ?? .none,
                right: ReaderTipType(rawValue: tipFooterRight) ?? .none
            )
        )
    }
}

/// The geometry of the page — the port of the `ChapterProvider` measurements.
public struct ReaderLayout: Equatable {
    /// The width of the page.
    public var viewWidth: Double = 0
    /// The height of the page.
    public var viewHeight: Double = 0
    /// The width of the visible area.
    public var visibleWidth: Double = 0
    /// The height of the visible area.
    public var visibleHeight: Double = 0
    /// The top of the visible area.
    public var visibleTop: Double = 0
    /// The bottom of the visible area.
    public var visibleBottom: Double = 0
    /// The left padding.
    public var paddingLeft: Double = 0
    /// The right padding.
    public var paddingRight: Double = 0
    /// The top padding.
    public var paddingTop: Double = 0
    /// The bottom padding.
    public var paddingBottom: Double = 0
    /// The extra line spacing, already divided by ten.
    public var lineSpacingExtra: Double = 0
    /// The space between two paragraphs.
    public var paragraphSpacing: Double = 0
    /// The space above the title.
    public var titleTopSpacing: Double = 0
    /// The space below the title.
    public var titleBottomSpacing: Double = 0
    /// The width of the paragraph indent.
    public var indentWidth: Double = 0
    /// The height of a line of body text.
    public var contentTextHeight: Double = 0
    /// The descent of the body font.
    public var contentDescent: Double = 0
    /// The height of a line of title text.
    public var titleTextHeight: Double = 0
    /// The descent of the title font.
    public var titleDescent: Double = 0
    /// Whether the page shows two columns.
    public var doublePage: Bool = false

    public init() {}

    /// Computes the geometry — upstream `ChapterProvider.upStyle()`.
    public init(config: ReaderConfig, size: CGSizeLike, measurer: TextMeasuring) {
        let metrics = measurer.metrics(for: config.contentStyle)
        let titleMetrics = measurer.metrics(for: config.titleStyle)
        viewWidth = size.width
        viewHeight = size.height
        paddingLeft = config.paddingLeft
        paddingRight = config.paddingRight
        paddingTop = config.paddingTop
        paddingBottom = config.paddingBottom
        visibleWidth = max(0, size.width - config.paddingLeft - config.paddingRight)
        visibleHeight = max(0, size.height - config.paddingTop - config.paddingBottom)
        visibleTop = config.paddingTop
        visibleBottom = config.paddingTop + visibleHeight
        lineSpacingExtra = config.lineSpacingExtra / 10.0
        paragraphSpacing = config.paragraphSpacing
        titleTopSpacing = config.titleTopSpacing
        titleBottomSpacing = config.titleBottomSpacing
        let indent = config.paragraphIndent
        indentWidth = indent.isEmpty
            ? 0
            : measurer.width(of: indent, style: config.contentStyle) / Double(indent.count)
        contentTextHeight = metrics.lineHeight
        contentDescent = metrics.descent
        titleTextHeight = titleMetrics.lineHeight
        titleDescent = titleMetrics.descent
        doublePage = config.doublePage
    }
}

/// A platform independent size — `CGFloat` does not exist on Linux.
public struct CGSizeLike: Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
