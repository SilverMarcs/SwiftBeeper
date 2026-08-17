import SwiftUI

#if os(macOS)
typealias PlatformApplicationDelegate = NSApplicationDelegate
typealias PlatformApplication = NSApplication
#else
typealias PlatformApplicationDelegate = UIApplicationDelegate
typealias PlatformApplication = UIApplication
#endif

@MainActor
final class AppDelegate: NSObject, PlatformApplicationDelegate {
    static weak var notificationService: NotificationService?
    #if os(macOS)
    static weak var chatStore: ChatStore?
    #endif

    // APNs registration is identical on both platforms: `NSApplication` and
    // `UIApplication` declare the same delegate selectors, so one
    // implementation keyed on `PlatformApplication` serves both.
    func application(
        _ application: PlatformApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Self.notificationService?.didRegisterForRemoteNotifications(deviceToken)
    }

    func application(
        _ application: PlatformApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Self.notificationService?.didFailToRegisterForRemoteNotifications(error)
    }

    #if os(macOS)
    func applicationDidBecomeActive(_ notification: Notification) {
        Self.chatStore?.handleAppActivation(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        Self.chatStore?.handleAppActivation(false)
    }
    #endif
}
