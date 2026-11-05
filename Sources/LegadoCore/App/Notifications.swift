//
//  Notifications.swift
//  LegadoCore
//
//  The notification channels.
//
//  Upstream registers three notification channels in `App.kt:179-222`
//  (`channel_download`, `channel_read_aloud`, `channel_web`) and posts the
//  download progress, the read-aloud state and the local web service state
//  through them.
//
//  The port keeps the channel identifiers and the content model platform
//  independent; the `UNUserNotificationCenter` binding lives in the UI
//  target (`LegadoUI/Notifications.swift`) because UserNotifications only
//  exists on Apple platforms.
//

import Foundation

/// The notification channels of the app (the upstream `AppConst` ids).
public enum NotificationChannel: String, CaseIterable, Sendable {
    /// The download / cache progress.
    case download = "channel_download"
    /// The read-aloud state.
    case readAloud = "channel_read_aloud"
    /// The local web service.
    case web = "channel_web"

    /// The user visible name of the channel (the upstream string resources).
    public var title: String {
        switch self {
        case .download: return "下载"
        case .readAloud: return "朗读"
        case .web: return "网页服务"
        }
    }

    /// The identifier used by the platform notification center.
    public var identifier: String { rawValue }
}

/// The identifiers of the resident notifications — upstream
/// `constant/NotificationId.kt`.
///
/// A notification with an identifier is UPDATED IN PLACE by the platform
/// (the upstream `notificationManager.notify(NotificationId.CacheBookService, …)`),
/// so the download progress does not pile up in the notification centre.
public enum NotificationId {
    public static let readAloudService = 101
    public static let audioPlayService = 102
    public static let cacheBookService = 103
    public static let exportBookService = 104
    public static let webService = 105
    public static let downloadService = 106
    public static let checkSourceService = 107
    public static let download = 10000
    public static let exportBook = 201
}

/// A button of a notification (the upstream `Notification.Action`).
public struct NotificationAction: Equatable, Sendable {
    /// The identifier of the action.
    public var id: String
    /// The user visible title.
    public var title: String
    /// Whether the action is destructive.
    public var isDestructive: Bool

    public init(id: String, title: String, isDestructive: Bool = false) {
        self.id = id
        self.title = title
        self.isDestructive = isDestructive
    }

    /// The six actions of the upstream read-aloud transport notification
    /// (`service/BaseReadAloudService.kt:604-670`).
    public static let readAloudActions: [NotificationAction] = [
        NotificationAction(id: "prevChapter", title: "上一章"),
        NotificationAction(id: "prevParagraph", title: "上一段"),
        NotificationAction(id: "toggle", title: "暂停"),
        NotificationAction(id: "nextParagraph", title: "下一段"),
        NotificationAction(id: "nextChapter", title: "下一章"),
        NotificationAction(id: "stop", title: "停止")
    ]

    /// The 取消 action of the download notification — upstream
    /// `CacheBookService` adds `IntentAction.stop` to it.
    public static let downloadActions: [NotificationAction] = [
        NotificationAction(id: "cancel", title: "取消", isDestructive: true)
    ]
}

/// The content of a notification.
public struct NotificationContent: Equatable, Sendable {
    /// The channel the notification belongs to.
    public var channel: NotificationChannel
    /// The identifier of the notification — a notification with an identifier
    /// replaces the previous one with the same identifier (the upstream
    /// resident notifications of the services).
    public var identifier: Int?
    /// The title of the notification.
    public var title: String
    /// The subtitle (the upstream `setSubText`).
    public var subtitle: String?
    /// The body of the notification.
    public var body: String?
    /// The progress in `0...1` (the upstream download progress).
    public var progress: Double?
    /// The user info (the upstream `setContentIntent` extras).
    public var userInfo: [String: String]
    /// The buttons of the notification.
    public var actions: [NotificationAction]

    public init(
        channel: NotificationChannel,
        identifier: Int? = nil,
        title: String,
        subtitle: String? = nil,
        body: String? = nil,
        progress: Double? = nil,
        userInfo: [String: String] = [:],
        actions: [NotificationAction] = []
    ) {
        self.channel = channel
        self.identifier = identifier
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.progress = progress
        self.userInfo = userInfo
        self.actions = actions
    }

    /// The download progress notification (upstream `DownloadService`).
    public static func download(bookName: String, progress: Double, chapterTitle: String? = nil) -> NotificationContent {
        var content = NotificationContent(
            channel: .download,
            identifier: NotificationId.cacheBookService,
            title: chapterTitle ?? bookName,
            subtitle: bookName,
            progress: min(max(progress, 0), 1)
        )
        content.userInfo["bookName"] = bookName
        if let chapterTitle { content.userInfo["chapterTitle"] = chapterTitle }
        return content
    }

    /// The resident download notification — upstream `CacheBookService`.
    ///
    /// The upstream notification is ongoing, it carries the fixed identifier
    /// `NotificationId.CacheBookService` (⇒ it is updated in place instead of
    /// piling up), its title is 离线缓存, its body is the summary of ALL the
    /// downloads and it carries the 取消 action.
    public static func downloadSummary(
        summary: String,
        progress: Double? = nil,
        bookName: String? = nil
    ) -> NotificationContent {
        var content = NotificationContent(
            channel: .download,
            identifier: NotificationId.cacheBookService,
            title: "离线缓存",
            body: summary,
            progress: progress,
            actions: NotificationAction.downloadActions
        )
        if let bookName { content.userInfo["bookName"] = bookName }
        return content
    }

    /// The read-aloud notification (upstream `BaseReadAloudService`).
    ///
    /// The upstream transport notification carries the six media actions.
    public static func readAloud(
        bookName: String,
        chapterTitle: String,
        isPlaying: Bool,
        actions: [NotificationAction] = NotificationAction.readAloudActions
    ) -> NotificationContent {
        var content = NotificationContent(
            channel: .readAloud,
            title: chapterTitle,
            subtitle: bookName,
            body: isPlaying ? "正在朗读" : "已暂停",
            userInfo: ["bookName": bookName, "chapterTitle": chapterTitle],
            actions: actions
        )
        // The pause button becomes a resume button while the reader is paused.
        content.actions = content.actions.map { action in
            action.id == "toggle"
                ? NotificationAction(id: action.id, title: isPlaying ? "暂停" : "继续", isDestructive: action.isDestructive)
                : action
        }
        return content
    }

    /// The web service notification (upstream `WebService`).
    public static func webService(address: String, port: Int) -> NotificationContent {
        NotificationContent(
            channel: .web,
            title: "网页服务已启动",
            body: "\(address):\(port)",
            userInfo: ["address": address, "port": String(port)]
        )
    }

    /// The resident notification of the source check — upstream
    /// `CheckSourceService.upNotification`.
    ///
    /// The upstream notification is ongoing, it carries the fixed identifier
    /// `NotificationId.CheckSourceService`, the title 检查书源, the progress
    /// (the finished sources / the total) and a 取消 action.
    public static func checkSource(
        message: String,
        finished: Int,
        total: Int
    ) -> NotificationContent {
        var content = NotificationContent(
            channel: .readAloud,
            identifier: NotificationId.checkSourceService,
            title: "检查书源",
            body: message,
            progress: total > 0 ? Double(finished) / Double(total) : nil,
            actions: NotificationAction.downloadActions
        )
        content.userInfo["finished"] = String(finished)
        content.userInfo["total"] = String(total)
        return content
    }

    /// The resident notification of the export — upstream
    /// `ExportBookService.upExportNotification`.
    ///
    /// The upstream notification is ongoing while it runs, it carries the
    /// fixed identifier `NotificationId.ExportBook`, the subtitle 导出书 and a
    /// 取消 action.
    public static func exportBook(message: String, progress: Double? = nil) -> NotificationContent {
        NotificationContent(
            channel: .download,
            identifier: NotificationId.exportBook,
            title: "导出书",
            body: message,
            progress: progress,
            actions: NotificationAction.downloadActions
        )
    }

    /// The notification of a file download — upstream `DownloadService`.
    ///
    /// The upstream notification is ongoing, it carries the identifier
    /// `NotificationId.Download + downloads.size` (⇒ every download has its
    /// own notification), the title is "<fileName> <状态>" and it carries the
    /// 取消 action (`IntentAction.stop`).
    public static func downloadFile(
        fileName: String,
        state: String,
        identifier: Int,
        progress: Double? = nil
    ) -> NotificationContent {
        NotificationContent(
            channel: .download,
            identifier: identifier,
            title: "\(fileName) \(state)",
            progress: progress,
            actions: NotificationAction.downloadActions
        )
    }
}

/// The platform independent sink of the notifications.
public protocol NotificationPosting: AnyObject {
    /// Posts a notification.
    func post(_ content: NotificationContent)
}

/// A sink that keeps the notifications in memory (the tests and the Linux
/// build use it).
public final class NotificationRecorder: NotificationPosting, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [NotificationContent] = []

    public init() {}

    /// The posted notifications, oldest first.
    public var notifications: [NotificationContent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public func post(_ content: NotificationContent) {
        lock.lock()
        storage.append(content)
        lock.unlock()
    }

    /// The notifications of one channel.
    public func notifications(for channel: NotificationChannel) -> [NotificationContent] {
        notifications.filter { $0.channel == channel }
    }

    /// Removes every recorded notification.
    public func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

/// The helper that builds the notification contents of the app.
public enum AppNotifications {

    /// The three channels the upstream registers.
    public static var channels: [NotificationChannel] { NotificationChannel.allCases }

    /// The download progress notification.
    public static func downloadProgress(bookName: String, completed: Int, total: Int) -> NotificationContent {
        let progress = total > 0 ? Double(completed) / Double(total) : 0
        return .download(bookName: bookName, progress: progress)
    }
}
