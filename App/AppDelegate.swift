import SwiftUI
import UserNotifications

#if os(macOS)
typealias PlatformApplicationDelegate = NSApplicationDelegate
typealias PlatformApplication = NSApplication
#else
typealias PlatformApplicationDelegate = UIApplicationDelegate
typealias PlatformApplication = UIApplication
#endif

/// Receives APNs tokens and notification actions, and on macOS app activation.
@MainActor
final class AppDelegate: NSObject, PlatformApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var notificationService: NotificationService?
    static weak var chatStore: ChatStore?
    static weak var inputManager: InputManager?

    #if os(macOS)
    func applicationDidFinishLaunching(_ notification: Notification) {
        prepareNotificationCenter()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Self.chatStore?.setAppActive(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        Self.chatStore?.setAppActive(false)
    }
    #else
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        prepareNotificationCenter()
        return true
    }
    #endif

    func application(_ application: PlatformApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Self.notificationService?.receivedDeviceToken(deviceToken)
    }

    func application(_ application: PlatformApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Self.notificationService?.registrationFailed(error)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            // Stay quiet for the chat already on screen.
            let content = notification.request.content
            if content.replyDraft == nil,
               Self.notificationService?.isAppActive == true,
               !content.chatID.isEmpty, Self.chatStore?.visibleChatID == content.chatID {
                return []
            }
            return [.banner, .sound]
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        Task { @MainActor in
            // UIKit updates its snapshot when this completes; finish on the main actor.
            defer { completionHandler() }
            let content = response.notification.request.content
            let chatID = content.chatID
            guard !chatID.isEmpty else { return }
            if let reply = response as? UNTextInputNotificationResponse,
               response.actionIdentifier == NotificationCategory.reply {
                await Self.sendReply(reply.userText, chatID: chatID, messageID: content.userInfo["messageID"] as? String)
            } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                if let draft = content.replyDraft { Self.inputManager?.restoreNotificationDraft(draft, for: chatID) }
                Self.chatStore?.openNotificationChat(chatID)
            }
        }
    }

    /// Runs at launch, before any notification or action is delivered.
    private func prepareNotificationCenter() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.registerRelayCategories()
    }

    private static func sendReply(_ text: String, chatID: String, messageID: String?) async {
        #if !os(macOS)
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Notification Reply")
        defer {
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }
        #endif
        await notificationService?.reply(text, to: chatID, messageID: messageID)
    }
}
