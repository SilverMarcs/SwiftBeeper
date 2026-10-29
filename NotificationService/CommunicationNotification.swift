import Foundation
@preconcurrency import Intents
@preconcurrency import UserNotifications

/// Presents a decrypted push as a communication notification, with the
/// sender's avatar and the group name, by donating a message intent.
enum CommunicationNotification {
    nonisolated static func content(from content: UNNotificationContent,
                                    preview: NotificationPreview) async -> UNNotificationContent {
        guard let conversationID = content.userInfo["chatID"] as? String else { return content }
        let avatar = preview.avatar.flatMap(INImage.init(imageData:))
        let groupImage = preview.isGroup ? avatar ?? NotificationAppIcon.image() : nil
        // Incomplete group metadata must fall back to the prepared group title
        // and Relay icon, rather than donating an apparent direct message.
        if preview.isGroup && ((preview.recipients ?? []).isEmpty || groupImage == nil) {
            return content
        }
        #if os(macOS)
        let senderImage = preview.isGroup ? groupImage : avatar
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
        if preview.isGroup, let groupImage {
            intent.setImage(groupImage, forParameterNamed: \.speakableGroupName)
        }
        #endif
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        do {
            try await interaction.donate()
            guard let updated = try content.updating(from: intent).mutableCopy() as? UNMutableNotificationContent else { return content }
            // Keep Relay's title / sender / body layout over the intent's.
            updated.title = preview.title
            updated.subtitle = preview.subtitle
            updated.body = preview.body
            updated.threadIdentifier = conversationID
            updated.categoryIdentifier = content.categoryIdentifier
            updated.userInfo = content.userInfo
            return updated
        } catch {
            return content
        }
    }
}
