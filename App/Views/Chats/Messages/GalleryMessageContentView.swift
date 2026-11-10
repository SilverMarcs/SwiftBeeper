import SwiftUI

/// A run of photos folded into one bubble, with the run's text below the
/// grid, whether the network sent it as a caption or as its own part. Each
/// part is still its own message, so each keeps its own reactions; reply,
/// react, copy, and edit from the context menu address the text, or the first
/// photo without one, while save and delete cover the whole set.
struct GalleryMessageContentView: View {
    let messages: [Message]
    let chat: Chat

    var body: some View {
        let photos = messages.filter(\.isGalleryPhoto)
        let captionMessage = messages.first { $0.hasText && !$0.isAlbumAnnouncement }
        if let primary = captionMessage ?? photos.first {
            let isOutgoing = primary.isSender
            let reactionsAlignment: Alignment = isOutgoing ? .bottomLeading : .bottomTrailing
            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                ImageGalleryAttachmentView(messages: photos)
                    .modifier(TypingBubbleGeometry())
                    .overlay(alignment: reactionsAlignment) {
                        if captionMessage == nil {
                            GalleryReactionsView(messages: messages, chat: chat)
                        }
                    }

                if let captionMessage, let caption = captionMessage.visibleText {
                    // The grid takes over the typing bubble; the caption has a
                    // separate background and must not match too.
                    MessageTextView(text: captionMessage.formattedText ?? caption, isOutgoing: isOutgoing, expansionID: captionMessage.id)
                        .messageBubbleChrome(isOutgoing: isOutgoing)
                        .environment(\.typingBubbleNamespace, nil)
                        .sendEffect(forConfirmed: isOutgoing ? captionMessage.id : nil)
                        .overlay(alignment: reactionsAlignment) {
                            GalleryReactionsView(messages: messages, chat: chat)
                        }
                }
            }
            #if !os(macOS)
            .contentShape(.contextMenuPreview, .rect(cornerRadius: 12))
            #endif
            .contextMenu {
                MessageContextMenu(
                    message: primary,
                    chat: chat,
                    galleryMessages: messages.filter { $0.id != primary.id }
                )
            }
        }
    }
}
