import SwiftUI

/// The quoted message above a reply. Tapping it scrolls to that message.
struct ReplyPreviewView: View {
    @Environment(\.scrollToMessage) private var scrollToMessage
    @Environment(\.outgoingBubbleColor) private var outgoingBubbleColor

    let linkedMessage: Message?
    let isOutgoing: Bool

    var body: some View {
        Button {
            if let linkedMessage { scrollToMessage(linkedMessage.id) }
        } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isOutgoing ? outgoingBubbleColor : .accentColor)
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
                        .lineLimit(1)
                }
            }
            // The accent bar is a flexible shape; without this, a VStack
            // beside flexible media (photos, stickers) splits its height
            // with the media and stretches the preview.
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ChatVisualStyle.replyPreviewFill(isOutgoing: isOutgoing, outgoingBubbleColor: outgoingBubbleColor))
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
