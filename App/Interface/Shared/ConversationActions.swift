import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
enum ConversationActions {
    static let reactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    static func chat(_ chat: Chat, store: ChatStore) -> [RelayAction] {
        var actions: [RelayAction] = []
        if chat.unreadCount > 0 || chat.isMarkedUnread == true {
            actions.append(RelayAction(title: "Mark Read", symbol: "envelope.open") {
                Task { await store.markChatAsRead(chat.id) }
            })
        }
        actions.append(RelayAction(title: chat.isArchived == true ? "Unarchive" : "Archive", symbol: chat.isArchived == true ? "tray.and.arrow.up" : "archivebox") {
            Task {
                if chat.isArchived == true { await store.unarchiveChat(chat.id) }
                else { await store.archiveChat(chat.id) }
            }
        })
        actions.append(RelayAction(title: chat.isMuted == true ? "Unmute" : "Mute", symbol: chat.isMuted == true ? "bell" : "bell.slash") {
            Task {
                if chat.isMuted == true { await store.unmuteChat(chat.id) }
                else { await store.muteChat(chat.id) }
            }
        })
        return actions
    }

    static func message(_ message: Message, chat: Chat, context: AppContext) -> [RelayAction] {
        let store = context.chats
        var actions = [RelayAction(title: "Reply", symbol: "arrowshape.turn.up.left") {
            store.setReplyTo(message)
            context.composer.pendingFocus = true
        }]
        if message.hasText || message.isDeletedMessage {
            actions.append(RelayAction(title: "Copy", symbol: "doc.on.doc") {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.displayText, forType: .string)
                #else
                UIPasteboard.general.string = message.displayText
                #endif
            })
        }
        if store.canEdit(message, in: chat) {
            actions.append(RelayAction(title: "Edit", symbol: "pencil") {
                context.composer.startEditing(message, in: chat)
            })
        }
        if !message.isDeletedMessage && message.isOutgoing(in: chat) {
            actions.append(RelayAction(title: "Delete", symbol: "trash", destructive: true) {
                Task { await store.deleteMessage(message.id, in: chat.id) }
            })
        }
        return actions
    }

    static func reaction(_ key: String, message: Message, chat: Chat, store: ChatStore) -> RelayAction {
        let selfID = chat.participants?.items.first { $0.isSelf == true }?.id ?? store.currentUserProfile?.id
        let selected = message.reactions?.contains { $0.reactionKey == key && $0.participantID == selfID } == true
        return RelayAction(title: key, symbol: "face.smiling", selected: selected) {
            Task {
                if selected { await store.removeReaction(from: message.id, in: chat.id, reactionKey: key) }
                else { await store.addReaction(to: message.id, in: chat.id, reactionKey: key) }
            }
        }
    }
}
