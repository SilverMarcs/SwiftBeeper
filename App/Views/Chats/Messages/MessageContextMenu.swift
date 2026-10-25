import SwiftUI

/// Reactions, reply, copy, edit, save, and delete for one message.
struct MessageContextMenu: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.saveAttachment) private var saveAttachment

    let message: Message
    let chat: Chat

    private static let commonReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    var body: some View {
        Section {
            EmptyView()
        } header: {
            Text(message.timestampText)
        }

        Picker(selection: Binding(get: { ownReactionKey }, set: setOwnReaction)) {
            #if os(macOS)
            Text("None").tag(String?.none)
            #endif
            ForEach(Self.commonReactions, id: \.self) { emoji in
                Text(emoji).tag(String?.some(emoji))
            }
        } label: {
            #if os(macOS)
            Label("Reactions", systemImage: "face.smiling.inverse")
                .labelStyle(.titleAndIcon)
            #endif
        }
        #if !os(macOS)
        .pickerStyle(.palette)
        .menuActionDismissBehavior(.enabled)
        #endif

        Section {
            if chatStore.canEdit(message, in: chat) {
                Button("Edit", systemImage: "pencil") {
                    withAnimation {
                        chatStore.startEditing(message, in: chat)
                    }
                }
            }
            
            Button("Reply", systemImage: "arrowshape.turn.up.left") {
                withAnimation {
                    chatStore.setReplyTo(message)
                }
            }

            if message.hasText || message.isDeletedMessage {
                Button("Copy", systemImage: "doc.on.doc", action: copyMessageText)
            }
        } header: {
            #if !os(macOS)
            Text(message.timestampText)
            #endif
        }

        if let attachments = message.attachments, !attachments.isEmpty {
            Divider()
            ForEach(attachments) { attachment in
                #if os(macOS)
                Button("Save to Downloads", systemImage: "arrow.down") { saveAttachment(attachment) }
                #else
                Button("Save to Files", systemImage: "folder") { saveAttachment(attachment) }
                #endif
            }
        }

        if !message.isDeletedMessage && message.isSender {
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) {
                Task {
                    await chatStore.deleteMessage(message.id, in: message.chatID)
                }
            }
        }
    }

    private var ownReactionKey: String? {
        guard let selfID = chat.participants?.items.first(where: { $0.isSelf == true })?.id else { return nil }
        return message.reactions?.first { $0.participantID == selfID }?.reactionKey
    }

    private func setOwnReaction(_ newValue: String?) {
        let old = ownReactionKey
        Task {
            if let old, old != newValue {
                await chatStore.removeReaction(from: message.id, in: message.chatID, reactionKey: old)
            }
            if let newValue, newValue != old {
                await chatStore.addReaction(to: message.id, in: message.chatID, reactionKey: newValue)
            }
        }
    }

    private func copyMessageText() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.displayText, forType: .string)
        #else
        UIPasteboard.general.string = message.displayText
        #endif
    }
}
