//
//  ReaderSystemIntegration.swift
//  LegadoUI
//
//  The reader system integrations.
//
//  Upstream `ui/book/read/BaseReadBookActivity.kt` and
//  `ui/book/read/ReadBookActivity.kt` apply a handful of system settings
//  while the reader is open:
//
//  * `keep_light` — the screen must not dim while reading
//    (`window.addFlags(FLAG_KEEP_SCREEN_ON)`);
//  * `brightness` / `nightBrightness` — the screen brightness is set when the
//    reader opens and restored when it closes;
//  * `screenOrientation` — the reader can force a rotation;
//  * `hideStatusBar` — the status bar is hidden;
//  * `volumeKeyPage` — the volume keys turn the pages.
//
//  The port applies the first four through UIKit. The volume keys need a
//  `UIEvent` subclass, which cannot be done from SwiftUI, so the port keeps
//  the preference and exposes it for a future `UIApplication` subclass.
//
//  The file compiles on Linux (the UIKit calls are guarded) so the CI job
//  type-checks it.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

#if canImport(UIKit)
import UIKit
#endif

/// Applies the reader preferences to the system.
public final class ReaderSystemIntegration: ObservableObject {

    /// The settings the integration reads.
    private let settings: AppSettings

    /// Whether the screen is kept awake.
    public var keepsScreenAwake: Bool = false

    /// The brightness that was active before the reader opened (`nil` = the
    /// user never set one).
    private var previousBrightness: Double?

    #if canImport(UIKit)
    /// The orientation the reader forces (`nil` = the system decides).
    private var forcedOrientation: UIInterfaceOrientationMask?
    #endif

    public init(settings: AppSettings) {
        self.settings = settings
    }

    // MARK: - Life cycle

    /// Applies the preferences when the reader opens.
    ///
    /// `UIApplication` and `UIScreen` are main actor isolated on Apple
    /// platforms, so the method runs on the main actor. The class itself is
    /// not isolated — it is created from a nonisolated context.
    @MainActor
    public func activate() {
        #if canImport(UIKit)
        keepsScreenAwake = settings.bool(.keepLight, default: true)
        if keepsScreenAwake {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // The brightness: the upstream applies `brightness` in the day mode and
        // `nightBrightness` in the night mode (`ReadBookActivity.kt:699`) —
        // but only when the brightness does not follow the system
        // (`ReadMenu.setScreenBrightness`).
        if !brightnessAuto {
            let night = settings.isDarkTheme
            let value = night ? settings.nightBrightness : settings.brightness
            if previousBrightness == nil {
                previousBrightness = Double(UIScreen.main.brightness)
            }
            UIScreen.main.brightness = CGFloat(min(max(Double(value) / 100.0, 0), 1))
        }

        // The orientation.
        switch settings.screenOrientation {
        case 0: forcedOrientation = .portrait
        case 1: forcedOrientation = .landscapeLeft
        case 2: forcedOrientation = .landscapeRight
        default: forcedOrientation = nil
        }
        if let forcedOrientation {
            UIApplication.shared.requestedOrientation = forcedOrientation
        }
        #endif
    }

    /// Restores the system settings when the reader closes.
    @MainActor
    public func deactivate() {
        #if canImport(UIKit)
        UIApplication.shared.isIdleTimerDisabled = false
        if let previousBrightness {
            UIScreen.main.brightness = CGFloat(previousBrightness)
            self.previousBrightness = nil
        }
        if let forcedOrientation {
            UIApplication.shared.requestedOrientation = .unknown
            self.forcedOrientation = nil
        }
        #endif
        keepsScreenAwake = false
    }

    /// The brightness the reader applies (`0...100`).
    public var brightnessPercent: Int {
        settings.isDarkTheme ? settings.nightBrightness : settings.brightness
    }

    /// Changes the screen brightness — upstream `ReadMenu.seekBrightness`
    /// (`binding.seekBrightness` writes `AppConfig.brightness` and the
    /// screen brightness).
    ///
    /// The value is a percentage (`0...100`); the setting is stored so the
    /// reader opens with it again. When the brightness follows the system, the
    /// upstream disables the slider — the port does the same.
    @MainActor
    public func setBrightness(percent: Int) {
        let value = min(max(percent, 0), 100)
        settings.brightness = value
        #if canImport(UIKit)
        if previousBrightness == nil {
            previousBrightness = Double(UIScreen.main.brightness)
        }
        UIScreen.main.brightness = CGFloat(Double(value) / 100.0)
        #endif
    }

    /// Whether the brightness follows the system — upstream
    /// `ReadMenu.brightnessAuto()`:
    /// `context.getPrefBoolean("brightnessAuto", true) || !showBrightnessView`.
    public var brightnessAuto: Bool {
        settings.bool(.brightnessAuto, default: true)
            || !settings.bool(.showBrightnessView, default: true)
    }

    /// Turns the "the brightness follows the system" mode on or off — upstream
    /// `ReadMenu.kt:380` (`context.putPrefBoolean("brightnessAuto", …)`).
    public func setBrightnessAuto(_ enabled: Bool) {
        settings.set(enabled, for: .brightnessAuto)
    }

    /// The current screen brightness as a percentage (`0...100`).
    @MainActor
    public func currentBrightnessPercent() -> Int {
        #if canImport(UIKit)
        return Int((Double(UIScreen.main.brightness) * 100).rounded())
        #else
        return brightnessPercent
        #endif
    }

    /// Whether the status bar is hidden (the upstream `hideStatusBar`).
    public var hidesStatusBar: Bool {
        settings.bool(.hideStatusBar, default: false)
    }

    /// Whether the volume keys turn the pages (the upstream `volumeKeyPage`).
    ///
    /// The port stores the preference; the event interception needs a
    /// `UIApplication` subclass that the app target installs.
    public var volumeKeysTurnPages: Bool {
        settings.bool(.volumeKeyPage, default: false)
    }
}
