//
//  ServerManagerTests.swift
//  LegadoCoreTests
//
//  The WebDAV servers of the remote-book browser — the port of the upstream
//  `ServersDialog` + `ServerConfigDialog` (`AppConst.DEFAULT_WEBDAV_ID` =
//  -1, the preference `remoteServerId`).
//

import XCTest
@testable import LegadoCore

final class ServerManagerTests: XCTestCase {

    private func settings() -> (AppSettings, InMemorySettingsStore) {
        let store = InMemorySettingsStore()
        return (AppSettings(store: store), store)
    }

    private func credentials(
        url: String = "https://dav.example.com",
        username: String = "user",
        password: String = "secret"
    ) -> WebDavCredentials {
        WebDavCredentials(url: url, username: username, password: password)
    }

    // MARK: - The default server

    func testDefaultServerIdIsMinusOne() {
        // Upstream `AppConst.DEFAULT_WEBDAV_ID`.
        XCTAssertEqual(ServerManager.defaultServerId, -1)
    }

    func testSelectedServerIdDefaultsToTheSentinel() {
        let (settings, _) = self.settings()
        XCTAssertEqual(ServerManager.selectedServerId(settings), ServerManager.defaultServerId)
    }

    func testSelectServerWritesThePreference() {
        let (settings, store) = self.settings()
        ServerManager.selectServer(42, settings: settings)
        XCTAssertEqual(store.int(forKey: SettingsKey.remoteServerId.rawValue), 42)
        XCTAssertEqual(ServerManager.selectedServerId(settings), 42)
    }

    // MARK: - The rows

    func testMakeServerUsesTheWebDavTypeAndTheCredentialsJson() {
        let server = ServerManager.makeServer(
            id: 7,
            name: "我的服务器",
            credentials: credentials()
        )
        XCTAssertEqual(server.id, 7)
        XCTAssertEqual(server.name, "我的服务器")
        XCTAssertEqual(server.type, Server.Kind.webDav)
        let parsed = ServerManager.credentials(of: server)
        XCTAssertEqual(parsed?.url, "https://dav.example.com")
        XCTAssertEqual(parsed?.username, "user")
        XCTAssertEqual(parsed?.password, "secret")
    }

    func testNewServerUsesTheCurrentTimeAsTheId() {
        let server = ServerManager.newServer(
            name: "新的",
            credentials: credentials(),
            now: 1_700_000_000_000
        )
        XCTAssertEqual(server.id, 1_700_000_000_000)
        XCTAssertEqual(server.sortNumber, 0)
    }

    func testSortedUsesTheSortNumberThenTheName() {
        let servers = [
            Server(id: 1, name: "B", sortNumber: 2),
            Server(id: 2, name: "A", sortNumber: 1),
            Server(id: 3, name: "C", sortNumber: 1)
        ]
        let sorted = ServerManager.sorted(servers)
        XCTAssertEqual(sorted.map(\.name), ["A", "C", "B"])
    }

    func testCredentialsOfAServerWithoutAConfigIsNil() {
        let server = Server(id: 1, name: "空的")
        XCTAssertNil(ServerManager.credentials(of: server))
    }

    // MARK: - The books of the browser

    func testBooksRootOfTheDefaultServerIsTheBooksFolder() {
        // Upstream `RemoteBookViewModel.upPath` — the default WebDAV uses
        // the "books" folder, a picked server uses its root.
        XCTAssertEqual(ServerManager.booksRoot(isDefault: true), "books/")
        XCTAssertEqual(ServerManager.booksRoot(isDefault: false), "")
    }

    func testBookCredentialsUsesThePickedServer() {
        let (settings, _) = self.settings()
        let server = ServerManager.makeServer(
            id: 5,
            name: "服务器",
            credentials: credentials(url: "https://picked.example.com")
        )
        ServerManager.selectServer(5, settings: settings)
        let resolved = ServerManager.bookCredentials(
            settings: settings,
            servers: [server]
        )
        XCTAssertEqual(resolved?.url, "https://picked.example.com")
    }

    func testBookCredentialsFallsBackToTheAppAccount() {
        let (settings, _) = self.settings()
        settings.appWebDav = AppWebDavAccount(
            url: "https://app.example.com",
            account: "app-user",
            password: "app-secret",
            directory: "",
            deviceName: ""
        )
        let resolved = ServerManager.bookCredentials(settings: settings, servers: [])
        // Upstream `AppWebDav.rootWebDavUrl` — the address gets a trailing slash.
        XCTAssertEqual(resolved?.url, "https://app.example.com/")
        XCTAssertEqual(resolved?.username, "app-user")
    }

    func testBookCredentialsIsNilWhenNothingIsConfigured() {
        let (settings, _) = self.settings()
        XCTAssertNil(ServerManager.bookCredentials(settings: settings, servers: []))
    }

    // MARK: - The store

    func testStoreReadsAndDeletesTheServers() throws {
        let store = LegadoStore(tables: MemoryTableStore())
        let server = ServerManager.makeServer(
            id: 9,
            name: "服务器",
            credentials: credentials()
        )
        try store.insert(server)
        let all = try store.allServers()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(try store.server(id: 9)?.name, "服务器")
        XCTAssertEqual(try store.webDavCredentials()?.username, "user")

        try store.deleteServer(server)
        XCTAssertTrue(try store.allServers().isEmpty)
    }
}
