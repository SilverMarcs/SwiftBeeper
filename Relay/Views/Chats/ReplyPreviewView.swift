import SwiftUI

struct ReplyPreviewView: View {
    @Environment(MessageStore.self) private var messageStore

    let linkedMessageID: String
    let chatID: String
    let isOutgoing: Bool

    var body: some View {
        let linkedMessage = messageStore.message(byID: linkedMessageID, in: chatID)

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
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ChatVisualStyle.replyPreviewFill(isOutgoing: isOutgoing))
        .clipShape(.rect(cornerRadius: 8))
    }
}
