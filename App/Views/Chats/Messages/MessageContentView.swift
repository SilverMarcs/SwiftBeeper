import SwiftUI

/// A message's bubbles: its attachments and text, or its deleted form. Reactions
/// sit on the last bubble, and the context menu covers the whole stack.
struct MessageContentView: View {
    let message: Message
    let chat: Chat
    @Environment(\.typingBubbleNamespace) private var typingBubbleNamespace

    private enum Bubble: Equatable {
        case attachment(String?)
        case text
    }

    var body: some View {
        let isOutgoing = message.isSender
        let reactionsAlignment: Alignment = isOutgoing ? .bottomLeading : .bottomTrailing
        let lastBubble = lastBubble
        VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
            if message.isDeletedMessage {
                Group {
                    if message.hasRetainedDeletedContent {
                        Text(message.displayFormattedText.messageAttributed)
                            .strikethrough()
                            .tint(isOutgoing ? .white : .blue)
                    } else {
                        Label(message.displayText, systemImage: "trash")
                            .italic()
                    }
                }
                .foregroundStyle(isOutgoing ? .white : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .messageBubbleChrome(isOutgoing: isOutgoing)
                .overlay(alignment: reactionsAlignment) {
                    ReactionsBarView(message: message, chat: chat)
                }
            } else {
                ForEach((message.attachments ?? []).enumerated(), id: \.element.id) { index, attachment in
                    AttachmentView(attachment: attachment, message: message, chat: chat)
                        .modifier(TypingBubbleGeometry(isEnabled: index == 0))
                        .overlay(alignment: reactionsAlignment) {
                            if lastBubble == .attachment(attachment.id) {
                                ReactionsBarView(message: message, chat: chat)
                            }
                        }
                }

                if let visibleText = message.visibleText {
                    MessageTextView(text: message.formattedText ?? visibleText, isOutgoing: isOutgoing)
                        .messageBubbleChrome(isOutgoing: isOutgoing)
                        // Media takes over the typing bubble when present; its
                        // caption has a separate background and must not match too.
                        .environment(\.typingBubbleNamespace, message.attachments?.isEmpty != false ? typingBubbleNamespace : nil)
                        .sendEffect(forConfirmed: isOutgoing ? message.id : nil)
                        .overlay(alignment: reactionsAlignment) {
                            ReactionsBarView(message: message, chat: chat)
                        }
                }
            }
        }
        #if !os(macOS)
        .contentShape(.contextMenuPreview, .rect(cornerRadius: 16))
        #endif
        .contextMenu {
            MessageContextMenu(message: message, chat: chat)
        }
    }

    /// Text renders below attachments, so it carries the reactions when present.
    private var lastBubble: Bubble? {
        if message.hasText { return .text }
        return message.attachments?.last.map { .attachment($0.id) }
    }
}
