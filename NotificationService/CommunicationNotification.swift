import Foundation
@preconcurrency import Intents
@preconcurrency import UserNotifications

/// Restore the native communication presentation used before the Matrix move.
enum CommunicationNotification {
    nonisolated static func content(from content: UNNotificationContent,
                                    preview: NotificationPreview) async -> UNNotificationContent {
        guard let conversationID = content.userInfo["chatID"] as? String else { return content }
        let avatar = preview.avatar.flatMap(INImage.init(imageData:))
        #if os(macOS)
        let senderImage = avatar
        #else
        let senderImage = preview.isGroup ? nil : avatar
        #endif
        let sender = INPerson(
            personHandle: INPersonHandle(value: preview.senderID, type: .unknown),
            nameComponents: nil, displayName: preview.senderName, image: senderImage,
            contactIdentifier: nil, customIdentifier: preview.senderID)
        let recipients = preview.isGroup ? (preview.recipients ?? []).map { participant in
            INPerson(personHandle: INPersonHandle(value: participant.id, type: .unknown),
                     nameComponents: nil, displayName: participant.name, image: nil,
                     contactIdentifier: nil, customIdentifier: participant.id)
        } : nil
        let intent = INSendMessageIntent(
            recipients: recipients, outgoingMessageType: .outgoingMessageText,
            content: preview.body,
            speakableGroupName: preview.isGroup ? INSpeakableString(spokenPhrase: preview.title) : nil,
            conversationIdentifier: conversationID, serviceName: "Relay",
            sender: sender, attachments: nil)
        #if !os(macOS)
        if preview.isGroup, let avatar {
            intent.setImage(avatar, forParameterNamed: \.speakableGroupName)
        }
        #endif
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        do {
            try await interaction.donate()
            guard let updated = try content.updating(from: intent).mutableCopy() as? UNMutableNotificationContent else { return content }
            // Keep the previous app's group title / sender / message layout.
            updated.title = preview.title
            updated.subtitle = preview.isGroup ? preview.senderName : ""
            updated.body = preview.body
            updated.threadIdentifier = conversationID
            return updated
        } catch {
            return content
        }
    }
}
