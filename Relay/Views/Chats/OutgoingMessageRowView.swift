import SwiftUI

struct OutgoingMessageRowView: View {
    @Environment(ChatStore.self) private var chatStore

    let message: OutgoingMessage
    /// The quoted message for a reply, pre-resolved by the timeline grouping so
    /// the optimistic bubble shows the same header the confirmed one will.
    var linkedMessage: Message? = nil
    var onTapLinkedMessage: ((String) -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 50)

            VStack(alignment: .trailing, spacing: 4) {
                if let replyToMessageID = message.replyToMessageID, !replyToMessageID.isEmpty {
                    ReplyPreviewView(
                        linkedMessage: linkedMessage,
                        isOutgoing: true,
                        onTap: { onTapLinkedMessage?(replyToMessageID) }
                    )
                }

                ForEach(message.attachments) { attachment in
                    OutgoingAttachmentView(
                        attachment: attachment,
                        progress: message.uploadProgressByAttachmentID[attachment.id],
                        state: message.state
                    )
                }

                if !message.text.isEmpty {
                    Text(message.text.messageAttributed(
                        mentionIDs: nil,
                        participants: [],
                        isOutgoing: true
                    ))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .messageBubbleChrome(isOutgoing: true)
                }

                if case .failed(let error) = message.state {
                    MessageDeliveryStatusView(
                        status: .failed(
                            error: error,
                            retry: { chatStore.retrySending(message.id) }
                        )
                    )
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
