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
    weak var sessionStore: SessionStore?
    #if os(iOS)
    private var deviceToken: String?
    #endif

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
            #if os(iOS)
            #if REMOTE_ONLY
            if granted {
                registerForRemoteNotifications()
            }
            #endif
            #else
            // macOS notifications are generated locally from the live event
            // stream. Ensure an APNs token from an older build is invalidated.
            NSApplication.shared.unregisterForRemoteNotifications()
            #endif
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription, privacy: .public)")
        }
    }

    #if os(iOS)
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
    #endif

    func syncRemoteRegistration() async {
        #if os(iOS) && REMOTE_ONLY
        guard isAuthorized,
              let deviceToken,
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
        #else
        prefersRemoteNotifications = false
        #endif
    }

    func unregisterRemoteRegistration() async {
        #if os(iOS)
        #if REMOTE_ONLY
        guard let deviceToken,
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
        #else
        prefersRemoteNotifications = false
        #endif
        #else
        NSApplication.shared.unregisterForRemoteNotifications()
        prefersRemoteNotifications = false
        #endif
    }

    #if os(iOS)
    private func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
    #endif

    func postNewMessageNotification(message: Message, chat: Chat) {
        guard isAuthorized else { return }

        Task {
            let mutableContent = UNMutableNotificationContent()
            mutableContent.title = chat.isGroupChat ? chat.displayTitle : message.senderDisplayName
            mutableContent.subtitle = chat.isGroupChat ? message.senderDisplayName : ""
            mutableContent.body = message.displayText
            mutableContent.sound = .default
            mutableContent.threadIdentifier = message.chatID
            mutableContent.categoryIdentifier = Self.messageCategory
            mutableContent.userInfo = ["chatID": message.chatID, "messageID": message.id]

            let content: UNNotificationContent
            #if os(iOS)
            let avatarURLString: String?
            if chat.isGroupChat {
                avatarURLString = chat.imgURL
            } else {
                avatarURLString = chat.participant(with: message.senderID)?.imgURL
                    ?? chat.otherParticipant?.imgURL
            }
            let avatarRequest = avatarURLString.flatMap(AuthenticatedImageLoader.buildRequest(for:))
            let avatarData = await NotificationAvatarLoader.data(for: avatarRequest)
            let information = CommunicationNotificationInfo(
                conversationID: message.chatID,
                senderID: message.senderID,
                senderName: message.senderDisplayName,
                chatTitle: chat.displayTitle,
                isGroupChat: chat.isGroupChat,
                messageBody: message.displayText,
                recipients: chat.isGroupChat
                    ? (chat.participants?.items ?? [])
                        .filter { $0.isSelf != true && $0.id != message.senderID }
                        .map {
                            CommunicationNotificationParticipant(
                                id: $0.id,
                                name: $0.displayName
                            )
                        }
                    : []
            )
            content = await CommunicationNotification.updatedContent(
                from: mutableContent,
                information: information,
                avatarData: avatarData
            )
            #else
            content = mutableContent
            #endif

            let request = UNNotificationRequest(
                identifier: "msg-\(message.id)",
                content: content,
                trigger: nil
            )
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                logger.error("Failed to post notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Removes every delivered notification for a conversation once that
    /// conversation is being viewed or has explicitly been marked as read.
    func clearDeliveredNotifications(for chatID: String) {
        Self.clearDeliveredNotifications(for: chatID, in: .current())
    }

    nonisolated private static func clearDeliveredNotifications(
        for chatID: String,
        in center: UNUserNotificationCenter
    ) {
        guard !chatID.isEmpty else { return }

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
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
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
        let content = response.notification.request.content
        let chatID = content.userInfo["chatID"] as? String
            ?? content.threadIdentifier

        Self.clearDeliveredNotifications(for: chatID, in: center)

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
