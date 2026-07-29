#if os(iOS)
import Foundation
@preconcurrency import Intents
@preconcurrency import UserNotifications

struct CommunicationNotificationInfo: Sendable {
    let conversationID: String
    let senderID: String
    let senderName: String
    let chatTitle: String
    let isGroupChat: Bool
    let messageBody: String

    init(
        conversationID: String,
        senderID: String,
        senderName: String,
        chatTitle: String,
        isGroupChat: Bool,
        messageBody: String
    ) {
        self.conversationID = conversationID
        self.senderID = senderID
        self.senderName = senderName
        self.chatTitle = chatTitle
        self.isGroupChat = isGroupChat
        self.messageBody = messageBody
    }

    init?(userInfo: [AnyHashable: Any], fallbackBody: String) {
        guard
            let conversationID = userInfo["chatID"] as? String,
            let senderID = userInfo["senderID"] as? String,
            let senderName = userInfo["senderName"] as? String
        else {
            return nil
        }

        self.conversationID = conversationID
        self.senderID = senderID
        self.senderName = senderName
        chatTitle = userInfo["chatTitle"] as? String ?? senderName
        isGroupChat = userInfo["isGroupChat"] as? Bool ?? false
        messageBody = fallbackBody
    }
}

enum CommunicationNotification {
    nonisolated static func updatedContent(
        from content: UNNotificationContent,
        information: CommunicationNotificationInfo,
        avatarData: Data?
    ) async -> UNNotificationContent {
        let avatar = avatarData.flatMap(INImage.init(imageData:))
        let sender = INPerson(
            personHandle: INPersonHandle(value: information.senderID, type: .unknown),
            nameComponents: nil,
            displayName: information.senderName,
            image: information.isGroupChat ? nil : avatar,
            contactIdentifier: nil,
            customIdentifier: information.senderID
        )
        let groupName = information.isGroupChat
            ? INSpeakableString(spokenPhrase: information.chatTitle)
            : nil
        let intent = INSendMessageIntent(
            recipients: nil,
            outgoingMessageType: .outgoingMessageText,
            content: information.messageBody,
            speakableGroupName: groupName,
            conversationIdentifier: information.conversationID,
            serviceName: "Relay",
            sender: sender,
            attachments: nil
        )

        if information.isGroupChat, let avatar {
            intent.setImage(avatar, forParameterNamed: \.speakableGroupName)
        }

        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming

        do {
            try await interaction.donate()
            return try content.updating(from: intent)
        } catch {
            return content
        }
    }
}

enum NotificationAvatarLoader {
    nonisolated private static let maximumBytes = 2 * 1_024 * 1_024

    nonisolated static func data(from url: URL?) async -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 4)
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        return await data(for: request)
    }

    nonisolated static func data(for request: URLRequest?) async -> Data? {
        guard var request else { return nil }
        request.timeoutInterval = min(request.timeoutInterval, 4)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard
                let response = response as? HTTPURLResponse,
                (200 ... 299).contains(response.statusCode),
                data.count <= maximumBytes
            else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }
}
#endif
