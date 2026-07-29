import SwiftUI

#if os(macOS)
typealias PlatformApplicationDelegate = NSApplicationDelegate
#else
typealias PlatformApplicationDelegate = UIApplicationDelegate
#endif

@MainActor
final class AppDelegate: NSObject, PlatformApplicationDelegate {
    #if os(iOS)
    static weak var notificationService: NotificationService?
    #endif

    #if os(macOS)
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let backend = EasyMatrixBackend.shared
        guard backend.isRunning else { return .terminateNow }

        Task { @MainActor in
            await backend.stop()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
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
