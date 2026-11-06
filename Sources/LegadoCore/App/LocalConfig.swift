//
//  LocalConfig.swift
//  LegadoCore
//
//  Port of the upstream `help/config/LocalConfig.kt`.
//
//  Upstream keeps these preferences in their own SharedPreferences file
//  (`local`), separate from the app preferences, so that they are **not**
//  written into a backup: the password encrypts the sensitive parts of a
//  backup (`help/storage/BackupAES.kt`) and must not travel with it.
//

import Foundation

/// The preferences that stay on the device — upstream `LocalConfig`.
public final class LocalConfig {

    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    /// The underlying store.
    public var settingsStore: SettingsStore { store }

    /// The local password — upstream `LocalConfig.password`.
    ///
    /// It is the key of the `servers.json` entry of a backup (the upstream
    /// derives the AES key with `MD5Utils.md5Encode(password)`). A `nil`
    /// value means the user has never chosen one; an empty string means the
    /// user declined to set one (the upstream behaves the same way).
    public var password: String? {
        get { store.string(forKey: LocalConfig.passwordKey) }
        set { store.set(newValue, forKey: LocalConfig.passwordKey) }
    }

    /// The key of the password in the store.
    public static let passwordKey = "password"

    /// Whether the privacy policy has been accepted — upstream
    /// `LocalConfig.privacyPolicyOk`.
    public var privacyPolicyAccepted: Bool {
        get { store.bool(forKey: "privacyPolicyOk") ?? false }
        set { store.set(newValue, forKey: "privacyPolicyOk") }
    }

    /// The version code of the app that was used the last time — upstream
    /// `LocalConfig.versionCode` (the key is `appVersionCode`).
    ///
    /// The startup sequence uses it to decide whether the changelog has to be
    /// shown.
    public var versionCode: Int {
        get { store.int(forKey: "appVersionCode") ?? 0 }
        set { store.set(newValue, forKey: "appVersionCode") }
    }

    /// The time of the last backup — upstream `LocalConfig.lastBackup`.
    public var lastBackup: Date? {
        get {
            let value = store.int(forKey: "lastBackup") ?? 0
            return value > 0 ? Date(timeIntervalSince1970: Double(value) / 1000.0) : nil
        }
        set {
            let millis = newValue.map { Int($0.timeIntervalSince1970 * 1000) } ?? 0
            store.set(millis, forKey: "lastBackup")
        }
    }

    /// Whether the app has been opened before — upstream
    /// `LocalConfig.isFirstOpenApp` (which flips the flag when it is read).
    public var isFirstOpen: Bool {
        get {
            let value = store.bool(forKey: "firstOpen") ?? true
            if value {
                store.set(false, forKey: "firstOpen")
            }
            return value
        }
    }

    /// Whether the crash report has to be shown — upstream
    /// `LocalConfig.appCrash`.
    public var appCrash: Bool {
        get { store.bool(forKey: "appCrash") ?? false }
        set { store.set(newValue, forKey: "appCrash") }
    }

    /// Whether the original file of a book is deleted with the book —
    /// upstream `LocalConfig.deleteBookOriginal`.
    public var deleteBookOriginal: Bool {
        get { store.bool(forKey: "deleteBookOriginal") ?? false }
        set { store.set(newValue, forKey: "deleteBookOriginal") }
    }

    /// Whether the book information screen asks before it deletes a book —
    /// upstream `LocalConfig.bookInfoDeleteAlert`.
    ///
    /// The upstream toggles it in the book information menu
    /// (`menu_delete_alert`) and reads it when the book is deleted.
    public var bookInfoDeleteAlert: Bool {
        get { store.bool(forKey: "bookInfoDeleteAlert") ?? false }
        set { store.set(newValue, forKey: "bookInfoDeleteAlert") }
    }

    /// The sorting of the reading records — upstream
    /// `ReadRecordActivity.sortMode` (`LocalConfig.getInt("readRecordSort")`).
    public var readRecordSort: ReadRecordSort {
        get { ReadRecordSort(rawValue: store.int(forKey: "readRecordSort") ?? 0) ?? .name }
        set { store.set(newValue.rawValue, forKey: "readRecordSort") }
    }

    /// The bearer token of the local web service.
    ///
    /// The upstream `web/HttpServer.kt` has **no** authentication at all, which
    /// means every web page the user visits can read the whole bookshelf and
    /// rewrite the book sources. The port requires a token instead; it is
    /// generated once and injected into the served web page
    /// (`WebAssets.accessToken`).
    ///
    /// It lives in the local configuration — not in the app preferences —
    /// because a backup must not carry a secret.
    public var webServiceToken: String {
        get {
            if let token = store.string(forKey: LocalConfig.webServiceTokenKey), !token.isEmpty {
                return token
            }
            let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            store.set(token, forKey: LocalConfig.webServiceTokenKey)
            return token
        }
        set { store.set(newValue, forKey: LocalConfig.webServiceTokenKey) }
    }

    /// The key of the token of the local web service.
    public static let webServiceTokenKey = "webServiceToken"

    // MARK: - The version counters of the default data

    /// Whether the default HTTP TTS engines have to be imported — upstream
    /// `LocalConfig.needUpHttpTTS` (`!isLastVersion(6, "httpTtsVersion")`).
    public var needsDefaultHttpTTS: Bool {
        isOutdated(6, forKey: "httpTtsVersion")
    }

    /// Records that the default HTTP TTS engines were imported.
    public func markDefaultHttpTTSImported() {
        markImported(6, forKey: "httpTtsVersion")
    }

    /// Whether the default TXT table of contents rules have to be imported —
    /// upstream `LocalConfig.needUpTxtTocRule`
    /// (`!isLastVersion(3, "txtTocRuleVersion")`).
    public var needsDefaultTxtTocRules: Bool {
        isOutdated(3, forKey: "txtTocRuleVersion")
    }

    /// Records that the default TXT table of contents rules were imported.
    public func markDefaultTxtTocRulesImported() {
        markImported(3, forKey: "txtTocRuleVersion")
    }

    /// Whether the default RSS sources have to be imported — upstream
    /// `LocalConfig.needUpRssSources` (`!isLastVersion(6, "rssSourceVersion")`).
    public var needsDefaultRssSources: Bool {
        isOutdated(6, forKey: "rssSourceVersion")
    }

    /// Records that the default RSS sources were imported.
    public func markDefaultRssSourcesImported() {
        markImported(6, forKey: "rssSourceVersion")
    }

    /// Whether the default dictionary rules have to be imported — upstream
    /// `LocalConfig.needUpDictRule` (`!isLastVersion(2, "needUpDictRule")`).
    public var needsDefaultDictRules: Bool {
        isOutdated(2, forKey: "needUpDictRule")
    }

    /// Records that the default dictionary rules were imported.
    public func markDefaultDictRulesImported() {
        markImported(2, forKey: "needUpDictRule")
    }

    /// Forgets which default data sets were imported, so the next upgrade run
    /// imports them again.
    ///
    /// A build whose schema creation failed raised those counters before the
    /// import threw — the device then kept the counters while the tables (and
    /// the default RSS sources) were missing. Once the schema is repaired the
    /// counters have to be cleared for the data to come back.
    public func resetDefaultDataVersions() {
        for key in [
            "httpTtsVersion",
            "txtTocRuleVersion",
            "rssSourceVersion",
            "needUpDictRule"
        ] {
            store.set(0, forKey: key)
        }
    }

    /// The port of upstream `LocalConfig.isLastVersion`, split from the write:
    /// the version is only raised once the import **succeeded** (see
    /// `markImported`). The upstream check raises the counter first, so an
    /// import that throws is skipped forever — which is exactly what happened
    /// when the schema was broken.
    private func isOutdated(_ lastVersion: Int, forKey key: String) -> Bool {
        (store.int(forKey: key) ?? 0) < lastVersion
    }

    private func markImported(_ version: Int, forKey key: String) {
        store.set(version, forKey: key)
    }
}
