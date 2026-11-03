//
//  Notifications.swift
//  LegadoUI
//
//  The `UNUserNotificationCenter` binding.
//
//  The channel model lives in `LegadoCore/App/Notifications.swift`; this file
//  only registers the channels with the system and posts the notifications.
//

#if canImport(SwiftUI)
import SwiftUI
#else
import LegadoUIShim
#endif
import Foundation
import LegadoCore

#if canImport(UserNotifications)
import UserNotifications

/// The notification center of the app.
public final class NotificationService: NSObject, NotificationPosting, @unchecked Sendable {

    /// The shared service.
    public static let shared = NotificationService()

    private let center: UNUserNotificationCenter

    private override init() {
        center = UNUserNotificationCenter.current()
        super.init()
    }

    /// Asks for the permission and registers the channels.
    public func prepare() async {
        do {
            try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // The user declined (or the system refused): the app keeps working
            // without notifications.
        }
        var categories: [UNNotificationCategory] = []
        for channel in AppNotifications.channels {
            let actions: [UNNotificationAction]
            switch channel {
            case .readAloud:
                // The upstream transport notification carries the six media
                // actions (`service/BaseReadAloudService.kt:604-670`).
                actions = NotificationAction.readAloudActions.map { action in
                    UNNotificationAction(
                        identifier: action.id,
                        title: action.title,
                        options: action.isDestructive ? [.destructive] : []
                    )
                }
            default:
                actions = []
            }
            categories.append(
                UNNotificationCategory(
                    identifier: channel.identifier,
                    actions: actions,
                    intentIdentifiers: [],
                    options: []
                )
            )
        }
        center.setNotificationCategories(Set(categories))
    }

    public func post(_ content: NotificationContent) {
        let settings = UNMutableNotificationContent()
        settings.title = content.title
        if let subtitle = content.subtitle { settings.subtitle = subtitle }
        if let body = content.body { settings.body = body }
        settings.sound = nil
        settings.userInfo = content.userInfo
        // The category carries the actions of the notification.
        settings.categoryIdentifier = content.channel.identifier
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: settings,
            trigger: nil
        )
        center.add(request)
    }
}
#else

/// The Linux stand-in (the notifications do not exist there).
public final class NotificationService: NotificationPosting, @unchecked Sendable {

    public static let shared = NotificationService()

    public init() {}

    public func prepare() async {}

    public func post(_ content: NotificationContent) {}
}
#endif
