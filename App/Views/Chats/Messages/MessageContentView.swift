import SwiftUI

/// A message's bubbles: its attachments and text, or its deleted form. The
/// context menu covers the whole stack; reactions sit below it, in the row.
struct MessageContentView: View {
    let message: Message
    let chat: Chat
    @Environment(\.typingBubbleNamespace) private var typingBubbleNamespace
    /// The stack's outer corners, where it meets the rows beside it.
    @Environment(\.messageBubbleJoins) private var bubbleJoins

    var body: some View {
        let isOutgoing = message.isSender
        // Each attachment and the text are bubbles of their own, joined.
        let bubbleCount = (message.attachments?.count ?? 0) + (message.visibleText == nil ? 0 : 1)
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
            if message.isDeletedMessage {
                Group {
                    if message.hasRetainedDeletedContent {
                        Text(message.displayFormattedText.messageAttributed)
                            .strikethrough()
                            .tint(isOutgoing ? .white : .accentColor)
                    } else {
                        Label(message.displayText, systemImage: "trash")
                            .italic()
                    }
                }
                .chatFont(.body)
                .foregroundStyle(isOutgoing ? .white : .primary)
                .messageTextSelection(id: message.id)
                .fixedSize(horizontal: false, vertical: true)
                .messageBubbleChrome(isOutgoing: isOutgoing)
            } else {
                ForEach((message.attachments ?? []).enumerated(), id: \.element.id) { index, attachment in
                    AttachmentView(attachment: attachment, message: message, chat: chat)
                        .modifier(TypingBubbleGeometry(isEnabled: index == 0))
                        .environment(\.messageBubbleJoins, bubbleJoins.bubble(at: index, of: bubbleCount))
                }

                if let visibleText = message.visibleText {
                    MessageTextWithLinkPreview(message: message, text: message.formattedText ?? visibleText, isOutgoing: isOutgoing)
                        .messageBubbleChrome(isOutgoing: isOutgoing)
                        .sendEffect(forConfirmed: isOutgoing ? message.id : nil)
                        // Media takes over the typing bubble when present; its
                        // caption has a separate background and must not match too.
                        .environment(\.typingBubbleNamespace, message.attachments?.isEmpty != false ? typingBubbleNamespace : nil)
                        .environment(\.messageBubbleJoins, bubbleJoins.bubble(at: bubbleCount - 1, of: bubbleCount))
                }
            }
        }
        #if !os(macOS)
        .contentShape(.contextMenuPreview, ChatVisualStyle.bubbleShape(isOutgoing: isOutgoing, joins: bubbleJoins))
        #endif
        .modifier(ReactionEmojiInputHost(messageID: message.id))
        .modifier(MessageReactionContextMenu(message: message, chat: chat))
    }
}
