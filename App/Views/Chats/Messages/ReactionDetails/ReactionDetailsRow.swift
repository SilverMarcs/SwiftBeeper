import SwiftUI

/// One person's reaction: their avatar and name, with the reaction trailing.
struct ReactionDetailsRow: View {
    let reaction: Reaction
    /// Nil when no member profile is available for the reactor.
    let participant: ChatParticipant?

    var body: some View {
        HStack {
            ProfileAvatarView(
                name: name,
                colorID: reaction.participantID,
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
