import SwiftUI

/// A group shared with the person: its avatar, name and size.
struct ChatCommonGroupRow: View {
    let chat: Chat

    var body: some View {
        HStack(spacing: 10) {
            ChatAvatarView(chat: chat, dimension: 32)

            VStack(alignment: .leading) {
                Text(chat.displayTitle)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let memberCount = chat.participants?.total, memberCount > 0 {
                    Text("^[\(memberCount) member](inflect: true)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .contentShape(.rect)
    }
}
