import SwiftUI

/// The quoted message above a reply. Tapping it shows that message above
/// `reply`, or runs `action` when one is given.
struct ReplyPreviewView: View {
    @Environment(\.showQuotedMessage) private var showQuotedMessage

    let linkedMessage: Message?
    /// The message that quotes it; nil for an optimistic row.
    var reply: Message?
    let isOutgoing: Bool
    var action: (() -> Void)?

    var body: some View {
        Button {
            if let action {
                action()
            } else if let linkedMessage {
                showQuotedMessage(linkedMessage, reply: reply)
            }
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(linkedMessage?.senderDisplayName ?? "Unknown")
                        .font(.caption)
                        .bold()
                        .foregroundStyle(.secondary)

                    Text(linkedMessage?.displayText ?? "Original message")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .strikethrough(linkedMessage?.hasRetainedDeletedContent == true)
                        .lineLimit(2)
                }
            }
            // The accent bar is a flexible shape; without this, a VStack
            // beside flexible media (photos, stickers) splits its height
            // with the media and stretches the preview.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ChatVisualStyle.replyPreviewFill(isOutgoing: isOutgoing))
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
