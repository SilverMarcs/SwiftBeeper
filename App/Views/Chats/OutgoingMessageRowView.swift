import SwiftUI

struct OutgoingMessageRowView: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var input

    let message: OutgoingMessage
    /// The quoted message for a reply, pre-resolved by the timeline grouping so
    /// the optimistic bubble shows the same header the confirmed one will.
    var linkedMessage: Message? = nil
    var onTapLinkedMessage: ((String) -> Void)? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
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
                    MessageTextView(text: message.text, isOutgoing: true)
                        .messageBubbleChrome(isOutgoing: true)
                        .modifier(MessageSendEffect(
                            animator: input.sendAnimator,
                            flight: input.sendAnimator.flight(forOutgoing: message.id)
                        ))
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
