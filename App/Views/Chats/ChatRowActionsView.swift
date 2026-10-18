import SwiftUI

struct ChatRowActionsView: View {
    @Environment(ChatStore.self) private var chatStore

    let chat: Chat
    let includesReadAction: Bool
    let includesArchiveAndMuteActions: Bool

    var body: some View {
        Group {
            if includesReadAction, chat.unreadCount > 0 {
                Button("Mark Read", systemImage: "envelope.open") {
                    Task {
                        await chatStore.markChatAsRead(chat.id)
                    }
                }
                .tint(.blue)
            }

            if includesArchiveAndMuteActions {
                Button(
                    chat.isArchived == true ? "Unarchive" : "Archive",
                    systemImage: chat.isArchived == true ? "tray.and.arrow.up" : "archivebox"
                ) {
                    Task {
                        if chat.isArchived == true {
                            await chatStore.unarchiveChat(chat.id)
                        } else {
                            await chatStore.archiveChat(chat.id)
                        }
                    }
                }
                .tint(chat.isArchived == true ? .blue : .orange)

                Button(
                    chat.isMuted == true ? "Unmute" : "Mute",
                    systemImage: chat.isMuted == true ? "bell" : "bell.slash"
                ) {
                    Task {
                        if chat.isMuted == true {
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
}
