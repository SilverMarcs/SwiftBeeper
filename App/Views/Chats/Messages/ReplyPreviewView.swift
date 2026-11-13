import SwiftUI

/// The quoted message above a reply, drawn as a faded copy of the bubble it
/// quotes: a wash of the accent colour for the user's own message, the
/// incoming bubble's grey for anyone else's. In a group, the sender's name
/// heads it, in their colour; a direct chat has only two people, so the fill
/// alone says who wrote it. Tapping it shows that message above `reply`, or
/// runs `action` when one is given.
struct ReplyPreviewView: View {
    @Environment(\.showQuotedMessage) private var showQuotedMessage
    @Environment(\.recedesReplyPreview) private var recedes

    let linkedMessage: Message?
    /// The message that quotes it; nil for an optimistic row.
    var reply: Message?
    /// False in a direct chat, where the fill already tells the two apart.
    var showsSenderName = true
    var action: (() -> Void)?

    var body: some View {
        Button {
            if let action {
                action()
            } else if let linkedMessage {
                showQuotedMessage(linkedMessage, reply: reply)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                if showsSenderName {
                    Text(linkedMessage?.senderDisplayName ?? "Unknown")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(senderColor.map { AnyShapeStyle($0.nameStyle) } ?? AnyShapeStyle(.secondary))
                }

                Text(linkedMessage?.displayText ?? "Original message")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .strikethrough(linkedMessage?.hasRetainedDeletedContent == true)
                    .lineLimit(2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ChatVisualStyle.replyPreviewFill(quotesOwnMessage: quotesOwnMessage))
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        // While the messages it stands for are shown above its reply; a tap
        // on it then returns to the timeline, as around them.
        .timelineFocus(!recedes)
        // The name stays in the spoken label even where it isn't shown.
        .accessibilityLabel(accessibilityLabel)
    }

    private var quotesOwnMessage: Bool {
        linkedMessage?.isSender == true
    }

    /// Someone else's colour; nil for the user's own message or a missing one.
    private var senderColor: IdentityColor? {
        guard let linkedMessage, !linkedMessage.isSender else { return nil }
        return IdentityColor(id: linkedMessage.senderID)
    }

    private var accessibilityLabel: String {
        let sender = quotesOwnMessage ? "you" : linkedMessage?.senderDisplayName ?? "unknown sender"
        return "Reply to \(sender): \(linkedMessage?.displayText ?? "Original message")"
    }
}
