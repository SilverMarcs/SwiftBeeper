import SwiftUI

/// Above a thread reply also sent to the chat: "Replied to a thread", with the
/// thread's first message when it is loaded. Tapping it opens the thread.
struct ThreadBroadcastLabel: View {
    @Environment(ChatStore.self) private var chatStore

    let message: Message

    var body: some View {
        let root = message.threadRootID.flatMap { rootID in chatStore.messages.first { $0.id == rootID } }
        Button {
            chatStore.showThread(for: message)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrowshape.turn.up.left.2")
                Text("Replied to a thread")
                if let root {
                    Text(root.displayText)
                        .foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
            .font(.caption)
            .foregroundStyle(.secondary)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the thread")
    }
}
