import SwiftUI

/// An optimistic message, laid out like a confirmed one so the swap is seamless,
/// with a retry when delivery fails.
struct OutgoingMessageRowView: View {
    let entry: OutgoingTimelineEntry

    var body: some View {
        let message = entry.message
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 50)

            VStack(alignment: .trailing, spacing: 4) {
                if message.replyToMessageID?.isEmpty == false {
                    ReplyPreviewView(linkedMessage: entry.linkedMessage, isOutgoing: true)
                }

                ForEach(message.attachments) { attachment in
                    OutgoingAttachmentView(attachment: attachment, message: message)
                }

                if !message.text.isEmpty {
                    MessageTextView(text: message.text, isOutgoing: true)
                        .messageBubbleChrome(isOutgoing: true)
                        .sendEffect(forOutgoing: message.id)
                }

                if case .failed(let error) = message.state {
                    MessageDeliveryStatusView(status: .failed(messageID: message.id, error: error))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}
