import SwiftUI

/// Quick buttons under an info header: an optional Message, then mute, pin,
/// archive, and a reminder for the chat. Those stay disabled until a chat is known.
struct ChatInfoActions: View {
    let chat: Chat?
    var onMessage: (() -> Void)? = nil
    /// Runs after a chat action finishes, for screens holding a chat snapshot.
    var onChatUpdated: (() async -> Void)? = nil
    @Environment(ChatStore.self) private var chatStore

    var body: some View {
        let isMuted = chat?.isMuted == true
        let isPinned = chat?.isPinned == true
        let isArchived = chat?.isArchived == true

        HStack {
            if let onMessage {
                ChatInfoActionButton("Message", systemImage: "bubble.left", action: onMessage)
            }

            ChatInfoActionButton(
                isMuted ? "Unmute" : "Mute",
                systemImage: isMuted ? "bell" : "bell.slash"
            ) {
                perform { chatID in
                    if isMuted {
                        await chatStore.unmuteChat(chatID)
                    } else {
                        await chatStore.muteChat(chatID)
                    }
                }
            }
            .disabled(chat.map { chatStore.mutingChatIDs.contains($0.id) } ?? true)

            ChatInfoActionButton(
                isPinned ? "Unpin" : "Pin",
                systemImage: isPinned ? "pin.slash" : "pin"
            ) {
                perform { await chatStore.setChatPinned($0, pinned: !isPinned) }
            }
            .disabled(chat.map { chatStore.pinningChatIDs.contains($0.id) } ?? true)

            ChatInfoActionButton(
                isArchived ? "Unarchive" : "Archive",
                systemImage: isArchived ? "tray.and.arrow.up" : "archivebox"
            ) {
                perform { chatID in
                    if isArchived {
                        await chatStore.unarchiveChat(chatID)
                    } else {
                        await chatStore.archiveChat(chatID)
                    }
                }
            }
            .disabled(chat == nil)

            ChatInfoReminderButton(chat: chat)
        }
    }

    private func perform(_ action: @escaping (String) async -> Void) {
        guard let chatID = chat?.id else { return }
        Task {
            await action(chatID)
            await onChatUpdated?()
        }
    }
}
