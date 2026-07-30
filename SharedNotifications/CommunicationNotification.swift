#if os(iOS)
import Foundation
@preconcurrency import Intents
@preconcurrency import UserNotifications

struct CommunicationNotificationInfo: Sendable {
    static let maximumRecipientCount = 8

    let conversationID: String
    let senderID: String
    let senderName: String
    let chatTitle: String
    let isGroupChat: Bool
    let messageBody: String
    let recipients: [CommunicationNotificationParticipant]

    init(
        conversationID: String,
        senderID: String,
        senderName: String,
        chatTitle: String,
        isGroupChat: Bool,
        messageBody: String,
        recipients: [CommunicationNotificationParticipant] = []
    ) {
        self.conversationID = conversationID
        self.senderID = senderID
        self.senderName = senderName
        self.chatTitle = chatTitle
        self.isGroupChat = isGroupChat
        self.messageBody = messageBody
        self.recipients = Array(recipients.prefix(Self.maximumRecipientCount))
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
        let participantPayloads = userInfo["groupParticipants"] as? [[String: Any]] ?? []
        recipients = Array(
            participantPayloads
                .compactMap { CommunicationNotificationParticipant(userInfo: $0) }
                .prefix(Self.maximumRecipientCount)
        )
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
        let recipients: [INPerson]? = information.isGroupChat
            ? information.recipients.map { participant in
                INPerson(
                    personHandle: INPersonHandle(value: participant.id, type: .unknown),
                    nameComponents: nil,
                    displayName: participant.name,
                    image: nil,
                    contactIdentifier: nil,
                    customIdentifier: participant.id
                )
            }
            : nil
        let intent = INSendMessageIntent(
            recipients: recipients,
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
            let updatedContent = try content.updating(from: intent)
            return preservingMessagePresentation(updatedContent, information: information)
        } catch {
            return content
        }
    }

    nonisolated private static func preservingMessagePresentation(
        _ content: UNNotificationContent,
        information: CommunicationNotificationInfo
    ) -> UNNotificationContent {
        guard let mutableContent = content.mutableCopy() as? UNMutableNotificationContent else {
            return content
        }
        mutableContent.title = information.isGroupChat
            ? information.chatTitle
            : information.senderName
        mutableContent.subtitle = information.isGroupChat
            ? information.senderName
            : ""
        mutableContent.body = information.messageBody
        mutableContent.threadIdentifier = information.conversationID
        return mutableContent
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
