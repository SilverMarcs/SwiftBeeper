import SwiftUI

/// The avatars of a thread's most recent repliers, overlapping like Slack's.
struct ThreadParticipantsView: View {
    let participants: [ChatParticipant]

    var body: some View {
        if !participants.isEmpty {
            HStack(spacing: -4) {
                ForEach(participants) { participant in
                    ProfileAvatarView(participant: participant, dimension: 18)
                }
            }
            .accessibilityHidden(true)
        }
    }
}
