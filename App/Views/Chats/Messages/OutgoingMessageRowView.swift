import SwiftUI

/// An optimistic message, laid out like a confirmed one so the swap is seamless,
/// with a retry when delivery fails.
struct OutgoingMessageRowView: View {
    let entry: OutgoingTimelineEntry
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.composer) private var composer

    var body: some View {
        let message = entry.message
        // Matches `MessageRowView`: the thread itself doesn't quote its root.
        let isThreadBroadcast = message.alsoSendToChat && composer?.target.isThread != true
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 50)

            VStack(alignment: .trailing, spacing: 4) {
                if isThreadBroadcast, let rootID = message.broadcastThreadRootID {
                    ThreadBroadcastLabel(followsName: false)
                        .font(.subheadline)
                        .lineLimit(1)
                    let root = entry.threadRoot ?? chatStore.activeThread.flatMap { $0.rootID == rootID ? $0.root : nil }
                    ReplyPreviewView(linkedMessage: root, isOutgoing: true) {
                        if let root { chatStore.showThread(for: root) }
                    }
                    .accessibilityHint("Opens the thread")
                } else if message.replyToMessageID?.isEmpty == false {
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
