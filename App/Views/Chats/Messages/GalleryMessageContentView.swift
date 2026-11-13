import SwiftUI

/// A run of photos folded into one bubble, with the run's text below the
/// grid, whether the network sent it as a caption or as its own part. Each
/// part is still its own message, so each keeps its own reactions, which the
/// row lists below the bubble; reply,
/// react, copy, and edit from the context menu address the text, or the first
/// photo without one, while save and delete cover the whole set.
struct GalleryMessageContentView: View {
    let messages: [Message]
    let chat: Chat
    /// The stack's outer corners, where it meets the rows beside it.
    @Environment(\.messageBubbleJoins) private var bubbleJoins

    var body: some View {
        let photos = messages.filter(\.isGalleryPhoto)
        let captionMessage = messages.first { $0.hasText && !$0.isAlbumAnnouncement }
        if let primary = captionMessage ?? photos.first {
            let isOutgoing = primary.isSender
            // The grid and the caption are bubbles of their own, joined.
            let bubbleCount = captionMessage == nil ? 1 : 2
            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                ImageGalleryAttachmentView(messages: photos)
                    .modifier(TypingBubbleGeometry())
                    .environment(\.messageBubbleJoins, bubbleJoins.bubble(at: 0, of: bubbleCount))

                if let captionMessage, let caption = captionMessage.visibleText {
                    // The grid takes over the typing bubble; the caption has a
                    // separate background and must not match too.
                    MessageTextView(text: captionMessage.formattedText ?? caption, isOutgoing: isOutgoing, expansionID: captionMessage.id)
                        .messageBubbleChrome(isOutgoing: isOutgoing)
                        .environment(\.typingBubbleNamespace, nil)
                        .environment(\.messageBubbleJoins, bubbleJoins.bubble(at: 1, of: bubbleCount))
                        .sendEffect(forConfirmed: isOutgoing ? captionMessage.id : nil)
                }
            }
            #if !os(macOS)
            .contentShape(.contextMenuPreview, ChatVisualStyle.bubbleShape(isOutgoing: isOutgoing, joins: bubbleJoins))
            #endif
            .modifier(ReactionTargetHighlight(messageID: primary.id))
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
