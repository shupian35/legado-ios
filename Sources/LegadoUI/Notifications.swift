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
public final class NotificationService: NSObject, NotificationPosting, UNUserNotificationCenterDelegate, @unchecked Sendable {

    /// The shared service.
    public static let shared = NotificationService()

    private let center: UNUserNotificationCenter

    /// The handler of the action buttons of the notifications — upstream
    /// `BaseReadAloudService` handles the six media actions of the transport
    /// notification.
    ///
    /// The identifier is the one of `NotificationAction.readAloudActions`.
    public var actionHandler: (@Sendable (String) -> Void)?

    private override init() {
        center = UNUserNotificationCenter.current()
        super.init()
        // The delegate makes the notification show up while the app is in the
        // foreground — the read-aloud notification is posted while the reader
        // is open.
        center.delegate = self
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

    // MARK: - UNUserNotificationCenterDelegate

    /// Shows the notification while the app is in the foreground.
    ///
    /// The upstream posts the read-aloud notification while the reader is
    /// open, so it has to be visible in the foreground.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    /// Handles a tapped notification or one of its buttons.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.actionIdentifier
        if identifier != UNNotificationDefaultActionIdentifier,
           identifier != UNNotificationDismissActionIdentifier {
            actionHandler?(identifier)
        }
        completionHandler()
    }
}
#else

/// The Linux stand-in (the notifications do not exist there).
public final class NotificationService: NotificationPosting, @unchecked Sendable {

    public static let shared = NotificationService()

    /// The handler of the action buttons of the notifications.
    public var actionHandler: (@Sendable (String) -> Void)?

    public init() {}

    public func prepare() async {}

    public func post(_ content: NotificationContent) {}
}
#endif
