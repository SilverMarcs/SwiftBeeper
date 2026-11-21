import SwiftUI

/// The quoted message above a reply, on the same grey fill in every chat,
/// headed by who wrote it: "You" for the user's own message, otherwise the
/// sender's name in their colour. Tapping it shows that message above
/// `reply`, or runs `action` when one is given.
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
                    .font(.caption)
                    .bold()
                    .foregroundStyle(senderColor.map { AnyShapeStyle($0.nameStyle) } ?? AnyShapeStyle(.secondary))

                Text(linkedMessage?.displayText ?? "Original message")
                    .font(.caption)
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

    private var senderName: String {
        if linkedMessage?.isSender == true { return "You" }
        return linkedMessage?.senderDisplayName ?? "Unknown"
    }

    /// Someone else's colour; nil for the user's own message or a missing one.
    private var senderColor: IdentityColor? {
        guard let linkedMessage, !linkedMessage.isSender else { return nil }
        return IdentityColor(id: linkedMessage.senderID)
    }

    private var accessibilityLabel: String {
        return "Reply to \(senderName): \(linkedMessage?.displayText ?? "Original message")"
    }
}
