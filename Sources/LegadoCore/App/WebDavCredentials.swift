//
//  WebDavCredentials.swift
//  LegadoCore
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/data/entities/Server.kt:51-58 (the
//  `WebDavConfig` of a server) and
//  app/src/main/java/io/legado/app/help/AppWebDav.kt (the default server).
//
//  The WebDAV server of the app is stored in the `servers` table — a row of
//  the kind `webDav` whose `config` column holds the JSON
//  `{"url":…,"username":…,"password":…}`.
//

import Foundation

/// The credentials of the WebDAV server — upstream `Server.WebDavConfig`.
public struct WebDavCredentials: Equatable, Sendable {

    public var url: String
    public var username: String
    public var password: String

    public init(url: String, username: String, password: String) {
        self.url = url
        self.username = username
        self.password = password
    }

    /// Whether the server is configured — upstream `AppWebDav.isConfigured`.
    public var isConfigured: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The JSON of the upstream's `WebDavConfig`.
    public var json: String {
        "{\"url\":\(Self.quote(url)),\"username\":\(Self.quote(username)),\"password\":\(Self.quote(password))}"
    }

    /// Parses the JSON of the upstream's `WebDavConfig`.
    public static func parse(_ json: String?) -> WebDavCredentials? {
        guard let json, !json.isEmpty else { return nil }
        guard let value = try? JSONValue.parse(json), let object = value.objectValue else { return nil }
        let url = object["url"]?.stringValue ?? ""
        let username = object["username"]?.stringValue ?? ""
        let password = object["password"]?.stringValue ?? ""
        return WebDavCredentials(url: url, username: username, password: password)
    }

    /// The configuration of the WebDAV service — the port of the upstream's
    /// `AppWebDav` (the book progress lives in `bookProgress/`).
    public func serviceConfiguration() -> WebDavConfiguration {
        WebDavConfiguration(
            url: url,
            username: username,
            password: password,
            backupDirectory: "",
            bookProgressDirectory: "bookProgress/",
            booksDirectory: "books/",
            backgroundDirectory: "background/"
        )
    }

    private static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
