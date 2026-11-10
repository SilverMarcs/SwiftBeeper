import SwiftUI

/// One person's reaction: their avatar and name, with the reaction trailing.
struct ReactionDetailsRow: View {
    let reaction: Reaction
    /// Nil when the reactor isn't among the chat's loaded participants.
    let participant: ChatParticipant?

    var body: some View {
        HStack {
            ProfileAvatarView(
                name: name,
                imageURLString: participant?.imgURL,
                dimension: 32
            )

            Text(name)
                .lineLimit(1)

            Spacer()

            Text(reaction.reactionKey)
                .font(.title2)
        }
        .accessibilityElement(children: .combine)
    }

    private var name: String {
        participant?.displayName ?? reaction.participantID
    }
}
