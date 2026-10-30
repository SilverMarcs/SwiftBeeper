import Foundation
@preconcurrency import Intents

/// Tells the system the user messaged a chat. iOS ranks the share sheet's
/// suggested conversations from these and from the incoming messages the
/// notification extension donates, and hands the chat ID back to the share
/// extension when one is picked. It's one call per sent message; the system
/// does the rest.
nonisolated enum SentMessageDonation {
    static func donate(
        chatID: String,
        title: String,
        isGroup: Bool,
        recipients: [(id: String, name: String)],
        imageData: Data?
    ) async {
        let image = imageData.map(INImage.init(imageData:))
        let people = recipients.map { recipient in
            INPerson(personHandle: INPersonHandle(value: recipient.id, type: .unknown),
                     nameComponents: nil, displayName: recipient.name, image: isGroup ? nil : image,
                     contactIdentifier: nil, customIdentifier: recipient.id)
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
}
