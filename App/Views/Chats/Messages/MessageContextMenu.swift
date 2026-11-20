import SwiftUI

/// Reactions, reply, copy, edit, save, and delete for one message. For a photo
/// gallery, save and delete also cover the photos folded in after it.
struct MessageContextMenu: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var input
    @Environment(\.composer) private var composer
    @Environment(\.saveAttachment) private var saveAttachment
    @Environment(\.saveAttachmentToPhotos) private var saveAttachmentToPhotos

    let message: Message
    let chat: Chat
    var galleryMessages: [Message] = []

    var showsQuickReactions = true

    var body: some View {
        Section {
            EmptyView()
        } header: {
            Text(message.timestampText)
        }

        if showsQuickReactions {
            ControlGroup {
                MessageQuickReactions(message: message, chat: chat)
                MessageReactionPickerButton(message: message, chat: chat)
            }
            .controlGroupStyle(.palette)
            .menuActionDismissBehavior(.enabled)
        }

        Section {
            if let composer, chatStore.canEdit(message, in: chat) {
                Button("Edit", systemImage: "pencil") {
                    input.startEditing(message, in: composer)
                }
            }

            // Inside a thread every message is already a thread reply.
            if let composer, !composer.target.isThread {
                Button("Reply", systemImage: "arrowshape.turn.up.left") {
                    input.reply(to: message, in: composer)
                }
            }

            if message.hasText || message.isDeletedMessage {
                Button("Copy Message", systemImage: "doc.on.doc", action: copyMessageText)
            }

            if chatStore.messageBookmarks.isAvailable, !message.isDeletedMessage {
                let isBookmarked = chatStore.isBookmarked(message)
                Button(isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: isBookmarked ? "bookmark.slash" : "bookmark") {
                    Task { await chatStore.setBookmarked(message, !isBookmarked) }
                }
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

    private func copyMessageText() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.displayText, forType: .string)
        #else
        UIPasteboard.general.string = message.displayText
        #endif
    }
}
