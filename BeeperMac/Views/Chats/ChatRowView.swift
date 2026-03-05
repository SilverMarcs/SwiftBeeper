import SwiftUI

struct ChatRowView: View {
    @Environment(ChatStore.self) private var chatStore

    let chat: Chat

    var body: some View {
        HStack {
            ProfileAvatarView(name: avatarName, imageURLString: avatarImageURL, dimension: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(chat.displayTitle)
                    .font(.headline)
                    .fontWeight(chat.unreadCount > 0 ? .bold : .regular)

                if let previewText = chat.previewText {
                    Text(previewText)
                        .font(.subheadline)
                        .foregroundStyle(chat.unreadCount > 0 ? .primary : .secondary)
                        .fontWeight(chat.unreadCount > 0 ? .medium : .regular)
                        .lineLimit(1)
                }
            }

            Spacer()

            if chat.unreadCount > 0 {
                Text(chat.unreadCount > 99 ? "99+" : "\(chat.unreadCount)")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
            }
        }
        .padding(3)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                Task {
                    if chatStore.selectedInboxFilter == .archive {
                        await chatStore.unarchiveChat(chat.id)
                    } else {
                        await chatStore.archiveChat(chat.id)
                    }
                }
            } label: {
                Label(
                    chatStore.selectedInboxFilter == .archive ? "Unarchive" : "Archive",
                    systemImage: chatStore.selectedInboxFilter == .archive ? "tray.and.arrow.up" : "archivebox"
                )
                .labelStyle(.iconOnly)
            }
            .tint(chatStore.selectedInboxFilter == .archive ? .blue : .orange)
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
    VStack {
        ChatRowView(chat: Chat(
            id: "chat-2",
            title: "Alice",
            unreadCount: 3,
            participants: nil,
            preview: Message(
                id: "message-2",
                chatID: "chat-2",
                senderID: "alice",
                senderName: "Alice",
                timestamp: .now,
                sortKey: "2",
                text: "Are you free tomorrow?",
                isSender: false,
                attachments: nil,
                reactions: nil,
                linkedMessageID: nil
            )
        ))

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
            isSender: false,
            attachments: nil,
            reactions: nil,
            linkedMessageID: nil
        )
        ))
    }
    .environment(ChatStore())
    .environment(SessionStore())
}
