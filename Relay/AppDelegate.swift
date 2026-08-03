import SwiftUI

#if os(macOS)
typealias PlatformApplicationDelegate = NSApplicationDelegate
#else
typealias PlatformApplicationDelegate = UIApplicationDelegate
#endif

@MainActor
final class AppDelegate: NSObject, PlatformApplicationDelegate {
    #if os(macOS)
    static weak var chatStore: ChatStore?
    #else
    static weak var notificationService: NotificationService?
    #endif

    #if os(macOS)
    func applicationDidBecomeActive(_ notification: Notification) {
        Self.chatStore?.handleAppActivation(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        Self.chatStore?.handleAppActivation(false)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        #if REMOTE_ONLY
        .terminateNow
        #else
        let backend = EasyMatrixBackend.shared
        guard backend.isRunning else { return .terminateNow }

        Task { @MainActor in
            await backend.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
        #endif
    }
    #else
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Self.notificationService?.didRegisterForRemoteNotifications(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Self.notificationService?.didFailToRegisterForRemoteNotifications(error)
    }
    #endif
}
