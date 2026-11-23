import SwiftUI
import OSLog
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
    private static let notificationLogger = Logger(subsystem: "com.SilverMarcs.Relay", category: "foreground-notifications")

    #if os(macOS)
    func applicationDidFinishLaunching(_ notification: Notification) {
        prepareNotificationCenter()
        ChatTextSize.zoomInOnUnshiftedPlus()
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
        // A launch straight into the background, such as for a notification
        // reply, may never show a scene to close the Matrix store before iOS
        // suspends the app. Close it after each command until a scene is active.
        if application.applicationState == .background {
            Task { await MatrixRuntime.shared.setKeepsOpen(false) }
        }
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
        let content = notification.request.content
        // Capture the chat at arrival, before the settings lookup can suspend
        // us while the reader navigates away or the app becomes inactive.
        if await MainActor.run(body: { Self.shouldSuppress(content) }) { return [] }
        #if os(iOS)
        let settings = await center.notificationSettings()
        let soundsAllowed = settings.authorizationStatus == .authorized && settings.soundSetting == .enabled
        #endif
        return await MainActor.run {
            // Also cover opening the notified chat during that lookup.
            if Self.shouldSuppress(content) { return [] }
            #if os(macOS)
            guard Self.notificationService?.isAppActive == true else { return [.banner, .sound] }
            #endif
            Self.notificationLogger.info("Foreground notification decision: present; has-visible-chat: \(Self.chatStore?.visibleChatID != nil), selected-chat-matches: \(Self.chatStore?.selectedChatID == content.chatID)")
            #if os(iOS)
            if content.categoryIdentifier == NotificationCategory.message,
               content.replyDraft == nil,
               let messageID = content.userInfo["messageID"] as? String {
                Self.notificationService?.messageSounds.notificationSoundsAllowed = soundsAllowed
                Self.notificationService?.messageSounds.received(
                    messageID: messageID,
                    isMuted: Self.chatStore?.chat(byID: content.chatID)?.isMuted == true,
                    isMention: content.userInfo["isMention"] as? Bool == true,
                    fromForegroundNotification: true
                )
                // The conversation sound replaces the foreground alert sound.
                return [.banner]
            }
            #endif
            return [.banner, .sound]
        }
    }

    /// The extension may time out before it sets the message category. The
    /// original APNs room/event IDs still identify that fallback notification.
    private static func shouldSuppress(_ content: UNNotificationContent) -> Bool {
        guard content.categoryIdentifier != NotificationCategory.reminder, content.replyDraft == nil else { return false }
        if let messageID = content.userInfo["messageID"] as? String,
           notificationService?.hasSeenMessage(messageID) == true {
            notificationLogger.info("Foreground notification decision: suppress-seen-message")
            return true
        }
        #if os(macOS)
        guard notificationService?.isAppActive == true else { return false }
        #endif
        // iOS calls willPresent only for foreground delivery; scenePhase may
        // still be catching up, so it must not gate this visibility check.
        if !content.chatID.isEmpty, chatStore?.visibleChatID == content.chatID {
            notificationLogger.info("Foreground notification decision: suppress-visible-chat")
            return true
        }
        return false
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
                Self.chatStore?.openNotificationChat(chatID, threadRootID: content.threadRootID)
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
