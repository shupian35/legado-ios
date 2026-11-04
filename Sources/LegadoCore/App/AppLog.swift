import Foundation

/// The in-memory application log — the port of upstream
/// `app/src/main/java/io/legado/app/constant/AppLog.kt`.
///
/// Upstream keeps the log in memory (NOT in the database): `put` inserts the
/// entry at the front and drops the oldest one when the list grows beyond 100
/// entries; `putDebug` only records when the `recordLog` preference is on;
/// `clear()` empties the list. The entries are shown by the app log dialog
/// (upstream `ui/about/AppLogDialog.kt`).
public final class AppLog: @unchecked Sendable {

    /// One log entry — the upstream `Triple<Long, String, Throwable?>`.
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: Int
        public let time: Date
        public let message: String
        /// The stack trace of the error, when there was one.
        public let errorDescription: String?

        public init(id: Int, time: Date, message: String, errorDescription: String? = nil) {
            self.id = id
            self.time = time
            self.message = message
            self.errorDescription = errorDescription
        }
    }

    /// The shared instance — upstream `AppLog` is an `object`.
    public static let shared = AppLog()

    /// The maximum number of entries (upstream `mLogs.size > 100`).
    public static let limit = 100

    private let lock = NSLock()
    private var entries: [Entry] = []
    private var nextId = 0

    public init() {}

    /// The entries, the newest first — upstream `AppLog.logs`.
    public var logs: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    /// Upstream `AppLog.put` — records the message (with an optional error).
    @discardableResult
    public func put(_ message: String, error: Error? = nil) -> Entry? {
        guard !message.isEmpty else { return nil }
        lock.lock()
        defer { lock.unlock() }
        if entries.count >= AppLog.limit {
            entries.removeLast()
        }
        let entry = Entry(
            id: nextId,
            time: Date(),
            message: message,
            errorDescription: error.map { String(describing: $0) }
        )
        nextId += 1
        entries.insert(entry, at: 0)
        return entry
    }

    /// Upstream `AppLog.putDebug` — only recorded when the `recordLog`
    /// preference is on.
    @discardableResult
    public func putDebug(_ message: String, error: Error? = nil, recordLog: Bool) -> Entry? {
        guard recordLog else { return nil }
        return put(message, error: error)
    }

    /// Upstream `AppLog.clear`.
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }

    /// The upstream log time format (`LogUtils.logTimeFormat`).
    public static func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
