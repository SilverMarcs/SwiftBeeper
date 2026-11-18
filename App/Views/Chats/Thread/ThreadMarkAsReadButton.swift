import SwiftUI

/// Marks a thread as read, the chat list's Mark as Read for one thread.
struct ThreadMarkAsReadButton: View {
    @Environment(ChatStore.self) private var chatStore

    let rootID: String
    let chatID: String

    var body: some View {
        Button("Mark as Read", systemImage: "envelope.open") {
            chatStore.markThreadAsRead(rootID: rootID, chatID: chatID)
        }
    }
}
