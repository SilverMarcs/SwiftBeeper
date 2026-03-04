import SwiftUI

struct ChatRowView: View {
    let chat: Chat

    var body: some View {
        HStack {
            ProfileAvatarView(name: avatarName, imageURLString: avatarImageURL, dimension: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(chat.displayTitle)
                    .font(.headline)

                if let previewText = chat.previewText {
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var avatarName: String {
        if let otherParticipant = chat.otherParticipant {
            return otherParticipant.displayName
        }

        if let senderName = chat.preview?.senderName,
           senderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return senderName
        }
        return chat.displayTitle
    }

    private var avatarImageURL: String? {
        chat.otherParticipant?.imgURL
    }
}

#Preview {
    ChatRowView(chat: Chat(
        id: "chat-1",
        title: "General",
        unreadCount: 0,
        participants: nil,
        preview: Message(
            id: "message-1",
            chatID: "chat-1",
            senderID: "alice",
            senderName: "Alice",
            timestamp: .now,
            sortKey: "1",
            text: "Hey",
            isSender: false
        )
    ))
}
