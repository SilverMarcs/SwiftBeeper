import SwiftUI

struct MentionSuggestionRow: View {
    let participant: ChatParticipant
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                ProfileAvatarView(participant: participant, dimension: 32)
                VStack(alignment: .leading) {
                    Text(participant.displayName)
                        .foregroundStyle(.primary)
                    if let username = participant.username?.trimmed,
                       !username.isEmpty, username != participant.displayName {
                        Text(username)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mention \(participant.displayName)")
    }
}
