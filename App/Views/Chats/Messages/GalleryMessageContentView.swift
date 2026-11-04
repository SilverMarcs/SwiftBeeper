import SwiftUI

/// A run of photos folded into one bubble. Each photo is still its own
/// message, so each keeps its own reactions; reply and react from the context
/// menu address the first photo, while save and delete cover the whole set.
struct GalleryMessageContentView: View {
    let messages: [Message]
    let chat: Chat

    var body: some View {
        if let message = messages.first {
            let isOutgoing = message.isSender
            ImageGalleryAttachmentView(messages: messages)
                .modifier(TypingBubbleGeometry())
                .overlay(alignment: isOutgoing ? .bottomLeading : .bottomTrailing) {
                    HStack(spacing: 4) {
                        ForEach(messages) { message in
                            ReactionsBarView(message: message, chat: chat)
                        }
                    }
                }
                #if !os(macOS)
                .contentShape(.contextMenuPreview, .rect(cornerRadius: 12))
                #endif
                .contextMenu {
                    MessageContextMenu(message: message, chat: chat, galleryMessages: Array(messages.dropFirst()))
                }
        }
    }
}
