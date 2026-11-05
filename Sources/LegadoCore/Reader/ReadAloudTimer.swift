//
//  ReadAloudTimer.swift
//  LegadoCore
//
//  The auto-stop timer of the read aloud.
//
//  Upstream source of truth:
//  app/src/main/java/io/legado/app/service/BaseReadAloudService.kt:392-432
//      fun setTimer(minute: Int) { timeMinute = minute; doDs() }
//      fun addTimer() { timeMinute += 10; if (timeMinute > 180) timeMinute = 0; doDs() }
//      private fun doDs() { ... every 60 s ...
//          if (!pause) { timeMinute--; if (timeMinute == 0) { ReadAloud.stop(...) } }
//          postEvent(EventBus.READ_ALOUD_DS, timeMinute) }
//
//  The logic lives in the Core so that it can be unit tested on Linux; the
//  SwiftUI layer only drives the ticks.
//

import Foundation

/// The countdown that stops the read aloud automatically.
///
/// The upstream counts one minute at a time and **does not count while the
/// speech is paused** (`if (!pause) { timeMinute-- }`). When the counter
/// reaches zero the speech stops.
public struct ReadAloudTimer: Equatable, Sendable {
    /// The maximum number of minutes — upstream `AppConfig.ttsTimer`
    /// (the choices are 0, 5, 10, 15, 30, 60, 90, 180).
    public static let maxMinutes = 180

    /// The number of minutes the timer was started with.
    public private(set) var minutes: Int = 0

    /// The minutes that are left — upstream `timeMinute`.
    public private(set) var remaining: Int = 0

    public init() {}

    /// Starts the timer with the given number of minutes.
    public init(minutes: Int) {
        start(minutes: minutes)
    }

    /// Starts (or cancels) the timer — upstream `setTimer(minute)`.
    public mutating func start(minutes: Int) {
        self.minutes = max(0, minutes)
        remaining = self.minutes
    }

    /// Adds ten minutes — upstream `addTimer()`.
    ///
    /// The upstream grows the counter by ten up to 180 minutes; at 180 it
    /// wraps around to zero.
    public mutating func add() {
        if minutes == Self.maxMinutes {
            minutes = 0
            remaining = 0
            return
        }
        start(minutes: min(Self.maxMinutes, minutes + 10))
    }

    /// Counts one minute down — upstream `doDs()`.
    ///
    /// - Parameter paused: whether the speech is paused; the upstream does not
    ///   count while it is.
    /// - Returns: `true` when the timer has expired and the speech must stop.
    @discardableResult
    public mutating func tick(paused: Bool) -> Bool {
        guard minutes > 0 else { return false }
        guard !paused else { return false }
        remaining = max(0, remaining - 1)
        return remaining == 0
    }

    /// Cancels the timer — upstream `ReadAloud.stop` resets the counter.
    public mutating func cancel() {
        minutes = 0
        remaining = 0
    }
}
