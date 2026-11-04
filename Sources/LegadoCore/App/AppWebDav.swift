//
//  AppWebDav.swift
//  LegadoCore
//
//  The WebDAV account of the app — the port of the upstream's `AppWebDav`.
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/help/AppWebDav.kt:40-337
//  app/src/main/java/io/legado/app/ui/config/BackupConfigFragment.kt:109-218
//

import Foundation

/// The WebDAV account of the app — upstream `AppWebDav`.
///
/// The upstream stores the account in the preferences
/// (`PreferKey.webDavUrl` / `webDavAccount` / `webDavPassword` /
/// `webDavDir` / `webDavDeviceName`) and NOT in the `servers` table (that
/// table holds the servers the user added for the remote books). The root URL
/// is the configured address plus the root folder, with a trailing slash.
public struct AppWebDavAccount: Equatable, Sendable {

    /// The address of the server — upstream `PreferKey.webDavUrl`.
    public var url: String
    /// The account — upstream `PreferKey.webDavAccount`.
    public var account: String
    /// The password — upstream `PreferKey.webDavPassword`.
    public var password: String
    /// The root folder on the server — upstream `PreferKey.webDavDir`.
    public var directory: String
    /// The name of the device — upstream `PreferKey.webDavDeviceName`.
    public var deviceName: String

    /// The address the upstream uses when none is configured — upstream
    /// `AppWebDav.defaultWebDavUrl`.
    public static let defaultURL = "https://dav.jianguoyun.com/dav/"

    /// The name of the folder the upstream uses when no directory is set —
    /// upstream `BackupConfigFragment.kt:216`.
    public static let defaultDirectory = "legado"

    public init(
        url: String = "",
        account: String = "",
        password: String = "",
        directory: String = "",
        deviceName: String = ""
    ) {
        self.url = url
        self.account = account
        self.password = password
        self.directory = directory
        self.deviceName = deviceName
    }

    /// The root URL of the server — upstream `AppWebDav.rootWebDavUrl`.
    ///
    /// The configured address (or the default one), the root folder and a
    /// trailing slash.
    public var rootURL: String {
        var url = self.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.isEmpty { url = Self.defaultURL }
        if !url.hasSuffix("/") { url += "/" }
        let directory = self.directory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !directory.isEmpty {
            url += directory.hasSuffix("/") ? directory : directory + "/"
        }
        return url
    }

    /// Whether the account is usable — upstream `AppWebDav.isOk`.
    ///
    /// The upstream needs both the account and the password.
    public var isConfigured: Bool {
        !account.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    /// The URL of the folder with the reading progress — upstream
    /// `AppWebDav.bookProgressUrl`.
    public var bookProgressURL: String { rootURL + "bookProgress/" }

    /// The URL of the folder with the exported books — upstream
    /// `AppWebDav.exportsWebDavUrl`.
    public var booksURL: String { rootURL + "books/" }

    /// The URL of the folder with the backgrounds — upstream
    /// `AppWebDav.bgWebDavUrl`.
    public var backgroundURL: String { rootURL + "background/" }

    /// The credentials of the account.
    public var credentials: WebDavCredentials {
        WebDavCredentials(url: rootURL, username: account, password: password)
    }

    /// The configuration of the WebDAV service.
    public var serviceConfiguration: WebDavConfiguration {
        WebDavConfiguration(
            url: rootURL,
            username: account,
            password: password,
            backupDirectory: "",
            bookProgressDirectory: "bookProgress/",
            booksDirectory: "books/",
            backgroundDirectory: "background/"
        )
    }

    /// The summary of the account — the password is masked, as the upstream
    /// does (`BackupConfigFragment.kt:212`).
    public var summary: String {
        guard !account.isEmpty else { return "未配置" }
        return "\(account) \(String(repeating: "*", count: password.count))"
    }
}
