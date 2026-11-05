//
//  AppLanguage.swift
//  LegadoCore
//
//  The language of the interface.
//
//  Upstream:
//  app/src/main/java/io/legado/app/base/AppContextWrapper.kt:77-84
//  (`getSetLocale`).
//

import Foundation

/// The language of the interface — upstream `AppContextWrapper.getSetLocale`
/// (`base/AppContextWrapper.kt:77-84`).
///
/// The upstream maps the `language` preference to a `Locale`:
///
/// * `"zh"` → `Locale.SIMPLIFIED_CHINESE`,
/// * `"tw"` → `Locale.TRADITIONAL_CHINESE`,
/// * `"en"` → `Locale.ENGLISH`,
/// * anything else → the system locale.
///
/// The port's interface strings are Chinese, so the selection does not
/// translate the screens; it applies the locale of the app (the system
/// dialogs, the date and number formatting and the pickers) and it is kept in
/// the backup like the upstream preference.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    /// Follow the system — the empty value of the upstream preference.
    case system = ""
    /// `"zh"` — 简体中文.
    case simplified = "zh"
    /// `"tw"` — 繁體中文.
    case traditional = "tw"
    /// `"en"` — English.
    case english = "en"

    public var id: String { rawValue }

    /// The name shown in the picker.
    public var displayName: String {
        switch self {
        case .system: return "跟随系统"
        case .simplified: return "简体中文"
        case .traditional: return "繁體中文"
        case .english: return "English"
        }
    }

    /// The locale of the language — `nil` when it follows the system.
    public var localeIdentifier: String? {
        switch self {
        case .system: return nil
        case .simplified: return "zh-Hans"
        case .traditional: return "zh-Hant"
        case .english: return "en"
        }
    }

    /// The language of a stored preference value.
    public static func from(_ value: String) -> AppLanguage {
        AppLanguage(rawValue: value) ?? .system
    }

    /// The locale of the interface — the selected language or the system one.
    public var locale: Locale {
        guard let identifier = localeIdentifier else { return .autoupdatingCurrent }
        return Locale(identifier: identifier)
    }

    /// Applies the language to the app — the upstream restarts the process
    /// (`appCtx.restart()` in `OtherConfigFragment.kt:201`); on Apple platforms
    /// the `AppleLanguages` preference takes effect at the next launch, which
    /// is the closest equivalent.
    ///
    /// The call is a no-op on the platforms without the preference.
    public static func apply(_ language: AppLanguage) {
        #if os(iOS) || os(macOS)
        let defaults = UserDefaults.standard
        if let identifier = language.localeIdentifier {
            defaults.set([identifier], forKey: "AppleLanguages")
        } else {
            defaults.removeObject(forKey: "AppleLanguages")
        }
        defaults.synchronize()
        #endif
    }
}
