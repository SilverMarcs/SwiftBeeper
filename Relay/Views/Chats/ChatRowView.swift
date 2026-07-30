import SwiftUI

struct ChatRowView: View {
    @Environment(\.appearsActive) private var appearsActive

    let chat: Chat

    var body: some View {
        HStack(spacing: 8) {
            ChatAvatarView(chat: chat, dimension: 42)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.displayTitle)
                        .font(.body)
                        .fontWeight(chat.unreadCount > 0 ? .bold : .regular)
                        .foregroundStyle(.primary)
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
                            .foregroundStyle(.secondary)
                            .fontWeight(chat.unreadCount > 0 ? .medium : .regular)
                            .lineLimit(1)
                    }

                    Spacer()

                    if chat.unreadCount > 0 {
                        Text(chat.unreadCount > 99 ? "99+" : "\(chat.unreadCount)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(chat.isMuted == true ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(chat.isMuted == true ? AnyShapeStyle(Color.secondary.opacity(0.25)) : AnyShapeStyle(Color.accentColor), in: Capsule())
                    }
                }
            }
        }
        .padding(3)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            ChatRowActionsView(
                chat: chat,
                includesReadAction: false,
                includesArchiveAndMuteActions: true
            )
            .labelStyle(.iconOnly)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            ChatRowActionsView(
                chat: chat,
                includesReadAction: true,
                includesArchiveAndMuteActions: false
            )
            .labelStyle(.iconOnly)
        }
        .contextMenu {
            ChatRowActionsView(
                chat: chat,
                includesReadAction: true,
                includesArchiveAndMuteActions: true
            )
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
    .environment(SessionStore())
}
