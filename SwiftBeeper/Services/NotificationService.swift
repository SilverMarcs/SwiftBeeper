import Foundation
import UserNotifications
import OSLog

@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private static let messageCategory = "MESSAGE"
    private static let replyAction = "REPLY_ACTION"

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SwiftBeeper", category: "NotificationService")
    private(set) var isAuthorized = false
    var messageStore: MessageStore?

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        let reply = UNTextInputNotificationAction(
            identifier: Self.replyAction,
            title: "Reply",
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message..."
        )
        let category = UNNotificationCategory(
            identifier: Self.messageCategory,
            actions: [reply],
            intentIdentifiers: []
        )
        center.setNotificationCategories([category])

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            logger.info("Notification authorization: \(granted, privacy: .public)")
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription, privacy: .public)")
        }
    }

    func postNewMessageNotification(message: Message, chatTitle: String) {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = chatTitle
        content.body = message.displayText
        content.sound = .default
        content.threadIdentifier = message.chatID
        content.categoryIdentifier = Self.messageCategory
        content.userInfo = ["chatID": message.chatID, "messageID": message.id]

        let request = UNNotificationRequest(
            identifier: "msg-\(message.id)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // Show banner + play sound even when the app is in the foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == Self.replyAction,
              let textResponse = response as? UNTextInputNotificationResponse else {
            completionHandler()
            return
        }

        let chatID = response.notification.request.content.userInfo["chatID"] as? String ?? ""
        let replyText = textResponse.userText

        guard !chatID.isEmpty, !replyText.isEmpty else {
            completionHandler()
            return
        }

        Task { @MainActor in
            _ = await messageStore?.sendMessage(text: replyText, attachments: [], to: chatID)
        }
        completionHandler()
    }
}
