//
//  UserNotifications.swift
//  apple-stubs
//
//  A **type-check only** stand-in for UserNotifications.
//
//  See `UIKit.swift` in this folder for the rationale. Only the declarations
//  the port uses are here and every signature mirrors the real Apple API.
//

import Foundation

// MARK: - The options

/// `UserNotifications.UNAuthorizationOptions`.
public struct UNAuthorizationOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNAuthorizationOptions(rawValue: 1 << 0)
    public static let sound = UNAuthorizationOptions(rawValue: 1 << 1)
    public static let alert = UNAuthorizationOptions(rawValue: 1 << 2)
    public static let provisional = UNAuthorizationOptions(rawValue: 1 << 6)
}

/// `UserNotifications.UNNotificationActionOptions`.
public struct UNNotificationActionOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let foreground = UNNotificationActionOptions(rawValue: 1 << 0)
    public static let destructive = UNNotificationActionOptions(rawValue: 1 << 1)
    public static let authenticationRequired = UNNotificationActionOptions(rawValue: 1 << 2)
}

/// `UserNotifications.UNNotificationCategoryOptions`.
public struct UNNotificationCategoryOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let customDismissAction = UNNotificationCategoryOptions(rawValue: 1 << 0)
    public static let hiddenPreviewsShowTitle = UNNotificationCategoryOptions(rawValue: 1 << 1)
}

/// `UserNotifications.UNAuthorizationStatus`.
public enum UNAuthorizationStatus: Int {
    case notDetermined = 0
    case denied = 1
    case authorized = 2
    case provisional = 3
    case ephemeral = 4
}

// MARK: - The content

/// `UserNotifications.UNNotificationSound`.
open class UNNotificationSound: NSObject {
    open class var defaultCriticalSound: UNNotificationSound { UNNotificationSound() }
    open class func `default`() -> UNNotificationSound { UNNotificationSound() }
    open class func named(_ name: String) -> UNNotificationSound { UNNotificationSound() }
}

/// `UserNotifications.UNMutableNotificationContent`.
open class UNMutableNotificationContent: NSObject {
    open var title: String = ""
    open var subtitle: String = ""
    open var body: String = ""
    open var sound: UNNotificationSound?
    open var userInfo: [AnyHashable: Any] = [:]
    open var categoryIdentifier: String = ""
    open var threadIdentifier: String = ""
    open var badge: NSNumber?
    public override init() { super.init() }
}

/// `UserNotifications.UNNotificationRequest`.
open class UNNotificationRequest: NSObject {
    open var identifier: String = ""
    open var content: UNMutableNotificationContent = UNMutableNotificationContent()
    open var trigger: UNNotificationTrigger?
    public init(identifier: String, content: UNMutableNotificationContent, trigger: UNNotificationTrigger?) {
        self.identifier = identifier
        self.content = content
        self.trigger = trigger
        super.init()
    }
}

/// `UserNotifications.UNNotificationTrigger`.
open class UNNotificationTrigger: NSObject {}

// MARK: - The actions

/// `UserNotifications.UNNotificationAction`.
open class UNNotificationAction: NSObject {
    open var identifier: String = ""
    open var title: String = ""
    open var options: UNNotificationActionOptions = []
    public init(identifier: String, title: String, options: UNNotificationActionOptions = []) {
        self.identifier = identifier
        self.title = title
        self.options = options
        super.init()
    }
}

/// `UserNotifications.UNNotificationCategory`.
open class UNNotificationCategory: NSObject {
    open var identifier: String = ""
    open var actions: [UNNotificationAction] = []
    open var intentIdentifiers: [String] = []
    open var options: UNNotificationCategoryOptions = []
    public init(
        identifier: String,
        actions: [UNNotificationAction],
        intentIdentifiers: [String],
        options: UNNotificationCategoryOptions = []
    ) {
        self.identifier = identifier
        self.actions = actions
        self.intentIdentifiers = intentIdentifiers
        self.options = options
        super.init()
    }
}

// MARK: - The center

/// `UserNotifications.UNNotificationPresentationOptions`.
public struct UNNotificationPresentationOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let badge = UNNotificationPresentationOptions(rawValue: 1 << 0)
    public static let sound = UNNotificationPresentationOptions(rawValue: 1 << 1)
    public static let alert = UNNotificationPresentationOptions(rawValue: 1 << 2)
    public static let list = UNNotificationPresentationOptions(rawValue: 1 << 3)
    public static let banner = UNNotificationPresentationOptions(rawValue: 1 << 4)
}

/// `UserNotifications.UNNotification`.
open class UNNotification: NSObject {
    open var request: UNNotificationRequest = UNNotificationRequest(
        identifier: "",
        content: UNMutableNotificationContent(),
        trigger: nil
    )
    open var date: Date = Date()
    public override init() { super.init() }
}

/// `UserNotifications.UNNotificationResponse`.
open class UNNotificationResponse: NSObject {
    open var notification: UNNotification = UNNotification()
    open var actionIdentifier: String = ""
    public override init() { super.init() }
}

/// `UserNotifications.UNNotificationDefaultActionIdentifier`.
public let UNNotificationDefaultActionIdentifier = "com.apple.UNNotificationDefaultActionIdentifier"

/// `UserNotifications.UNNotificationDismissActionIdentifier`.
public let UNNotificationDismissActionIdentifier = "com.apple.UNNotificationDismissActionIdentifier"

/// `UserNotifications.UNUserNotificationCenterDelegate`.
public protocol UNUserNotificationCenterDelegate: AnyObject {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    )
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    )
}

public extension UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}

/// `UserNotifications.UNUserNotificationCenter`.
open class UNUserNotificationCenter: NSObject {
    open class func current() -> UNUserNotificationCenter { UNUserNotificationCenter() }

    open weak var delegate: (any UNUserNotificationCenterDelegate)?

    open func setNotificationCategories(_ categories: Set<UNNotificationCategory>) {}
    open func getNotificationCategories(completionHandler: @escaping (Set<UNNotificationCategory>) -> Void) { completionHandler([]) }
    open func requestAuthorization(options: UNAuthorizationOptions = [], completionHandler: @escaping (Bool, Error?) -> Void) { completionHandler(true, nil) }
    open func requestAuthorization(options: UNAuthorizationOptions = []) async throws -> Bool { true }
    open func add(_ request: UNNotificationRequest, withCompletionHandler completionHandler: ((Error?) -> Void)? = nil) {}
    open func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {}
    open func removeAllPendingNotificationRequests() {}
    open func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {}
    open func removeAllDeliveredNotifications() {}
}
