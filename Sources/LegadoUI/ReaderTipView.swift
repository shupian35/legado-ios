//
//  ReaderTipView.swift
//  LegadoUI
//
//  The header and the footer of the reader page — upstream
//  `ui/book/read/page/PageView.kt` (the tip styles of the page).
//
//  The upstream draws up to six tips (the header and the footer, each with a
//  left, a middle and a right slot); every slot holds one tip type and the
//  visibility of the header and of the footer is a preference
//  (`ReadBookConfig.headerMode` / `footerMode`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

import Foundation
import LegadoCore

/// The header or the footer of the reader page.
public struct ReaderTipView: View {

    /// The three slots of the row.
    let row: ReaderTipRenderer.Row
    /// The values the tips are rendered from.
    let context: ReaderTipContext
    /// The colour of the tips.
    let textColor: Color
    /// The size of the tips.
    let fontSize: Double

    public init(
        row: ReaderTipRenderer.Row,
        context: ReaderTipContext,
        textColor: Color = .secondary,
        fontSize: Double = 11
    ) {
        self.row = row
        self.context = context
        self.textColor = textColor
        self.fontSize = fontSize
    }

    public var body: some View {
        HStack(spacing: 4) {
            slot(row.left, alignment: .leading)
            Spacer()
            slot(row.middle, alignment: .center)
            Spacer()
            slot(row.right, alignment: .trailing)
        }
        .font(.system(size: fontSize))
        .foregroundColor(textColor)
    }

    @ViewBuilder
    private func slot(_ type: ReaderTipType, alignment: HorizontalAlignment) -> some View {
        if let text = ReaderTipRenderer.text(for: type, context: context) {
            Text(text)
                .lineLimit(1)
        }
    }
}

/// The battery level of the device — upstream `PageView.upBattery`.
///
/// The upstream reads the battery of the system; on iOS the battery
/// monitoring has to be switched on first. `UIDevice` is a main-actor API on
/// Apple platforms, so the value is read on the main actor and cached — the
/// synchronous getter never leaves the caller's thread.
public enum ReaderBattery {

    /// The cache of the level.
    private static let cache = BatteryCache()

    /// The level of the battery in percent (100 when it is unknown).
    public static var level: Int { cache.level }

    /// Refreshes the cached battery level.
    public static func refresh() {
        #if canImport(UIKit) && !os(watchOS)
        Task { @MainActor in
            let device = UIDevice.current
            device.isBatteryMonitoringEnabled = true
            let value = device.batteryLevel
            device.isBatteryMonitoringEnabled = false
            cache.level = value >= 0 ? Int((value * 100).rounded()) : 100
        }
        #endif
    }
}

/// The thread-safe cache of the battery level.
private final class BatteryCache: @unchecked Sendable {

    private let lock = NSLock()
    private var storage: Int = 100

    var level: Int {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
        set {
            lock.lock()
            storage = newValue
            lock.unlock()
        }
    }
}
