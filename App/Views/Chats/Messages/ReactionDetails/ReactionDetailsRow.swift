import SwiftUI

/// One person's reaction: their avatar and name, with the reaction trailing,
/// named when it's a custom emoji.
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

            if !reaction.appearance.isEmoji {
                Text(reaction.spokenName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ReactionGlyph(reaction.appearance, textStyle: .title2)
                .font(.title2)
        }
        .accessibilityElement(children: .combine)
    }

    private var name: String {
        participant?.displayName ?? reaction.participantID
    }
}
