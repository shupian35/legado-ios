//
//  AutoPager.swift
//  LegadoCore
//
//  Port of `app/src/main/java/io/legado/app/ui/book/read/page/AutoPager.kt`.
//
//  The upstream auto pager has two modes:
//
//  * the E-Ink mode turns the page every `ReadBookConfig.autoReadSpeed`
//    seconds;
//  * the normal mode scrolls the page continuously and turns it when the
//    scroll reaches the bottom.
//
//  The scroll arithmetic is the load-bearing part, so it lives here (it is
//  platform independent and therefore testable); the SwiftUI side only
//  schedules the ticks and renders the offset.
//

import Foundation

/// How the auto pager advances.
public enum AutoPagerMode: Int, CaseIterable, Sendable {
    /// Turn the page every `speed` seconds — the upstream E-Ink mode
    /// (`AutoPager.start()` posts itself delayed and turns the whole page).
    case pageTurn
    /// Scroll the page continuously — the upstream mode of the scroll page
    /// animation (`ReadView.isScroll`, the `pageAnim == 3` case).
    case scroll
    /// Fill the progress of the page over `speed` seconds and then turn it —
    /// the upstream normal mode with a page-turn animation
    /// (`AutoPager.computeOffset` + `AutoPager.onDraw`).
    case progress
}

/// The auto pager.
public final class AutoPager {

    /// The configuration — upstream `ReadBookConfig.autoReadSpeed`.
    public struct Configuration: Equatable, Sendable {
        /// The seconds per page. Upstream clamps a value below 1 to 1
        /// (`AutoReadDialog.kt:78`).
        public var speed: Int
        /// The mode.
        public var mode: AutoPagerMode

        public init(speed: Int = 10, mode: AutoPagerMode = .pageTurn) {
            self.speed = max(1, speed)
            self.mode = mode
        }
    }

    /// The state — upstream `AutoPager.isRunning` / `isPausing`.
    public private(set) var isRunning = false
    public private(set) var isPausing = false

    /// The configuration.
    public var configuration: Configuration

    /// Called when the pager wants to turn the page.
    ///
    /// The closure returns `false` when there is no next page — the upstream
    /// `readView.fillPage(PageDirection.NEXT)` returns false and the pager
    /// stops.
    public var onTurn: ((PageTurnDirection) -> Bool)?
    /// Called with the scroll offset (0…1 of the page height) in the scroll
    /// mode.
    public var onScroll: ((Double) -> Void)?

    /// The accumulated scroll offset in pixels — upstream `scrollOffsetRemain`.
    private var scrollOffsetRemain: Double = 0
    /// The scroll offset of the current frame in pixels — upstream `scrollOffset`.
    private var scrollOffset: Int = 0
    /// The progress of the current page in pixels — upstream `progress`.
    private var progress: Double = 0
    /// The elapsed time of the current page in seconds — upstream
    /// `lastTimeMillis` (the difference of two `SystemClock.uptimeMillis`).
    private var elapsedRemain: Double = 0

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// The effective seconds per page.
    public var speed: Int { max(1, configuration.speed) }

    /// Starts the pager — upstream `AutoPager.start()`.
    public func start() {
        isRunning = true
        isPausing = false
        scrollOffsetRemain = 0
        scrollOffset = 0
        progress = 0
        elapsedRemain = 0
    }

    /// Stops the pager — upstream `AutoPager.stop()`.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        isPausing = false
        scrollOffsetRemain = 0
        scrollOffset = 0
        progress = 0
        elapsedRemain = 0
    }

    /// Pauses the pager — upstream `AutoPager.pause()`.
    public func pause() {
        guard isRunning else { return }
        isPausing = true
    }

    /// Resumes the pager — upstream `AutoPager.resume()`.
    public func resume() {
        guard isRunning else { return }
        isPausing = false
    }

    /// Resets the scroll — upstream `AutoPager.reset()`.
    public func reset() {
        scrollOffsetRemain = 0
        scrollOffset = 0
        progress = 0
        elapsedRemain = 0
    }

    /// The scroll progress of the current page (0…1).
    public var pageProgress: Double {
        switch configuration.mode {
        case .scroll: return progress
        case .progress: return min(1, elapsedRemain / Double(speed))
        case .pageTurn: return 0
        }
    }

    /// Advances the pager.
    ///
    /// In the page-turn mode the pager turns the page and the caller
    /// schedules the next tick after `speed` seconds; in the scroll mode the
    /// pager accumulates the scroll offset and turns the page when the page
    /// is full.
    ///
    /// - Parameters:
    ///   - elapsed: the seconds since the last tick.
    ///   - pageHeight: the height of the page in points (the scroll mode).
    /// - Returns: `false` when the pager reached the end of the book.
    @discardableResult
    public func tick(elapsed: TimeInterval, pageHeight: Double = 0) -> Bool {
        guard isRunning, !isPausing else { return true }

        switch configuration.mode {
        case .pageTurn:
            guard let onTurn else { return false }
            if onTurn(.next) {
                return true
            }
            stop()
            return false

        case .progress:
            // Upstream `AutoPager.computeOffset`: the elapsed time fills the
            // progress of the page; when the page is full it is turned.
            elapsedRemain += elapsed
            let readTime = Double(speed)
            onScroll?(min(1, elapsedRemain / readTime))
            guard elapsedRemain >= readTime else { return true }
            elapsedRemain = 0
            guard let onTurn, onTurn(.next) else {
                stop()
                return false
            }
            onScroll?(0)
            return true

        case .scroll:
            guard pageHeight > 0 else { return true }
            // Upstream: `scrollOffsetRemain += height / readTime * elapsedTime`.
            let readTime = Double(speed)
            scrollOffsetRemain += pageHeight / readTime * elapsed
            guard scrollOffsetRemain >= 1 else {
                onScroll?(progress / pageHeight)
                return true
            }
            scrollOffset = Int(scrollOffsetRemain)
            scrollOffsetRemain -= Double(scrollOffset)
            progress += Double(scrollOffset)
            if progress >= pageHeight {
                guard let onTurn, onTurn(.next) else {
                    stop()
                    return false
                }
                reset()
                onScroll?(0)
                return true
            }
            onScroll?(progress / pageHeight)
            return true
        }
    }
}
