import SwiftUI

struct MessageRowView: View {
    let message: Message
    let isOutgoing: Bool
    let senderAvatarImageURL: String?
    let showIncomingIdentity: Bool

    var body: some View {
        HStack(alignment: .bottom) {
            if isOutgoing {
                Spacer(minLength: 0)
            } else if showIncomingIdentity {
                ProfileAvatarView(name: message.senderDisplayName, imageURLString: senderAvatarImageURL, dimension: 28)
            }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 6) {
                if isOutgoing == false && showIncomingIdentity {
                    Text(message.senderDisplayName)
                        .font(.subheadline)
                        .bold()
                }

                Text(message.displayText)
                    .font(.body)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isOutgoing ? Color.accentColor.opacity(0.20) : Color.gray.opacity(0.15))
                    .clipShape(.rect(cornerRadius: 12))
            }

            if isOutgoing == false {
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    VStack {
        MessageRowView(message: Message(
            id: "msg-1",
            chatID: "chat-1",
            senderID: "@alice",
            senderName: "Alice",
            timestamp: .now,
            sortKey: "1",
            text: "Hello",
            isSender: false
        ), isOutgoing: false, senderAvatarImageURL: nil, showIncomingIdentity: true)

        MessageRowView(message: Message(
            id: "msg-2",
            chatID: "chat-1",
            senderID: "@me",
            senderName: "Me",
            timestamp: .now,
            sortKey: "2",
            text: "Hey!",
            isSender: true
        ), isOutgoing: true, senderAvatarImageURL: nil, showIncomingIdentity: true)
    }
    .padding()
}
