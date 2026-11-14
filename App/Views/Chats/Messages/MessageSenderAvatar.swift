import SwiftUI

/// The same sender avatar in its timeline row and while moving to a focused reply.
struct MessageSenderAvatar: View {
    let message: Message
    let chat: Chat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProfileAvatarView(
                name: message.senderDisplayName,
                colorID: message.senderID,
                imageURLString: chat.participant(with: message.senderID)?.imgURL,
                dimension: 28
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(message.senderDisplayName)’s profile")
    }
}
