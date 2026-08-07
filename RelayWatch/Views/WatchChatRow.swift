import SwiftUI

struct WatchChatRow: View {
    let chat: WatchChatSummary

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                WatchChatAvatarView(
                    title: chat.title,
                    imageURL: chat.avatarURL,
                    dimension: 40
                )
                .overlay(alignment: .bottomLeading) {
                    if chat.unreadCount > 0 {
                        Image(systemName: "circle.fill")
                            .font(.footnote)
                            .foregroundStyle(
                                chat.isMuted == true
                                    ? AnyShapeStyle(.secondary)
                                    : AnyShapeStyle(.tint)
                            )
                            .background(.background, in: .circle)
                            .accessibilityLabel(chat.isMuted == true ? "Unread, muted" : "Unread")
                    }
                }

                VStack(alignment: .leading) {
                    Text(chat.title)
                        .bold()
                        .lineLimit(1)

                    if let lastActivityText = chat.lastActivityText {
                        Text(lastActivityText)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Text(chat.preview)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
