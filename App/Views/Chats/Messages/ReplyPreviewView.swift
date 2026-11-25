import SwiftUI

/// The quoted message above a reply, on the same grey fill in every chat,
/// headed by who wrote it: "You" for the user's own message, otherwise the
/// sender's name, either in the colour their ID hashes to. The text is
/// flattened like a chat list preview, so Markdown and blank lines don't use
/// up its two lines. Tapping it shows that message above `reply`, or runs
/// `action` when one is given.
struct ReplyPreviewView: View {
    @Environment(\.showQuotedMessage) private var showQuotedMessage

    let linkedMessage: Message?
    /// The message that quotes it; nil for an optimistic row.
    var reply: Message?
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
                Text(senderName)
                    .chatFont(.caption)
                    .bold()
                    .foregroundStyle(senderColor.map { AnyShapeStyle($0.nameStyle) } ?? AnyShapeStyle(.secondary))

                Text(quotedText)
                    .chatFont(.caption)
                    .foregroundStyle(.secondary)
                    .strikethrough(linkedMessage?.hasRetainedDeletedContent == true)
                    .lineLimit(2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quinary)
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    /// The quoted text as shown, which VoiceOver reads too.
    private var quotedText: AttributedString {
        linkedMessage?.previewSource.previewAttributed ?? "Original message"
    }

    private var senderName: String {
        if linkedMessage?.isSender == true { return "You" }
        return linkedMessage?.senderDisplayName ?? "Unknown"
    }

    /// The sender's colour, the user's own included; nil for a missing message.
    private var senderColor: IdentityColor? {
        linkedMessage.map { IdentityColor(id: $0.senderID) }
    }

    private var accessibilityLabel: String {
        return "Reply to \(senderName): \(String(quotedText.characters))"
    }
}
