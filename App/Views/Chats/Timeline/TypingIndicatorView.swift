import SwiftUI

/// Uses the same text metrics, chrome, and sender alignment as an incoming row.
struct TypingIndicatorView: View {
    let participant: ChatParticipant
    let chat: Chat
    let isFirstInGroup: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if !chat.isSingleChat {
                ProfileAvatarView(participant: participant, dimension: 28)
            }

            VStack(alignment: .leading, spacing: 4) {
                if !chat.isSingleChat && isFirstInGroup {
                    Text(participant.displayName)
                        .font(.subheadline)
                        .bold()
                        .foregroundStyle(IdentityColor(id: participant.id).nameStyle)
                }

                TypingBubbleView()
            }

            Spacer(minLength: 50)
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(participant.displayName) is typing"))
    }
}
