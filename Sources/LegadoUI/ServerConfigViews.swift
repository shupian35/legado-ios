//
//  ServerConfigViews.swift
//  LegadoUI
//
//  The WebDAV servers of the remote-book browser — the port of
//  `ui/book/import/remote/ServersDialog.kt` (the list) and
//  `ui/book/import/remote/ServerConfigDialog.kt` (the editor).
//
//  The user adds the WebDAV servers and picks the one the remote-book
//  browser uses; the "default" entry means "the account of the backup
//  screen" (upstream `AppConst.DEFAULT_WEBDAV_ID`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The list of the synchronisation servers — upstream `ServersDialog`.
public struct ServersView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var servers: [Server] = []
    /// The id of the picked server — upstream `adapter.selectServerId`.
    @State private var selectedId: Int64 = ServerManager.defaultServerId
    /// The server that is edited — upstream `ServerConfigDialog(server.id)`.
    @State private var editing: Server?
    /// The server that is about to be deleted — upstream the alert.
    @State private var pendingDelete: Server?

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        List {
            // Upstream `ServersDialog.tvFooterLeft` — the "default" entry
            // picks the app's own account.
            HStack {
                Button {
                    selectedId = ServerManager.defaultServerId
                } label: {
                    Image(systemName: selectedId == ServerManager.defaultServerId ? "largecircle.filled.circle" : "circle")
                }
                .buttonStyle(PlainButtonStyle())
                Text("默认")
                Spacer()
            }
            ForEach(servers) { server in
                HStack {
                    Button {
                        selectedId = server.id
                    } label: {
                        Image(systemName: selectedId == server.id ? "largecircle.filled.circle" : "circle")
                    }
                    .buttonStyle(PlainButtonStyle())
                    Text(server.name)
                    Spacer()
                    // Upstream `binding.ivEdit`.
                    Button("编辑") {
                        editing = server
                    }
                    .buttonStyle(PlainButtonStyle())
                    // Upstream `binding.ivDelete`.
                    Button("删除") {
                        pendingDelete = server
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .navigationTitle("服务器配置")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Upstream `ServersDialog.menu_add`.
                Button("添加") {
                    editing = ServerManager.newServer(
                        name: "",
                        credentials: WebDavCredentials(url: "", username: "", password: ""),
                        sortNumber: Int64(servers.count)
                    )
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                // Upstream `binding.tvCancel`.
                Button("取消") {
                    model.setSelectedRemoteServerId(selectedId)
                }
                Spacer()
                // Upstream `binding.tvOk`.
                Button("确定") {
                    model.setSelectedRemoteServerId(selectedId)
                }
                .font(.system(size: 16, weight: .semibold))
            }
            .padding()
        }
        .sheet(item: $editing) { server in
            ServerEditorView(server: server) { saved in
                model.saveWebDavServer(saved)
                reload()
            }
        }
        .confirmationDialog(
            "确定删除",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { server in
            Button("删除", role: .destructive) {
                model.deleteWebDavServer(server)
                reload()
            }
            Button("取消", role: .cancel) {}
        } message: { server in
            Text(server.name)
        }
        .onAppear {
            reload()
        }
    }

    private func reload() {
        model.reloadWebDavServers()
        servers = model.webDavServers
        selectedId = model.selectedRemoteServerId
    }
}

/// The editor of a synchronisation server — upstream `ServerConfigDialog`.
///
/// The upstream has three fields (the url, the user name and the password)
/// and the name of the server.
public struct ServerEditorView: View {

    @State private var name: String
    @State private var url: String
    @State private var username: String
    @State private var password: String
    @State private var sortNumber: Int64
    private let id: Int64

    private let onSave: (Server) -> Void

    public init(server: Server, onSave: @escaping (Server) -> Void) {
        let credentials = ServerManager.credentials(of: server)
        _name = State(initialValue: server.name)
        _url = State(initialValue: credentials?.url ?? "")
        _username = State(initialValue: credentials?.username ?? "")
        _password = State(initialValue: credentials?.password ?? "")
        _sortNumber = State(initialValue: server.sortNumber)
        id = server.id
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("名称", text: $name)
                    TextField("url", text: $url)
                        .legadoNoAutocapitalization()
                        .autocorrectionDisabled()
                    TextField("username", text: $username)
                        .legadoNoAutocapitalization()
                        .autocorrectionDisabled()
                    SecureField("password", text: $password)
                }
                Section {
                    Button("保存") {
                        onSave(
                            ServerManager.makeServer(
                                id: id,
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                credentials: WebDavCredentials(
                                    url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                                    password: password
                                ),
                                sortNumber: sortNumber
                            )
                        )
                    }
                }
            }
            .navigationTitle("服务器配置")
        }
    }
}
