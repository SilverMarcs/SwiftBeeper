import Foundation
@preconcurrency import Intents

/// Tells the system the user messaged a chat. iOS ranks the share sheet's
/// suggested conversations from these and from the incoming messages the
/// notification extension donates, and hands the chat ID back to the share
/// extension when one is picked. It's one call per sent message; the system
/// does the rest.
nonisolated enum SentMessageDonation {
    /// - Parameters:
    ///   - photo: The chat's Matrix avatar source, as its avatar shows it.
    ///   - recipients: Everyone but the user, as far as the chat lists them.
    static func donate(
        chatID: String,
        title: String,
        isGroup: Bool,
        photo: String?,
        recipients: [(id: String, name: String)]
    ) async {
        let imageData = await ConversationImage.make(photo: photo)
        let image = imageData.map(INImage.init(imageData:))
        var people = recipients.map { recipient in
            person(id: recipient.id, name: recipient.name, image: isGroup ? nil : image)
        }
        // iOS treats a conversation as a group only with more than one
        // recipient; the chat stands in for members it doesn't list.
        if people.isEmpty || (isGroup && people.count < 2) {
            people.append(person(id: chatID, name: title, image: isGroup ? nil : image))
        }
        let intent = INSendMessageIntent(
            recipients: people, outgoingMessageType: .outgoingMessageText, content: nil,
            speakableGroupName: isGroup ? INSpeakableString(spokenPhrase: title) : nil,
            conversationIdentifier: chatID, serviceName: "Relay", sender: nil, attachments: nil)
        #if !os(macOS)
        if isGroup, let image {
            intent.setImage(image, forParameterNamed: \.speakableGroupName)
        }
        #endif
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .outgoing
        try? await interaction.donate()
    }

    private static func person(id: String, name: String, image: INImage?) -> INPerson {
        INPerson(personHandle: INPersonHandle(value: id, type: .unknown),
                 nameComponents: nil, displayName: name, image: image,
                 contactIdentifier: nil, customIdentifier: id)
    }
}
