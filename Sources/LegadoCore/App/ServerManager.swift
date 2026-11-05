//
//  ServerManager.swift
//  LegadoCore
//
//  Upstream reference:
//  app/src/main/java/io/legado/app/ui/book/import/remote/ServersDialog.kt (the
//  server list), app/src/main/java/io/legado/app/ui/book/import/remote/
//  ServerConfigDialog.kt (the editor) and
//  app/src/main/java/io/legado/app/data/entities/Server.kt (the row).
//
//  The user can add several WebDAV servers and pick the one the remote-book
//  browser uses. The id of the picked server is stored in the preference
//  `remoteServerId`; the sentinel `-1` means "the app's own account".
//

import Foundation

/// The synchronisation servers — upstream `ServersDialog` +
/// `ServerConfigDialog`.
public enum ServerManager {

    /// The id of the "default" server — upstream `AppConst.DEFAULT_WEBDAV_ID`.
    ///
    /// It is not a row of the `servers` table: it means "use the account of
    /// the backup screen" (`AppWebDav.defaultBookWebDav`).
    public static let defaultServerId: Int64 = -1

    /// The id of the server the remote-book browser uses — upstream
    /// `AppConfig.remoteServerId`.
    public static func selectedServerId(_ settings: AppSettings) -> Int64 {
        Int64(settings.int(.remoteServerId, default: Int(defaultServerId)))
    }

    /// Picks the server the remote-book browser uses.
    public static func selectServer(_ id: Int64, settings: AppSettings) {
        settings.set(Int(id), for: .remoteServerId)
    }

    /// The credentials of a server — upstream `Server.getWebDavConfig`.
    public static func credentials(of server: Server) -> WebDavCredentials? {
        WebDavCredentials.parse(server.config)
    }

    /// Builds a server row — upstream `ServerConfigDialog.getServer`.
    ///
    /// The type is always the WebDAV one (the upstream has a single type) and
    /// the config column holds the JSON of the credentials.
    public static func makeServer(
        id: Int64,
        name: String,
        credentials: WebDavCredentials,
        sortNumber: Int64 = 0
    ) -> Server {
        Server(
            id: id,
            name: name,
            type: Server.Kind.webDav,
            config: credentials.json,
            sortNumber: sortNumber
        )
    }

    /// A new server row — upstream `Server()` (the id is the current time).
    public static func newServer(
        name: String,
        credentials: WebDavCredentials,
        sortNumber: Int64 = 0,
        now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) -> Server {
        makeServer(id: now, name: name, credentials: credentials, sortNumber: sortNumber)
    }

    /// The servers in the order the upstream shows them — by their sort
    /// number, the name breaks a tie.
    public static func sorted(_ servers: [Server]) -> [Server] {
        servers.sorted { left, right in
            if left.sortNumber != right.sortNumber {
                return left.sortNumber < right.sortNumber
            }
            return left.name < right.name
        }
    }

    /// The root of the books of a server.
    ///
    /// The upstream uses the "books" folder of the default book WebDAV and
    /// the root of a server the user picked
    /// (`RemoteBookViewModel.initData` → `isDefaultWebdav`).
    public static func booksRoot(isDefault: Bool) -> String {
        isDefault ? "books/" : ""
    }

    /// The credentials the remote-book browser uses.
    ///
    /// The picked server wins; when there is none (or the id is the
    /// sentinel) the account of the backup screen is used — upstream
    /// `RemoteBookViewModel.initData`.
    public static func bookCredentials(
        settings: AppSettings,
        servers: [Server]
    ) -> WebDavCredentials? {
        let id = selectedServerId(settings)
        if id != defaultServerId {
            if let server = servers.first(where: { $0.id == id }) {
                return credentials(of: server)
            }
        }
        let account = settings.appWebDav
        // Upstream `AppWebDav.isOk` — the account and the password are
        // needed; the address falls back to the default one.
        guard account.isConfigured else { return nil }
        return account.credentials
    }
}
