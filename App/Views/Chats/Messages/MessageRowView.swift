import SwiftUI

/// A canonical message: in group chats the sender's name heads a run and their
/// avatar ends it; reactions and a failed delivery's caption follow the bubbles.
struct MessageRowView: View {
    let entry: TimelineEntry
    let chat: Chat
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.composer) private var composer
    @Environment(\.quotedFocusRole) private var quotedFocusRole
    @Environment(\.timelineRowFrames) private var rowFrames

    @State private var profileSheetParticipant: ChatParticipant?
    /// Between the sender's name, the bubbles, and what follows them.
    static let stackSpacing: CGFloat = 4
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
                    MessageSenderAvatar(message: message, chat: chat) {
                        profileSheetParticipant = message.senderParticipant(in: chat)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .timelineContent).maxY } action: {
                        rowFrames?.update(entry.id, senderAvatarBottomEdge: $0)
                    }
                    .quotedFocusHandoff(quotedFocusRole.senderAvatar)
                } else {
                    Color.clear
                        .frame(width: 28, height: 1)
                        .overlay(alignment: .bottom) {
                            if let copy = quotedFocusRole.avatarCopy {
                                MessageSenderAvatar(message: message, chat: chat) {
                                    profileSheetParticipant = message.senderParticipant(in: chat)
                                }
                                .quotedMessageMorph(from: copy.origin, isPresented: copy.isPresented)
                                .id(copy.id)
                                .transition(.identity)
                            }
                        }
                }
            }

            VStack(alignment: isOutgoing ? .trailing : .leading, spacing: Self.stackSpacing) {
                if showsSenderName || isThreadBroadcast || isForwarded {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if showsSenderName {
                            SenderNameLabel(message: message)
                                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .timelineContent).maxY } action: {
                                    rowFrames?.update(entry.id, senderNameBottomEdge: $0)
                                }
                                .quotedFocusHandoff(quotedFocusRole.senderName)
                        }
                        if isThreadBroadcast {
                            ThreadBroadcastLabel(followsName: showsSenderName)
                        }
                        if isForwarded {
                            ForwardedLabel()
                        }
                    }
                    .chatFont(.subheadline)
                    .lineLimit(1)
                }

                if isThreadBroadcast {
                    // The thread's first message, quoted like a reply.
                    ReplyPreviewView(linkedMessage: entry.threadRoot) {
                        chatStore.showThread(for: message)
                    }
                    .accessibilityHint("Opens the thread")
                    .modifier(TypingBubbleContentReveal())
                    .quotedFocusHandoff(quotedFocusRole.replyPreview)
                } else if message.linkedMessageID?.isEmpty == false {
                    ReplyPreviewView(linkedMessage: entry.linkedMessage, reply: message)
                        .modifier(TypingBubbleContentReveal())
                        .quotedFocusHandoff(quotedFocusRole.replyPreview)
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
                // The bubbles' outer corners, where they meet the rows beside.
                .environment(\.messageBubbleJoins, entry.bubbleJoins)
                .alignmentGuide(.messageBubbleTop) { $0[.top] }
                .modifier(MessageBookmarkTint(messageIDs: entry.messages.map(\.id), chatID: chat.id))

                // Outside the bubbles' context menu, so holding a pill opens
                // the sheet of who reacted instead. The pills reach up over
                // the bubbles' bottom edge, past the stack's spacing.
                ReactionPillsView(
                    messages: entry.messages,
                    chat: chat,
                    topOverlap: Self.stackSpacing + ChatVisualStyle.reactionPillOverlap
                )

                if !isInThread, let thread = message.thread, thread.replyCount > 0 {
                    ThreadSummaryButton(message: message, summary: thread, chat: chat)
                } else if isInThread, message.isThreadBroadcast == true {
                    Text(chat.isSingleChat ? "Also sent as direct message" : "Also sent to \(chat.displayTitle)")
                        .chatFont(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Progress shows once, below the newest row; a failure shows
                // on whichever message failed.
                if isOutgoing, let failed = entry.messages.first(where: { $0.deliveryStatus == .failed }) {
                    MessageDeliveryStatusView(status: .notDelivered(error: failed.deliveryError))
                }
            }

            if !isOutgoing {
                Spacer(minLength: 50)
            }
        }
        .onDisappear {
            rowFrames?.update(entry.id, senderNameBottomEdge: nil)
            rowFrames?.update(entry.id, senderAvatarBottomEdge: nil)
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
