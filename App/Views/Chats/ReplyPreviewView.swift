import SwiftUI

/// The quoted message above a reply. Tapping it scrolls to that message.
struct ReplyPreviewView: View {
    @Environment(\.scrollToMessage) private var scrollToMessage

    let linkedMessage: Message?
    let isOutgoing: Bool

    var body: some View {
        Button {
            if let linkedMessage { scrollToMessage(linkedMessage.id) }
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
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ChatVisualStyle.replyPreviewFill(isOutgoing: isOutgoing))
            .clipShape(.rect(cornerRadius: 8))
            .contentShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
