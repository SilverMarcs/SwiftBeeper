import SwiftUI

/// A canonical message: in group chats the sender's name heads a run and their
/// avatar ends it; the read indicator follows the bubbles.
struct MessageRowView: View {
    let entry: TimelineEntry
    let chat: Chat
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.composer) private var composer

    @State private var profileSheetParticipant: ChatParticipant?
    @State private var pendingDirectChat: Chat?

    var body: some View {
        let message = entry.message
        // Rows in a thread drop the thread footer and the thread quote.
        let isInThread = composer?.target.isThread == true
        let isOutgoing = message.isSender
        let showsSenderIdentity = !isOutgoing && !chat.isSingleChat
        let showsSenderName = showsSenderIdentity && entry.isFirstInGroup
        let isThreadBroadcast = message.isThreadBroadcast == true && !isInThread
        let isForwarded = entry.messages.contains { $0.isForwarded == true }
        HStack(alignment: .bottom, spacing: 6) {
            if isOutgoing {
                Spacer(minLength: 50)
            } else if showsSenderIdentity {
                if entry.isLastInGroup {
                    let sender = chat.participant(with: message.senderID)
                    Button {
                        profileSheetParticipant = sender
                    } label: {
                        ProfileAvatarView(
                            name: message.senderDisplayName,
                            imageURLString: sender?.imgURL,
                            dimension: 28
                        )
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                        .frame(width: 28, height: 1)
                }
            }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: 4) {
                if showsSenderName || isThreadBroadcast || isForwarded {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if showsSenderName {
                            Text(message.senderDisplayName)
                                .bold()
                        }
                        if isThreadBroadcast {
                            ThreadBroadcastLabel(followsName: showsSenderName)
                        }
                        if isForwarded {
                            ForwardedLabel()
                        }
                    }
                    .font(.subheadline)
                    .lineLimit(1)
                }

                if isThreadBroadcast {
                    // The thread's first message, quoted like a reply.
                    ReplyPreviewView(linkedMessage: entry.threadRoot, isOutgoing: isOutgoing) {
                        chatStore.showThread(for: message)
                    }
                    .accessibilityHint("Opens the thread")
                    .modifier(TypingBubbleContentReveal())
                } else if message.linkedMessageID?.isEmpty == false {
                    ReplyPreviewView(linkedMessage: entry.linkedMessage, isOutgoing: isOutgoing)
                        .modifier(TypingBubbleContentReveal())
                }

                Group {
                    if entry.galleryMessages.isEmpty {
                        MessageContentView(message: message, chat: chat)
                    } else {
                        GalleryMessageContentView(messages: entry.messages, chat: chat)
                    }
                }
                .environment(\.openURL, OpenURLAction { url in
                    openMention(url, in: message)
                })

                if !isInThread, let thread = message.thread, thread.replyCount > 0 {
                    ThreadSummaryButton(message: message, summary: thread, chat: chat)
                } else if isInThread, message.isThreadBroadcast == true {
                    Text(chat.isSingleChat ? "Also sent as direct message" : "Also sent to \(chat.displayTitle)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if isOutgoing && entry.showsReadIndicator {
                    MessageDeliveryStatusView(status: .read)
                }
            }

            if !isOutgoing {
                Spacer(minLength: 50)
            }
        }
        .sheet(item: $profileSheetParticipant, onDismiss: openPendingDirectChat) { participant in
            ParticipantInfoSheet(participant: participant, sourceChat: chat) { chat in
                pendingDirectChat = chat
            }
        }
    }

    private func openPendingDirectChat() {
        guard let chat = pendingDirectChat else { return }
        pendingDirectChat = nil
        chatStore.openChat(chat)
    }

    private func openMention(_ url: URL, in message: Message) -> OpenURLAction.Result {
        guard let mention = MessageMentionLink(url) else { return .systemAction }
        let attributed = message.displayFormattedText.messageAttributed
        let label = attributed.runs.first(where: { $0.link == url }).map {
            String(attributed[$0.range].characters)
        }
        // Large groups only load a participant sample. A link still opens a
        // useful profile even when its user isn't in that sample anymore.
        profileSheetParticipant = chat.participant(with: mention.userID) ?? ChatParticipant(
            id: mention.userID, username: nil, fullName: label, imgURL: nil,
            isSelf: mention.userID == chatStore.currentUserProfile?.id
        )
        return .handled
    }
}
