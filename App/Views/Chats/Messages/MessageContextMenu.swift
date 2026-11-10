import SwiftUI

/// Reactions, who reacted, reply, copy, edit, save, and delete for one message. For a photo
/// gallery, save and delete also cover the photos folded in after it.
struct MessageContextMenu: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var input
    @Environment(\.composer) private var composer
    @Environment(\.saveAttachment) private var saveAttachment
    @Environment(\.saveAttachmentToPhotos) private var saveAttachmentToPhotos
    @Environment(\.showReactionDetails) private var showReactionDetails

    let message: Message
    let chat: Chat
    var galleryMessages: [Message] = []

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
            if let composer, chatStore.canEdit(message, in: chat) {
                Button("Edit", systemImage: "pencil") {
                    input.startEditing(message, in: composer)
                }
            }

            if !message.visibleReactions.isEmpty {
                Button("Reactions", systemImage: "face.smiling") {
                    showReactionDetails(message, in: chat)
                }
            }

            // Inside a thread every message is already a thread reply.
            if let composer, !composer.target.isThread {
                Button("Reply", systemImage: "arrowshape.turn.up.left") {
                    input.reply(to: message, in: composer)
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

        if !galleryMessages.isEmpty {
            let attachments = ([message] + galleryMessages).flatMap { $0.attachments ?? [] }
            Divider()
            Button("Save All to Photos", systemImage: "photo.on.rectangle.angled") {
                saveAttachmentToPhotos(attachments)
            }
            #if os(macOS)
            Button("Save All to Downloads", systemImage: "arrow.down") { saveAttachment(attachments) }
            #else
            Button("Save All to Files", systemImage: "folder") { saveAttachment(attachments) }
            #endif
        } else if let attachments = message.attachments, !attachments.isEmpty {
            Divider()
            ForEach(attachments) { attachment in
                if attachment.photoLibraryContentType != nil {
                    Button("Save to Photos", systemImage: "photo.on.rectangle.angled") {
                        saveAttachmentToPhotos(attachment)
                    }
                }
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
                    for message in [message] + galleryMessages {
                        await chatStore.deleteMessage(message.id, in: message.chatID)
                    }
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
