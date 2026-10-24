import SwiftUI

/// A chat member in the info sheet; tapping it opens their profile.
struct ParticipantRow: View {
    let participant: ChatParticipant
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
