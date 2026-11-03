//
//  BackupView.swift
//  LegadoUI
//
//  The backup and restore screen — upstream `ui/about/backup/` and the
//  WebDAV section of the settings.
//
//  The backup format is the upstream one: a ZIP with one JSON file per table
//  plus the preferences (`Storage/Backup.swift`), optionally encrypted for the
//  `servers` table, and it can be uploaded to a WebDAV server
//  (`Storage/WebDavService.swift`).
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif

import Foundation
import LegadoCore

/// The backup screen.
public struct BackupView: View {

    @ObservedObject var model: LegadoAppModel

    @State private var isWorking = false
    @State private var status: String?
    @State private var localBackups: [URL] = []
    @State private var remoteBackups: [String] = []
    @State private var webDavUrl: String = ""
    @State private var webDavAccount: String = ""
    @State private var webDavPassword: String = ""
    /// Whether the folder picker is open — upstream `selectBackupPath`.
    @State private var isSelectingDirectory = false

    public init(model: LegadoAppModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("本地备份") {
                Button("立即备份") {
                    backup()
                }
                Button("选择备份目录") {
                    isSelectingDirectory = true
                }
                Text(backupDirectory.path)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if !localBackups.isEmpty {
                    ForEach(localBackups, id: \.path) { url in
                        HStack {
                            Text(url.lastPathComponent)
                                .font(.system(size: 13))
                            Spacer()
                            Button("恢复") {
                                restore(url)
                            }
                            .font(.system(size: 13))
                        }
                    }
                }
            }
            Section("WebDAV") {
                TextField("地址", text: $webDavUrl)
                TextField("账号", text: $webDavAccount)
                SecureField("密码", text: $webDavPassword)
                Button("上传备份到 WebDAV") {
                    uploadToWebDav()
                }
                Button("刷新远端备份列表") {
                    loadRemoteBackups()
                }
                ForEach(remoteBackups, id: \.self) { name in
                    HStack {
                        Text(name)
                            .font(.system(size: 13))
                        Spacer()
                        Button("下载恢复") {
                            restoreFromWebDav(name)
                        }
                        .font(.system(size: 13))
                    }
                }
            }
            if isWorking {
                ProgressView("正在处理…")
            }
            if let status {
                Section {
                    Text(status)
                        .font(.system(size: 13))
                }
            }
        }
        .navigationTitle("备份与恢复")
        .onAppear {
            webDavUrl = model.environment.settings.webDavUrl ?? ""
            webDavAccount = model.environment.settings.webDavAccount ?? ""
            webDavPassword = model.environment.settings.webDavPassword ?? ""
            loadLocalBackups()
        }
        .fileImporter(
            isPresented: $isSelectingDirectory,
            allowedContentTypes: [.folder]
        ) { result in
            if case let .success(url) = result {
                selectDirectory(url)
            }
        }
    }

    // MARK: - The backup directory

    /// The directory the local backups live in.
    ///
    /// The upstream keeps the folder in `PreferKey.backupPath`
    /// (`backupUri`) and lets the user pick it with the system folder picker
    /// (`BackupConfigFragment.selectBackupPath`); the default is
    /// `<documents>/backup`.
    private var backupDirectory: URL {
        if let path = model.environment.settings.backupPath, !path.isEmpty {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        let base = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("backup", isDirectory: true)
    }

    /// Stores the picked folder — upstream `PreferKey.backupPath`.
    private func selectDirectory(_ url: URL) {
        model.environment.settings.backupPath = url.path
        loadLocalBackups()
        status = "备份目录：\(url.lastPathComponent)"
    }

    private func loadLocalBackups() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        localBackups = files
            .filter { $0.pathExtension.lowercased() == "zip" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    // MARK: - The actions

    private func backup() {
        isWorking = true
        status = nil
        do {
            let archive = try LegadoBackup.make(
                store: model.environment.store.tableStore,
                settings: backupSettings(),
                preferences: preferences()
            )
            let data = try archive.zip()
            let directory = backupDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(archive.fileName)
            // A folder the user picked needs the security scope.
            try withSecurityScope(url) {
                try data.write(to: url)
            }
            loadLocalBackups()
            status = "备份完成：\(archive.fileName)"
        } catch {
            status = "备份失败：\(error.localizedDescription)"
        }
        isWorking = false
    }

    private func restore(_ url: URL) {
        isWorking = true
        status = nil
        do {
            let data = try Data(contentsOf: url)
            let summary = try LegadoBackup.restore(
                zipData: data,
                store: model.environment.store.tableStore,
                settings: backupSettings()
            )
            let applied = applyPreferences(in: data)
            model.reloadAll()
            status = "恢复完成：\(summary.restoredRows) 条记录，\(applied) 项设置"
        } catch {
            status = "恢复失败：\(error.localizedDescription)"
        }
        isWorking = false
    }

    /// Restores the preferences of a backup, skipping the ignored groups —
    /// upstream `Restore.restoreConfig` + `BackupConfig.keyIsNotIgnore`.
    private func applyPreferences(in data: Data) -> Int {
        let preferences = (try? LegadoBackup.preferences(inZipData: data)) ?? [:]
        let ignore = BackupIgnoreConfig.load(from: model.environment.settings.settingsStore)
        return LegadoBackup.applyPreferences(
            preferences,
            to: model.environment.settings.settingsStore,
            ignore: ignore
        )
    }

    private func uploadToWebDav() {
        isWorking = true
        status = nil
        Task {
            do {
                let archive = try LegadoBackup.make(
                    store: model.environment.store.tableStore,
                    settings: backupSettings(),
                    preferences: preferences()
                )
                let service = webDavService()
                try await service.uploadBackup(archive)
                status = "已上传：\(archive.fileName)"
            } catch {
                status = "上传失败：\(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    private func loadRemoteBackups() {
        isWorking = true
        Task {
            do {
                let files = try await webDavService().backupNames()
                remoteBackups = files.map { $0.name }
                status = "远端备份 \(remoteBackups.count) 个"
            } catch {
                status = "读取失败：\(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    private func restoreFromWebDav(_ name: String) {
        isWorking = true
        Task {
            do {
                let data = try await webDavService().downloadBackup(named: name)
                let summary = try LegadoBackup.restore(
                    zipData: data,
                    store: model.environment.store.tableStore,
                    settings: backupSettings()
                )
                let applied = applyPreferences(in: data)
                model.reloadAll()
                status = "恢复完成：\(summary.restoredRows) 条记录，\(applied) 项设置"
            } catch {
                status = "恢复失败：\(error.localizedDescription)"
            }
            isWorking = false
        }
    }

    // MARK: - The helpers

    /// The backup settings — upstream `BackupConfig`.
    ///
    /// The cipher key comes from the local password (upstream
    /// `help/storage/BackupAES.kt` → `LocalConfig.password`), not from the
    /// WebDAV password.
    private func backupSettings() -> BackupSettings {
        BackupSettings(
            password: model.environment.localConfig.password,
            deviceName: model.environment.settings.webDavDeviceName,
            onlyLatestBackup: model.environment.settings.onlyLatestBackup,
            ignoreLocalBook: false
        )
    }

    /// The preferences that go into `config.xml`.
    private func preferences() -> [String: String] {
        var result: [String: String] = [:]
        for key in SettingsKey.allCases {
            if let value = model.environment.settings.string(key) {
                result[key.rawValue] = value
            }
        }
        return result
    }

    /// The WebDAV client built from the settings.
    private func webDavService() -> WebDavService {
        let configuration = WebDavConfiguration(
            url: webDavUrl,
            username: webDavAccount,
            password: webDavPassword,
            backupDirectory: "",
            bookProgressDirectory: "bookProgress/",
            booksDirectory: "books/",
            backgroundDirectory: "background/"
        )
        return WebDavService(
            configuration: configuration,
            httpClient: model.environment.httpClient
        )
    }
}

/// Runs the body with the security scope of a URL the user picked.
///
/// The API only exists on the Apple platforms — on Linux the body runs
/// directly.
private func withSecurityScope<T>(_ url: URL, _ body: () throws -> T) rethrows -> T {
    #if os(iOS) || os(macOS)
    let scoped = url.startAccessingSecurityScopedResource()
    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
    #endif
    return try body()
}
