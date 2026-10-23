import SwiftUI
import UserNotifications

#if os(macOS)
typealias PlatformApplicationDelegate = NSApplicationDelegate
typealias PlatformApplication = NSApplication
#else
typealias PlatformApplicationDelegate = UIApplicationDelegate
typealias PlatformApplication = UIApplication
#endif

@MainActor
final class AppDelegate: NSObject, PlatformApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var notificationService: NotificationService?
    static weak var chatStore: ChatStore?
    static weak var inputManager: InputManager?
    #if os(macOS)
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        NotificationService.registerCategories()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Self.chatStore?.setAppActive(true)
    }

    func applicationDidResignActive(_ notification: Notification) {
        Self.chatStore?.setAppActive(false)
    }
    #else
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationService.registerCategories()
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
            let chatID = content.userInfo["chatID"] as? String ?? content.threadIdentifier
            if content.userInfo["replyDraft"] == nil,
               Self.notificationService?.isAppActive == true,
               !chatID.isEmpty, Self.chatStore?.visibleChatID == chatID {
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
            let chatID = content.userInfo["chatID"] as? String ?? content.threadIdentifier
            guard !chatID.isEmpty else { return }
            if let reply = response as? UNTextInputNotificationResponse,
               response.actionIdentifier == NotificationCategory.reply {
                let text = reply.userText
                let messageID = content.userInfo["messageID"] as? String
                await Self.sendReply(text, chatID: chatID, messageID: messageID)
            } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                let draft = content.userInfo["replyDraft"] as? String
                if let draft { Self.inputManager?.restoreNotificationDraft(draft, for: chatID) }
                Self.chatStore?.openNotificationChat(chatID)
            }
        }
    }

    @MainActor private static func sendReply(_ text: String, chatID: String, messageID: String?) async {
        #if !os(macOS)
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Notification Reply")
        defer {
            if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
        }
        #endif
        await notificationService?.reply(text, to: chatID, messageID: messageID)
    }
}
