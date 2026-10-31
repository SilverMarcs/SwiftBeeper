import SwiftUI

/// The Remind Me tile, opening the same reminder menu as the chat's context menu.
/// It stays disabled until a chat is known.
struct ChatInfoReminderButton: View {
    let chat: Chat?

    var body: some View {
        if let chat {
            ChatReminderMenu(chat: chat) {
                ChatInfoActionLabel(title: "Remind Me", systemImage: "clock")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Remind Me")
        } else {
            ChatInfoActionButton("Remind Me", systemImage: "clock") {}
                .disabled(true)
        }
    }
}
