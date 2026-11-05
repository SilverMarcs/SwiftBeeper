import SwiftUI

/// The @ shown beside a chat's unread badge when an unread message mentions
/// the user. It stays tinted in muted chats, since mentions still notify there.
struct ChatMentionBadgeView: View {
    var body: some View {
        Image(systemName: "at")
            .font(.subheadline)
            .bold()
            .foregroundStyle(.tint)
            .accessibilityLabel("Mentioned")
    }
}
