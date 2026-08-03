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
                            .foregroundStyle(.tint)
                            .background(.background, in: .circle)
                            .accessibilityLabel("Unread")
                    }
                }

                VStack(alignment: .leading) {
                    Text(chat.title)
                        .bold()
                        .lineLimit(1)

                    if let lastActivity = chat.lastActivity {
                        if Calendar.current.isDateInToday(lastActivity) {
                            Text(lastActivity, format: .dateTime.hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(lastActivity, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text(chat.preview)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}
