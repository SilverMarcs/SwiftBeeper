import SwiftUI

/// Read, pin, archive, and mute actions for a chat row.
struct ChatRowActionsView: View {
    /// Leading swipes mark read, trailing swipes archive or mute, and the
    /// context menu offers everything.
    enum Placement {
        case leadingSwipe
        case trailingSwipe
        case contextMenu
    }

    @Environment(ChatStore.self) private var chatStore

    let chat: Chat
    let placement: Placement

    var body: some View {
        let isArchived = chat.isArchived == true
        let isMuted = chat.isMuted == true

        if placement != .trailingSwipe, chat.unreadCount > 0 {
            Button("Mark Read", systemImage: "envelope.open") {
                Task { await chatStore.markChatAsRead(chat.id) }
            }
            .tint(.blue)
        }

        if placement != .trailingSwipe {
            let isPinned = chat.isPinned == true
            Button(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin") {
                Task { await chatStore.setChatPinned(chat.id, pinned: !isPinned) }
            }
            .tint(.yellow)
            .disabled(chatStore.pinningChatIDs.contains(chat.id))
        }

        if placement != .leadingSwipe {
            Button(
                isArchived ? "Unarchive" : "Archive",
                systemImage: isArchived ? "tray.and.arrow.up" : "archivebox"
            ) {
                Task {
                    if isArchived {
                        await chatStore.unarchiveChat(chat.id)
                    } else {
                        await chatStore.archiveChat(chat.id)
                    }
                }
            }
            .tint(isArchived ? .blue : .orange)

            Button(
                isMuted ? "Unmute" : "Mute",
                systemImage: isMuted ? "bell" : "bell.slash"
            ) {
                Task {
                    if isMuted {
                        await chatStore.unmuteChat(chat.id)
                    } else {
                        await chatStore.muteChat(chat.id)
                    }
                }
            }
            .tint(.purple)
        }
    }
}
