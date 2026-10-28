import SwiftUI

/// A chat's avatar, title, last activity, preview, and unread badge, with its
/// swipe and context-menu actions.
struct ChatRowView: View {
    let chat: Chat

    var body: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            ChatAvatarView(chat: chat, dimension: 43)
            #else
            ChatAvatarView(chat: chat, dimension: 48)
            #endif

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.displayTitle)
                        .font(.body)
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    if let previewText = chat.previewText {
                        Text(previewText)
                            #if os(iOS)
                            .font(.callout)
                            #else
                            .font(.body)
                            #endif
                            .foregroundStyle(.secondary)
                            .lineLimit(2, reservesSpace: true)
                    }

                    Spacer()

                    if chat.unreadCount > 0 {
                        let isMuted = chat.isMuted == true
                        Text(chat.unreadCount > 99 ? "99+" : "\(chat.unreadCount)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(isMuted ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(isMuted ? Color.secondary.opacity(0.25) : .accentColor, in: .capsule)
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
        .padding(5)
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
    }
}
