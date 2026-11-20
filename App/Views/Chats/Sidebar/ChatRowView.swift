import SwiftUI

/// A chat's avatar, title, last activity, preview, and unread badge, with its
/// swipe and context-menu actions.
struct ChatRowView: View {
    let chat: Chat
    /// The logo badging the avatar; nil shows the plain avatar.
    let networkImageURL: String?

    var body: some View {
        ChatRowLayout(
            chat: chat,
            networkImageURL: networkImageURL,
            title: chat.displayTitle,
            isPinned: chat.isPinned == true,
            timeText: chat.lastActivityText
        ) {
            // Typing shows its bubble over these reserved lines, so the row
            // never changes height for it.
            ChatRowPreview(chat: chat)
        } badges: {
            if chat.hasUnreadMention == true {
                ChatMentionBadgeView()
            }

            if chat.unreadCount > 0 {
                ChatUnreadCountBadge(count: chat.unreadCount, isMuted: chat.isMuted == true)
            } else if chat.isMarkedUnread == true {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(chat.isMuted == true ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tint))
                    .accessibilityLabel("Unread")
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            ChatRowActionsView(chat: chat, placement: .trailingSwipe)
                .labelStyle(.iconOnly)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            ChatRowActionsView(chat: chat, placement: .leadingSwipe)
                .labelStyle(.iconOnly)
        }
        .contextMenu {
            ChatRowActionsView(chat: chat, placement: .contextMenu)
        }
        .menuOrder(.fixed)
    }
}
