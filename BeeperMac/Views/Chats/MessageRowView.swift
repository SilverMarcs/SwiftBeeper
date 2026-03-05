import SwiftUI

struct MessageRowView: View {
    let message: Message
    let chat: Chat

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

    private var currentParticipant: ChatParticipant? {
        chat.participants?.items.first(where: { $0.isSelf == true })
    }

    private var showIncomingIdentity: Bool {
        guard let participantCount = chat.participants?.items.count else {
            return true
        }

        return participantCount != 2
    }

    private var senderAvatarImageURL: String? {
        chat.participant(with: message.senderID)?.imgURL
    }

    private var isOutgoing: Bool {
        if let isSender = message.isSender {
            return isSender
        }

        if let currentParticipant {
            return message.senderID == currentParticipant.id
        }

        return false
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
        ), chat: Chat(
            id: "chat-1",
            title: "General",
            unreadCount: 0,
            participants: nil,
            preview: nil
        ))

        MessageRowView(message: Message(
            id: "msg-2",
            chatID: "chat-1",
            senderID: "@me",
            senderName: "Me",
            timestamp: .now,
            sortKey: "2",
            text: "Hey!",
            isSender: true
        ), chat: Chat(
            id: "chat-1",
            title: "General",
            unreadCount: 0,
            participants: nil,
            preview: nil
        ))
    }
    .padding()
}
