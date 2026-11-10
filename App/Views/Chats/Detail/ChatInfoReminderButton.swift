import SwiftUI

/// The Remind tile, opening the same reminder menu as the chat's context menu.
/// It stays disabled until a chat is known. The tile says "Remind" to fit
/// beside the other tiles; VoiceOver keeps the full "Remind Me".
struct ChatInfoReminderButton: View {
    let chat: Chat?

    var body: some View {
        if let chat {
            ChatReminderMenu(chat: chat) {
                ChatInfoActionLabel(title: "Remind", systemImage: "clock")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Remind Me")
        } else {
            ChatInfoActionButton("Remind", systemImage: "clock") {}
                .disabled(true)
        }
    }
}
