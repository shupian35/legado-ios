//
//  LauncherIcon.swift
//  LegadoCore
//
//  Port of the upstream launcher icon handling:
//
//  · `help/LauncherIconHelp.kt`   — `changeIcon(icon: String?)`.
//  · `ui/config/ThemeConfigFragment.kt` — the picker.
//
//  Upstream keeps six launcher activities (`Launcher1` … `Launcher6`) and
//  enables the one the user picked; the preference `launcherIcon` holds the
//  name of that activity. The iOS port uses the same preference value and
//  maps it onto the alternate icons of the app bundle (`CFBundleAlternateIcons`).
//

import Foundation

/// The alternate launcher icons of the app.
///
/// The raw values are the upstream activity names, so a preference file
/// written by the Android app can be read by the port.
public enum LauncherIcon: String, CaseIterable, Identifiable, Sendable {
    case launcher1 = "Launcher1"
    case launcher2 = "Launcher2"
    case launcher3 = "Launcher3"
    case launcher4 = "Launcher4"
    case launcher5 = "Launcher5"
    case launcher6 = "Launcher6"

    public var id: String { rawValue }

    /// The number of the icon — the upstream order.
    public var index: Int {
        Int(rawValue.suffix(1)) ?? 0
    }

    /// The name of the icon inside the app bundle (`CFBundleAlternateIcons`).
    ///
    /// The primary icon has no name: `nil` restores it.
    public var alternateName: String {
        "Icon\(index)"
    }

    /// The name shown in the picker.
    public var displayName: String {
        switch self {
        case .launcher1: return "图标一"
        case .launcher2: return "图标二"
        case .launcher3: return "图标三"
        case .launcher4: return "图标四"
        case .launcher5: return "图标五"
        case .launcher6: return "图标六"
        }
    }

    /// The icon of the given preference value; `nil` for the primary icon.
    public static func from(_ value: String?) -> LauncherIcon? {
        guard let value, !value.isEmpty else { return nil }
        return LauncherIcon(rawValue: value)
    }
}
