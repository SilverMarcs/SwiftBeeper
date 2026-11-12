import SwiftUI

/// A toolbar menu of the open chat's threads with replies you haven't seen.
/// Choosing one opens it, which clears it from the menu.
struct UnreadThreadsMenu: View {
    @Environment(ChatStore.self) private var chatStore

    var body: some View {
        Menu("Unread Threads", systemImage: "bubble.left.and.text.bubble.right") {
            ForEach(chatStore.unreadThreads) { root in
                Button {
                    chatStore.showThread(for: root)
                } label: {
                    Text(label(for: root))
                }
            }
        }
        .accessibilityHint("Lists threads with new replies")
    }

    private func label(for root: Message) -> String {
        let text = root.displayText
        guard let sender = root.senderName, !sender.isEmpty else { return text }
        return "\(sender): \(text)"
    }
}
