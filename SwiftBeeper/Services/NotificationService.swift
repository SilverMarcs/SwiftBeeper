import Foundation
import UserNotifications
import OSLog

@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SwiftBeeper", category: "NotificationService")
    private(set) var isAuthorized = false

    func requestAuthorization() async {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

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
}
