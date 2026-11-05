//
//  ScreenAwake.swift
//  LegadoUI
//
//  The screen-awake hold of the long tasks.
//
//  Upstream:
//  - `ui/book/source/manage/BookSourceActivity.kt:507,534,629` — the source
//    check keeps the screen on while it runs,
//  - `ui/rss/read/ReadRssActivity.kt:381,389` — the RSS reader keeps it on
//    while a full-screen video is shown,
//  - `utils/ActivityExtensions.kt:178` — `Activity.keepScreenOn(on)`.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Keeps the screen awake while a long task runs.
///
/// The upstream keeps the screen on while the source check runs
/// (`BookSourceActivity.kt:507` → `keepScreenOn(true)` and `:629` →
/// `keepScreenOn(false)`); the port keeps a counter so that two overlapping
/// holds do not release each other's flag.
///
/// The counter is guarded by a lock so the type is usable from any isolation
/// domain; the `UIApplication` call is hopped to the main actor.
public enum ScreenAwake {

    private static let lock = NSLock()
    private static var holds = 0

    /// Starts a hold.
    public static func begin() {
        lock.lock()
        holds += 1
        let isFirst = holds == 1
        lock.unlock()
        guard isFirst else { return }
        #if canImport(UIKit)
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = true
        }
        #endif
    }

    /// Ends a hold — the screen goes back to the system timeout when the last
    /// hold is released.
    public static func end() {
        lock.lock()
        holds = max(0, holds - 1)
        let isReleased = holds == 0
        lock.unlock()
        guard isReleased else { return }
        #if canImport(UIKit)
        Task { @MainActor in
            UIApplication.shared.isIdleTimerDisabled = false
        }
        #endif
    }

    /// Whether a hold is active.
    public static var isHeld: Bool {
        lock.lock()
        defer { lock.unlock() }
        return holds > 0
    }
}
