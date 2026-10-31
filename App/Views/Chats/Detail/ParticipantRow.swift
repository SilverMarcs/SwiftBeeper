import SwiftUI

/// A chat member's avatar and name, used as a members list row label.
struct ParticipantRow: View {
    let participant: ChatParticipant

    var body: some View {
        HStack(spacing: 10) {
            ProfileAvatarView(participant: participant, dimension: 32)

            Text(participant.displayName)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            Spacer()

            if participant.isSelf == true {
                Text("You")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
