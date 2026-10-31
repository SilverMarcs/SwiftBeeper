import SwiftUI

/// The Mac toolbar's chat title: avatar, name, and member count, styled like a
/// window title and subtitle. The whole thing opens chat info.
struct ChatTitleButton: View {
    let chat: Chat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                ChatAvatarView(chat: chat, dimension: 28)

                VStack(alignment: .leading, spacing: 0) {
                    Text(chat.displayTitle)
                        .font(.headline)
                        .lineLimit(1)

                    if memberCount > 0 {
                        Text("^[\(memberCount) member](inflect: true)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows chat info")
    }

    private var memberCount: Int {
        guard chat.isGroupChat else { return 0 }
        return chat.participants?.total ?? chat.participants?.items.count ?? 0
    }
}
