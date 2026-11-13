import SwiftUI

/// The first few people who reacted, overlapping, then how many more did.
struct ReactionPillAvatars: View {
    @Environment(ChatStore.self) private var chatStore

    let participantIDs: [String]
    let chat: Chat
    /// Whether the pill is the user's own, filled with the accent color.
    let isOwn: Bool

    private static let shownLimit = 3
    private static let dimension: CGFloat = 18

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: -Self.dimension / 3) {
                ForEach(participantIDs.prefix(Self.shownLimit), id: \.self) { id in
                    ProfileAvatarView(participant: participant(with: id), dimension: Self.dimension)
                        // Each avatar's edge stays visible over the one before it.
                        .padding(1)
                        .background { ReactionPillFill(isOwn: isOwn) }
                        .clipShape(.circle)
                }
            }

            if participantIDs.count > Self.shownLimit {
                Text("+\(participantIDs.count - Self.shownLimit)")
                    .font(.caption)
                    .foregroundStyle(isOwn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
        }
    }

    /// The reactor's profile, with the user's own photo for themselves.
    private func participant(with id: String) -> ChatParticipant? {
        if let participant = chat.participant(with: id) {
            return chatStore.displayedParticipant(participant, in: chat)
        }
        if let profile = chatStore.currentUserProfile, profile.id == id {
            return chatStore.displayedParticipant(profile, in: chat)
        }
        return nil
    }
}
