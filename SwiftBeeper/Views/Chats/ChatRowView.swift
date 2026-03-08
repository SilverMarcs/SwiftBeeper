import SwiftUI

struct ChatRowView: View {
    @Environment(ChatStore.self) private var chatStore

    let chat: Chat

    var body: some View {
        HStack(spacing: 8) {
            ChatAvatarView(chat: chat, dimension: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.displayTitle)
                        .font(.body)
                        .fontWeight(chat.unreadCount > 0 ? .bold : .regular)
                        .lineLimit(1)

                    Spacer()

                    if let timeText = chat.lastActivityText {
                        Text(timeText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if let previewText = chat.previewText {
                        Text(previewText)
                            .font(.body)
                            .foregroundStyle(chat.unreadCount > 0 ? .primary : .secondary)
                            .fontWeight(chat.unreadCount > 0 ? .medium : .regular)
                            .lineLimit(1)
                    }

                    Spacer()

                    if chat.unreadCount > 0 {
                        Text(chat.unreadCount > 99 ? "99+" : "\(chat.unreadCount)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(chat.isMuted == true ? Color.secondary : Color.accentColor, in: Capsule())
                    }
                }
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
                type: nil,
                text: "Are you free tomorrow?",
                isSender: false,
                attachments: nil,
                isUnread: nil,
                reactions: nil,
                linkedMessageID: nil
            ),
            isMuted: false,
            type: "single",
            isPinned: nil,
            isArchived: nil,
            accountID: nil,
            lastActivity: .now.addingTimeInterval(-3600),
            lastReadMessageSortKey: nil
        ))

        ChatRowView(chat: Chat(
            id: "chat-1",
            title: "General",
            unreadCount: 5,
            participants: nil,
            preview: Message(
                id: "message-1",
                chatID: "chat-1",
                senderID: "alice",
                senderName: "Alice",
                timestamp: .now,
                sortKey: "1",
                type: nil,
                text: "Hey",
                isSender: false,
                attachments: nil,
                isUnread: nil,
                reactions: nil,
                linkedMessageID: nil
            ),
            isMuted: true,
            type: "group",
            isPinned: true,
            isArchived: nil,
            accountID: nil,
            lastActivity: .now.addingTimeInterval(-86400),
            lastReadMessageSortKey: nil
        ))
    }
    .environment(ChatStore())
    .environment(SessionStore())
}
