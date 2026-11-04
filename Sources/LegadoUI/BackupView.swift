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
    /// The root folder on the server — upstream `PreferKey.webDavDir`.
    @State private var webDavDirectory: String = ""
    /// The name of the device — upstream `PreferKey.webDavDeviceName`.
    @State private var webDavDeviceName: String = ""
    /// Whether the folder picker is open — upstream `selectBackupPath`.
    @State private var isSelectingDirectory = false
    /// Whether the old-data picker is open — upstream `import_old`.
    @State private var isSelectingOldData = false

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
            Section("旧版数据") {
                Button("导入旧版数据") {
                    isSelectingOldData = true
                }
                Text("导入旧版阅读（2.x）的 myBookShelf.json、myBookSource.json 和 myBookReplaceRule.json")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Section("WebDAV") {
                TextField("地址", text: $webDavUrl)
                TextField("账号", text: $webDavAccount)
                SecureField("密码", text: $webDavPassword)
                TextField("根目录", text: $webDavDirectory)
                TextField("设备名称", text: $webDavDeviceName)
                Button("保存") {
                    saveWebDav()
                }
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
            let account = model.environment.settings.appWebDav
            webDavUrl = account.url
            webDavAccount = account.account
            webDavPassword = account.password
            webDavDirectory = account.directory
            webDavDeviceName = account.deviceName
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
        .fileImporter(
            isPresented: $isSelectingOldData,
            allowedContentTypes: [.folder, .json]
        ) { result in
            if case let .success(url) = result {
                importOldData(url)
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

    // MARK: - The old data

    /// Imports the data of the old Legado — upstream `import_old`
    /// (`BackupConfigFragment.kt:238` → `ImportOldData.importUri`).
    ///
    /// The upstream picks a folder that holds `myBookShelf.json`,
    /// `myBookSource.json` and `myBookReplaceRule.json`; a single JSON file
    /// is accepted as well — the kind is detected from its content.
    private func importOldData(_ url: URL) {
        isWorking = true
        status = nil
        do {
            let summary = try withSecurityScope(url) {
                try importOldDataFiles(in: url)
            }
            model.reloadAll()
            status = summary.isEmpty
                ? "没有找到可导入的旧版数据"
                : "导入完成：书架 \(summary.books) 本，书源 \(summary.sources) 个，替换规则 \(summary.rules) 条"
        } catch {
            status = "导入失败：\(error.localizedDescription)"
        }
        isWorking = false
    }

    /// The summary of an old-data import.
    private struct OldDataSummary {
        var books = 0
        var sources = 0
        var rules = 0
        var isEmpty: Bool { books == 0 && sources == 0 && rules == 0 }
    }

    /// Reads the old data of a folder or of a single JSON file.
    private func importOldDataFiles(in url: URL) throws -> OldDataSummary {
        var summary = OldDataSummary()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return summary
        }
        if isDirectory.boolValue {
            let shelf = url.appendingPathComponent("myBookShelf.json")
            let sources = url.appendingPathComponent("myBookSource.json")
            let rules = url.appendingPathComponent("myBookReplaceRule.json")
            if FileManager.default.fileExists(atPath: shelf.path) {
                let books = try ImportOldData.importOldBooks(
                    try String(contentsOf: shelf, encoding: .utf8),
                    existingBookUrls: Set((try? model.environment.store.allBooks())?.map(\.bookUrl) ?? [])
                )
                try model.environment.store.insert(books)
                summary.books = books.count
            }
            if FileManager.default.fileExists(atPath: sources.path) {
                let imported = try ImportOldData.importOldSources(
                    try String(contentsOf: sources, encoding: .utf8)
                )
                try model.environment.store.insert(imported)
                summary.sources = imported.count
            }
            if FileManager.default.fileExists(atPath: rules.path) {
                let imported = try ImportOldData.importOldReplaceRules(
                    try String(contentsOf: rules, encoding: .utf8)
                )
                for rule in imported {
                    try model.environment.store.insert(rule)
                }
                summary.rules = imported.count
            }
            return summary
        }
        // A single file — the kind is detected from the first item.
        let json = try String(contentsOf: url, encoding: .utf8)
        guard let value = try? JSONValue.parse(json) else {
            throw ImportOldDataError.brokenJson
        }
        let keys = firstItemKeys(of: value)
        if keys.contains("noteUrl") {
            let books = try ImportOldData.importOldBooks(
                json,
                existingBookUrls: Set((try? model.environment.store.allBooks())?.map(\.bookUrl) ?? [])
            )
            try model.environment.store.insert(books)
            summary.books = books.count
        } else if keys.contains("bookSourceUrl") {
            let imported = try ImportOldData.importOldSources(json)
            try model.environment.store.insert(imported)
            summary.sources = imported.count
        } else {
            let imported = try ImportOldData.importOldReplaceRules(json)
            for rule in imported {
                try model.environment.store.insert(rule)
            }
            summary.rules = imported.count
        }
        return summary
    }

    /// The keys of the first item of a JSON array (or of the object itself).
    private func firstItemKeys(of value: JSONValue) -> Set<String> {
        let object: JSONValue
        switch value {
        case .array(let items):
            guard let first = items.first else { return [] }
            object = first
        default:
            object = value
        }
        return Set(object.objectValue?.keys ?? [:].keys)
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
    ///
    /// The upstream stores the account in the preferences and rebuilds the
    /// client whenever one of the keys changes
    /// (`BackupConfigFragment.kt:179-186` → `AppWebDav.upConfig`); the port
    /// therefore saves the fields before every use.
    private func webDavService() -> WebDavService {
        saveWebDav()
        let account = model.environment.settings.appWebDav
        return WebDavService(
            configuration: account.serviceConfiguration,
            httpClient: model.environment.httpClient
        )
    }

    /// Saves the WebDAV account in the preferences — upstream
    /// `AppWebDav.upConfig`.
    private func saveWebDav() {
        var account = model.environment.settings.appWebDav
        account.url = webDavUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        account.account = webDavAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        account.password = webDavPassword
        account.directory = webDavDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        account.deviceName = webDavDeviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        model.environment.settings.appWebDav = account
        // The server row of the `servers` table holds the servers the user
        // added for the remote books — the app's own account is not one of
        // them, so the row is only written when it already exists.
        let credentials = account.credentials
        if (try? model.environment.store.webDavServer()) != nil {
            try? model.environment.store.saveWebDavCredentials(credentials)
        }
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
