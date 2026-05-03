import SwiftUI

struct ChatRowView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(MessageStore.self) private var messageStore

    let chat: Chat

    /// Prefer the latest locally-known message (including reactions and deletions)
    /// over the server's `preview`, which lags realtime and excludes reactions.
    private var subtitleText: String? {
        let serverPreview = chat.preview
        let localLatest = messageStore.latestKnownMessage(for: chat.id)
        switch (serverPreview, localLatest) {
        case (nil, nil): return nil
        case (let preview?, nil): return preview.displayText
        case (nil, let latest?): return latest.displayText
        case (let preview?, let latest?):
            return latest.numericSortKey >= preview.numericSortKey ? latest.displayText : preview.displayText
        }
    }

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
                    if let previewText = subtitleText {
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
                            .background(chat.isMuted == true ? AnyShapeStyle(.background.secondary) : AnyShapeStyle(Color.accentColor), in: Capsule())
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

            Button {
                Task {
                    if chat.isMuted == true {
                        await chatStore.unmuteChat(chat.id)
                    } else {
                        await chatStore.muteChat(chat.id)
                    }
                }
            } label: {
                Label(
                    chat.isMuted == true ? "Unmute" : "Mute",
                    systemImage: chat.isMuted == true ? "bell" : "bell.slash"
                )
                .labelStyle(.iconOnly)
            }
            .tint(.purple)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if chat.unreadCount > 0 {
                Button {
                    Task {
                        await chatStore.markChatAsRead(chat.id)
                    }
                } label: {
                    Label("Mark Read", systemImage: "envelope.open")
                        .labelStyle(.iconOnly)
                }
                .tint(.blue)
            }
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
            type: .single,
            isPinned: nil,
            isArchived: nil,
            accountID: nil,
            lastActivity: .now.addingTimeInterval(-3600),
            lastReadMessageSortKey: nil,
            imgURL: nil
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
            type: .group,
            isPinned: true,
            isArchived: nil,
            accountID: nil,
            lastActivity: .now.addingTimeInterval(-86400),
            lastReadMessageSortKey: nil,
            imgURL: nil
        ))
    }
    .environment(ChatStore())
    .environment(MessageStore())
    .environment(SessionStore())
}
