import Foundation
import UserNotifications
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The client half of Relay's single notification path.
///
/// Every alert Relay shows on every platform originates as an APNs push sent by
/// the server (`internal/server/push.go`). The client never synthesises a
/// notification from the live WebSocket stream — the app being connected is
/// exactly the case where a locally-generated alert would double up with the
/// push. This type therefore only ever: registers the device with APNs, keeps
/// that registration in sync with the signed-in server, decides whether an
/// arriving push should be shown while the app is in the foreground, and
/// handles taps and inline replies.
@MainActor
@Observable
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let messageCategory = "MESSAGE"
    nonisolated private static let replyAction = "REPLY_ACTION"

    #if os(macOS)
    nonisolated private static let platform = "macos"
    #else
    nonisolated private static let platform = "ios"
    #endif

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Relay", category: "NotificationService")
    private(set) var isAuthorized = false
    weak var store: ChatStore?
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
                // Apple recommends asking APNs for the current token on every
                // launch rather than treating a saved value as permanent.
                #if os(macOS)
                NSApplication.shared.registerForRemoteNotifications()
                #else
                UIApplication.shared.registerForRemoteNotifications()
                #endif
            }
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription, privacy: .public)")
        }
    }

    func didRegisterForRemoteNotifications(_ data: Data) {
        deviceToken = data.map { byte in
            let value = String(byte, radix: 16)
            return value.count == 1 ? "0\(value)" : value
        }.joined()
        Task { await syncRemoteRegistration() }
    }

    func didFailToRegisterForRemoteNotifications(_ error: Error) {
        logger.error("APNs registration failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Points the current APNs token at the currently signed-in server. Safe to
    /// call repeatedly; the server keys registrations by token.
    func syncRemoteRegistration() async {
        guard isAuthorized,
              let deviceToken,
              sessionStore?.accessToken.isEmpty == false else { return }

        do {
            try await APIClient.registerPushDevice(token: deviceToken, platform: Self.platform)
            logger.info("Registered this device for push notifications")
        } catch {
            logger.error("Could not register push device: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Detaches this device from the server it is currently registered with.
    /// Call before switching servers or signing out, while the old access token
    /// is still valid.
    func unregisterRemoteRegistration() async {
        guard let deviceToken, sessionStore?.accessToken.isEmpty == false else { return }

        do {
            try await APIClient.unregisterPushDevice(token: deviceToken)
        } catch {
            logger.error("Could not unregister push device: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Removes every delivered notification for a conversation once that
    /// conversation is being viewed or has explicitly been marked as read.
    func clearDeliveredNotifications(for chatID: String) {
        Self.clearDeliveredNotifications(for: chatID)
    }

    nonisolated private static func clearDeliveredNotifications(for chatID: String) {
        guard !chatID.isEmpty else { return }

        let center = UNUserNotificationCenter.current()
        center.getDeliveredNotifications { notifications in
            let identifiers = notifications.compactMap { notification in
                let content = notification.request.content
                let notificationChatID = content.userInfo["chatID"] as? String
                    ?? content.threadIdentifier
                return notificationChatID == chatID
                    ? notification.request.identifier
                    : nil
            }
            guard !identifiers.isEmpty else { return }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
        }
    }

    /// The server pushes to every registered device unconditionally — it has no
    /// reliable view of which one you are looking at. Suppression is a client
    /// decision, made here: stay quiet only for the conversation that is open
    /// on screen right now, and alert for everything else even in the
    /// foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let content = notification.request.content
        let chatID = content.userInfo["chatID"] as? String ?? content.threadIdentifier

        Task { @MainActor [weak self] in
            if !chatID.isEmpty, self?.store?.selectedChatID == chatID {
                self?.clearDeliveredNotifications(for: chatID)
                completionHandler([])
            } else {
                completionHandler([.banner, .sound])
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let chatID = content.userInfo["chatID"] as? String
            ?? content.threadIdentifier

        Self.clearDeliveredNotifications(for: chatID)

        if response.actionIdentifier == Self.replyAction,
           let textResponse = response as? UNTextInputNotificationResponse {
            let replyText = textResponse.userText
            guard !chatID.isEmpty, !replyText.isEmpty else {
                completionHandler()
                return
            }
            Task { @MainActor in
                _ = store?.sendMessage(text: replyText, attachments: [], to: chatID)
            }
        } else if !chatID.isEmpty {
            Task { @MainActor in
                store?.selectedChatID = chatID
            }
        }

        completionHandler()
    }
}
