import Foundation

/// The WebDAV side of backups and reading progress — the port of
/// `app/src/main/java/io/legado/app/help/AppWebDav.kt`.
///
/// Three independent flows share one account:
///
/// * **backups** — the ZIP produced by `LegadoBackup` sits at the server root;
/// * **reading progress** — one JSON file per book in `bookProgress/`, named
///   `<name>_<author>.json` (see `BookProgress.fileName`);
/// * **uploaded books and background images** — `books/` and `background/`.
///
/// Upstream runs `upConfig()` from an object initialiser, i.e. it performs
/// blocking network I/O while the Kotlin object is first touched. The port
/// keeps every call async and explicit instead — same behaviour, no surprise
/// I/O.
public actor WebDavService {

    public let client: WebDavClient

    public init(client: WebDavClient) {
        self.client = client
    }

    public init(configuration: WebDavConfiguration, httpClient: any HttpClient = URLSessionHttpClient()) {
        self.client = WebDavClient(configuration: configuration, httpClient: httpClient)
    }

    public nonisolated var configuration: WebDavConfiguration {
        client.configuration
    }

    // MARK: - Authorization

    public func checkAuthorization() async throws {
        try await client.checkAuthorization()
    }

    // MARK: - Backups

    /// Every backup file at the server root, newest name first — the upstream
    /// `getBackupNames()`.
    public func backupNames() async throws -> [WebDavFile] {
        let files = try await client.list(configuration.backupDirectory, depth: 1)
        return files
            .filter { !$0.isDirectory && $0.name.hasPrefix("backup") }
            .sorted { $0.name > $1.name }
    }

    /// Uploads a finished backup.
    public func uploadBackup(_ archive: BackupArchive) async throws {
        let data = try archive.zip()
        try await client.upload(data, to: path(in: configuration.backupDirectory, archive.fileName))
    }

    /// Downloads a backup by file name.
    public func downloadBackup(named name: String) async throws -> Data {
        try await client.download(path(in: configuration.backupDirectory, name))
    }

    /// Whether a backup with this name already exists — used to avoid
    /// re-uploading an unchanged daily backup.
    public func hasBackup(named name: String) async throws -> Bool {
        try await backupNames().contains { $0.name == name }
    }

    // MARK: - Reading progress

    /// Uploads one book's progress.
    public func uploadProgress(_ progress: BookProgress) async throws {
        let data = try JSONEncoder().encode(progress)
        try await client.upload(
            data,
            to: path(in: configuration.bookProgressDirectory, progress.fileName),
            contentType: "application/json"
        )
    }

    /// Downloads one book's progress.
    public func downloadProgress(fileName: String) async throws -> BookProgress {
        let data = try await client.download(path(in: configuration.bookProgressDirectory, fileName))
        return try JSONDecoder().decode(BookProgress.self, from: data)
    }

    /// Every progress file the server holds.
    public func progressFiles() async throws -> [WebDavFile] {
        try await client.list(configuration.bookProgressDirectory, depth: 1)
            .filter { !$0.isDirectory && $0.name.hasSuffix(".json") }
    }

    /// Downloads every progress file, skipping the ones that do not parse.
    public func downloadAllProgress() async throws -> [(file: WebDavFile, progress: BookProgress)] {
        var result: [(WebDavFile, BookProgress)] = []
        for file in try await progressFiles() {
            guard let progress = try? await downloadProgress(fileName: file.name) else { continue }
            result.append((file, progress))
        }
        return result
    }

    /// Whether a remote progress should replace the local one.
    ///
    /// Upstream adopts the remote value only when it is strictly further into
    /// the book — a chapter index comparison first, then the character
    /// position — and only when the local copy is older than the remote file.
    public nonisolated static func shouldAdopt(
        remote: BookProgress,
        local: BookProgress?,
        remoteModified: Date? = nil,
        localSyncedAt: Date? = nil
    ) -> Bool {
        guard let local else { return true }
        if remote.durChapterIndex > local.durChapterIndex { return true }
        if remote.durChapterIndex < local.durChapterIndex { return false }
        if remote.durChapterPos > local.durChapterPos { return true }
        if remote.durChapterPos < local.durChapterPos { return false }
        // Same place: only time matters.
        if let remoteModified, let localSyncedAt, remoteModified > localSyncedAt { return true }
        return remote.durChapterTime > local.durChapterTime
    }

    // MARK: - Helpers

    private func path(in directory: String, _ name: String) -> String {
        directory.isEmpty ? name : directory + name
    }
}
