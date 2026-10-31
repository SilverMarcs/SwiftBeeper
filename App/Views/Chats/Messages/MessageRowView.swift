import SwiftUI

/// A canonical message: in group chats the sender's name heads a run and their
/// avatar ends it; the read indicator follows the bubbles.
struct MessageRowView: View {
    let entry: TimelineEntry
    let chat: Chat
    @Environment(ChatStore.self) private var chatStore

    @State private var profileSheetParticipant: ChatParticipant?
    @State private var pendingDirectChat: Chat?

    var body: some View {
        let message = entry.message
        let isOutgoing = message.isSender
        let showsSenderIdentity = !isOutgoing && !chat.isSingleChat
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
                if showsSenderIdentity && entry.isFirstInGroup {
                    Text(message.senderDisplayName)
                        .font(.subheadline)
                        .bold()
                }

                if message.linkedMessageID?.isEmpty == false {
                    ReplyPreviewView(linkedMessage: entry.linkedMessage, isOutgoing: isOutgoing)
                        .modifier(TypingBubbleContentReveal())
                }

                MessageContentView(message: message, chat: chat)
                    .environment(\.openURL, OpenURLAction { url in
                        openMention(url, in: message)
                    })

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
