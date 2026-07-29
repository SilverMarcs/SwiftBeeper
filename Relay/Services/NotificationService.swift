import Foundation
import UserNotifications
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    nonisolated private static let messageCategory = "MESSAGE"
    nonisolated private static let replyAction = "REPLY_ACTION"

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Relay", category: "NotificationService")
    private(set) var isAuthorized = false
    private(set) var prefersRemoteNotifications = false
    weak var store: ChatStore?
    weak var serverConnection: ServerConnection?
    weak var sessionStore: SessionStore?
    private var deviceToken: String?

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
            if granted {
                registerForRemoteNotifications()
            }
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription, privacy: .public)")
        }
    }

    func didRegisterForRemoteNotifications(_ data: Data) {
        // Apple recommends asking APNs for the current token on every launch,
        // rather than treating a previously saved value as permanent.
        deviceToken = data.map { byte in
            let value = String(byte, radix: 16)
            return value.count == 1 ? "0\(value)" : value
        }.joined()
        Task { await syncRemoteRegistration() }
    }

    func didFailToRegisterForRemoteNotifications(_ error: Error) {
        logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    func syncRemoteRegistration() async {
        guard isAuthorized,
              let deviceToken,
              serverConnection?.usesEmbeddedServer == false,
              sessionStore?.accessToken.isEmpty == false else {
            prefersRemoteNotifications = false
            return
        }

        do {
            prefersRemoteNotifications = try await APIClient.registerPushDevice(token: deviceToken)
            logger.info("Registered this device for remote notifications")
        } catch {
            prefersRemoteNotifications = false
            logger.error("Could not register push device: \(error.localizedDescription, privacy: .public)")
        }
    }

    func unregisterRemoteRegistration() async {
        guard let deviceToken,
              serverConnection?.usesEmbeddedServer == false,
              sessionStore?.accessToken.isEmpty == false else {
            prefersRemoteNotifications = false
            return
        }

        do {
            try await APIClient.unregisterPushDevice(token: deviceToken)
        } catch {
            logger.error("Could not unregister push device: \(error.localizedDescription, privacy: .public)")
        }
        prefersRemoteNotifications = false
    }

    private func registerForRemoteNotifications() {
        #if os(macOS)
        NSApplication.shared.registerForRemoteNotifications()
        #else
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    func postNewMessageNotification(message: Message, chatTitle: String) {
        guard isAuthorized, !prefersRemoteNotifications else { return }

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
        let chatID = response.notification.request.content.userInfo["chatID"] as? String ?? ""

        if response.actionIdentifier == Self.replyAction,
           let textResponse = response as? UNTextInputNotificationResponse {
            let replyText = textResponse.userText
            guard !chatID.isEmpty, !replyText.isEmpty else {
                completionHandler()
                return
            }
            Task { @MainActor in
                _ = await store?.sendMessage(text: replyText, attachments: [], to: chatID)
            }
        } else if !chatID.isEmpty {
            Task { @MainActor in
                store?.selectedChatID = chatID
            }
        }

        completionHandler()
    }
}
