//
//  AppStartup.swift
//  LegadoCore
//
//  The startup sequence of the application.
//
//  Upstream `app/src/main/java/io/legado/app/ui/main/MainActivity.kt:117-140`
//  runs the following steps when the window is created:
//
//      1. the privacy policy has to be accepted,
//      2. the version is checked (the help of the app on the first run, the
//         changelog after an update),
//      3. the local password is set,
//      4. a crash of the reader is reported,
//      5. the WebDAV server is checked for a newer backup,
//      6. the books are updated when the preference is on.
//
//  The port runs the same steps; the ones that need the user live in
//  `LegadoUI/AppStartupViews.swift`.
//

import Foundation

/// The document the app shows when it starts — upstream
/// `MainActivity.upVersion()`.
public enum StartupDocument: String, Equatable, Sendable {

    /// The help of the app — upstream `assets/web/help/md/appHelp.md`.
    case appHelp

    /// The changelog — upstream `assets/updateLog.md`.
    case updateLog

    /// The title of the document.
    public var title: String {
        switch self {
        case .appHelp: return "帮助"
        case .updateLog: return "更新日志"
        }
    }
}

/// The startup steps — upstream `MainActivity.onPostCreate()`.
public enum StartupService {

    /// Whether the privacy policy still has to be accepted — upstream
    /// `MainActivity.privacyPolicy()`.
    public static func needsPrivacyPolicy(localConfig: LocalConfig) -> Bool {
        !localConfig.privacyPolicyAccepted
    }

    /// The document that has to be shown after an update — upstream
    /// `MainActivity.upVersion()`.
    ///
    /// The upstream compares the version code of the app with the one that
    /// was stored the last time it ran; when they differ the new code is
    /// stored and the changelog (or the help of the app on the very first
    /// run) is shown.
    public static func startupDocument(
        localConfig: LocalConfig,
        versionCode: Int
    ) -> StartupDocument? {
        guard localConfig.versionCode != versionCode else { return nil }
        localConfig.versionCode = versionCode
        // `isFirstOpen` flips its own flag when it is read, so it must only be
        // read when the version has actually changed.
        if localConfig.isFirstOpen { return .appHelp }
        return .updateLog
    }

    /// Whether the reader crashed and the user should be offered the crash
    /// log — upstream `MainActivity.notifyAppCrash()`.
    ///
    /// The flag is reset, so the question is asked only once.
    public static func needsCrashPrompt(localConfig: LocalConfig) -> Bool {
        guard localConfig.appCrash else { return false }
        localConfig.appCrash = false
        return true
    }

    /// Whether the daily automatic backup is due — upstream
    /// `Backup.shouldBackup()`.
    ///
    /// The upstream backs up once a day; the time of the last backup is kept
    /// in `LocalConfig.lastBackup`.
    public static func shouldAutoBackup(
        localConfig: LocalConfig,
        now: Date = Date()
    ) -> Bool {
        let last = localConfig.lastBackup ?? .distantPast
        return last.addingTimeInterval(86_400) < now
    }
}
