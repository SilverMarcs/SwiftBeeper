import SwiftUI

/// The first few people who reacted, overlapping, then how many more did.
struct ReactionPillAvatars: View {
    @Environment(ChatStore.self) private var chatStore

    let pill: ReactionPill
    let chat: Chat

    private static let shownLimit = 3
    private static let dimension: CGFloat = 18

    var body: some View {
        HStack(spacing: 4) {
            OverlappingAvatarsView(
                participants: pill.group.participantIDs.prefix(Self.shownLimit).map(participant(with:)),
                dimension: Self.dimension
            ) {
                ReactionPillFill(isOwn: pill.isOwn)
            }

            if pill.group.count > Self.shownLimit {
                Text("+\(pill.group.count - Self.shownLimit)")
                    .font(.caption)
                    .foregroundStyle(pill.isOwn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
        }
    }

    /// The reactor's profile, with the user's own photo for themselves, or
    /// "?" in their colour when no member profile is available.
    private func participant(with id: String) -> ChatParticipant {
        if let participant = pill.participant(with: id, in: chat) {
            return chatStore.displayedParticipant(participant, in: chat)
        }
        if let profile = chatStore.currentUserProfile, profile.id == id {
            return chatStore.displayedParticipant(profile, in: chat)
        }
        return ChatParticipant(id: id, username: nil, fullName: "?", imgURL: nil, isSelf: nil)
    }
}
