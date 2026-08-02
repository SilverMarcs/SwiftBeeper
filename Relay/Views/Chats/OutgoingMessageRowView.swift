import SwiftUI

struct OutgoingMessageRowView: View {
    @Environment(ChatStore.self) private var chatStore

    let message: OutgoingMessage

    var body: some View {
        HStack(alignment: .bottom) {
            Spacer(minLength: 50)

            VStack(alignment: .trailing, spacing: 4) {
                ForEach(message.attachments) { attachment in
                    OutgoingAttachmentView(
                        attachment: attachment,
                        progress: message.uploadProgressByAttachmentID[attachment.id],
                        state: message.state
                    )
                }

                if !message.text.isEmpty {
                    Text(message.text.markdownAttributed)
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
