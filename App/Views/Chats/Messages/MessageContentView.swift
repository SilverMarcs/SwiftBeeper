import SwiftUI

/// A message's bubbles: its attachments and text, or its deleted form. The
/// context menu covers the whole stack; reactions sit below it, in the row.
struct MessageContentView: View {
    let message: Message
    let chat: Chat
    @Environment(\.typingBubbleNamespace) private var typingBubbleNamespace

    var body: some View {
        let isOutgoing = message.isSender
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
                .foregroundStyle(isOutgoing ? .white : .primary)
                .messageTextSelection(id: message.id)
                .fixedSize(horizontal: false, vertical: true)
                .messageBubbleChrome(isOutgoing: isOutgoing)
            } else {
                ForEach((message.attachments ?? []).enumerated(), id: \.element.id) { index, attachment in
                    AttachmentView(attachment: attachment, message: message, chat: chat)
                        .modifier(TypingBubbleGeometry(isEnabled: index == 0))
                }

                if let visibleText = message.visibleText {
                    MessageTextView(text: message.formattedText ?? visibleText, isOutgoing: isOutgoing, expansionID: message.id)
                        .messageBubbleChrome(isOutgoing: isOutgoing)
                        // Media takes over the typing bubble when present; its
                        // caption has a separate background and must not match too.
                        .environment(\.typingBubbleNamespace, message.attachments?.isEmpty != false ? typingBubbleNamespace : nil)
                        .sendEffect(forConfirmed: isOutgoing ? message.id : nil)
                }
            }
        }
        #if !os(macOS)
        .contentShape(.contextMenuPreview, .rect(cornerRadius: 16))
        #endif
        .modifier(ReactionTargetHighlight(messageID: message.id))
        .contextMenu {
            MessageContextMenu(message: message, chat: chat)
        }
    }
}
