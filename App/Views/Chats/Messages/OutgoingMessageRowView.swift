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
                    ReplyPreviewView(linkedMessage: root, showsSenderName: showsQuotedSenderName) {
                        if let root { chatStore.showThread(for: root) }
                    }
                    .accessibilityHint("Opens the thread")
                } else if message.replyToMessageID?.isEmpty == false {
                    ReplyPreviewView(linkedMessage: entry.linkedMessage, showsSenderName: showsQuotedSenderName)
                }

                // The gallery or each attachment, then the text, as bubbles
                // of their own, joined as the confirmed row's will be.
                let galleryImages = message.galleryImages
                let mediaCount = galleryImages == nil ? message.attachments.count : 1
                let bubbleCount = mediaCount + (message.text.isEmpty ? 0 : 1)
                if let galleryImages {
                    OutgoingImageGalleryView(images: galleryImages, state: message.state)
                        .environment(\.messageBubbleJoins, entry.bubbleJoins.bubble(at: 0, of: bubbleCount))
                } else {
                    ForEach(message.attachments.enumerated(), id: \.element.id) { index, attachment in
                        OutgoingAttachmentView(attachment: attachment, message: message)
                            .environment(\.messageBubbleJoins, entry.bubbleJoins.bubble(at: index, of: bubbleCount))
                    }
                }

                if !message.text.isEmpty {
                    MessageTextView(text: message.text, isOutgoing: true, expansionID: message.id.uuidString)
                        .messageBubbleChrome(isOutgoing: true)
                        .sendEffect(forOutgoing: message.id)
                        .environment(\.messageBubbleJoins, entry.bubbleJoins.bubble(at: bubbleCount - 1, of: bubbleCount))
                }

                if case .failed(let error) = message.state {
                    MessageDeliveryStatusView(status: .failed(messageID: message.id, error: error))
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// Matches the confirmed row: a direct chat's quotes go without names.
    private var showsQuotedSenderName: Bool {
        chatStore.selectedChat?.isSingleChat != true
    }
}
