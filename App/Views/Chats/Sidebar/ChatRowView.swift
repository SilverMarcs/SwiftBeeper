import SwiftUI

/// A chat's avatar, title, last activity, preview, and unread badge, with its
/// swipe and context-menu actions.
struct ChatRowView: View {
    let chat: Chat
    /// The logo badging the avatar; nil shows the plain avatar.
    let networkImageURL: String?

    var body: some View {
        HStack(spacing: Self.avatarSpacing) {
            #if os(macOS)
            NetworkBadgedAvatarView(chat: chat, dimension: 43, networkImageURL: networkImageURL)
            #else
            NetworkBadgedAvatarView(chat: chat, dimension: 48, networkImageURL: networkImageURL)
            #endif

            // Name and preview sit line to line, as in Messages.
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(chat.displayTitle)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if chat.isPinned == true {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Pinned")
                    }

                    Spacer()

                    if let timeText = chat.lastActivityText {
                        Text(timeText)
                            #if os(macOS)
                            .font(.callout)
                            #else
                            .font(.subheadline)
                            #endif
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    // Typing shows its bubble over these reserved lines, so
                    // the row never changes height for it.
                    ChatRowPreview(chat: chat)
                        #if os(iOS)
                        .font(.subheadline)
                        #else
                        .font(.body)
                        #endif
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)

                    Spacer()

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
            }
        }
        #if os(macOS)
        .padding(.horizontal, 5)
        .padding(.vertical, 12)
        #else
        .padding(-1)
        #endif
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

    #if os(macOS)
    private static let avatarSpacing: CGFloat = 8
    #else
    private static let avatarSpacing: CGFloat = 12
    #endif
}
