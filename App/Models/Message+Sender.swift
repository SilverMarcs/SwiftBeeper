import Foundation

extension Message {
    /// The profile the message carries for its sender, or their ID and name
    /// when the core found no member event for them.
    var senderProfile: ChatParticipant {
        sender ?? ChatParticipant(id: senderID, username: nil, fullName: senderDisplayName, imgURL: nil, isSelf: isSender)
    }

    /// The sender's profile: the chat's loaded participant when the sample
    /// has them, otherwise the profile the message carries. Read receipts
    /// and reactions resolve people by the same rule.
    func senderParticipant(in chat: Chat) -> ChatParticipant {
        chat.participant(with: senderID) ?? senderProfile
    }
}
