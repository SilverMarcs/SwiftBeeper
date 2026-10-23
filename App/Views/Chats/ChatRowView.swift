import SwiftUI

struct ChatRowView: View {
    @Environment(\.appearsActive) private var appearsActive

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
                        // .fontWeight(chat.unreadCount > 0 ? .bold : .regular)
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
                            #if os(iOS)
                            .font(.callout)
                            #else
                            .font(.body)
                            #endif
                            .foregroundStyle(.secondary)
                            // .fontWeight(chat.unreadCount > 0 ? .medium : .regular)
                            .lineLimit(2, reservesSpace: true)
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
        #if os(macOS)
        .padding(5)
        #else
        .padding(-1)
        #endif
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

