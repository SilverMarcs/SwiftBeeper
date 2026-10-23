import SwiftUI

struct MessageRowView: View {
    let entry: TimelineEntry
    let chat: Chat

    @State private var profileSheetParticipant: ChatParticipant?

    var body: some View {
        let message = entry.message
        let isOutgoing = message.isSender
        let showsSenderIdentity = !isOutgoing && !chat.isSingleChat
        HStack(alignment: .bottom, spacing: 6) {
            if isOutgoing {
                Spacer(minLength: 50)
            } else if showsSenderIdentity {
                if entry.isLastInGroup {
                    Button {
                        profileSheetParticipant = chat.participant(with: message.senderID)
                    } label: {
                        ProfileAvatarView(
                            name: message.senderDisplayName,
                            imageURLString: chat.participant(with: message.senderID)?.imgURL,
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
                }

                MessageContentView(message: message, chat: chat)

                if isOutgoing && entry.showsReadIndicator {
                    MessageDeliveryStatusView(status: .read)
                }
            }

            if !isOutgoing {
                Spacer(minLength: 50)
            }
        }
        .sheet(item: $profileSheetParticipant) { participant in
            ParticipantProfileSheet(participant: participant)
        }
    }
}
