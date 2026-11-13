import SwiftUI

/// Small avatars overlapping from the leading edge, each ringed with `ring`,
/// the fill of whatever holds them, so its edge stays visible over the one
/// before it. Shared by reaction pills and the "seen by" pill.
struct OverlappingAvatarsView<Ring: View>: View {
    /// Who to show, leading first; callers cap how many.
    let participants: [ChatParticipant]
    let dimension: CGFloat
    let ring: Ring

    init(participants: [ChatParticipant], dimension: CGFloat, @ViewBuilder ring: () -> Ring) {
        self.participants = participants
        self.dimension = dimension
        self.ring = ring()
    }

    var body: some View {
        HStack(spacing: -dimension / 3) {
            ForEach(participants) { participant in
                ProfileAvatarView(participant: participant, dimension: dimension)
                    .padding(1)
                    .background { ring }
                    .clipShape(.circle)
            }
        }
    }
}
