import SwiftUI

/// One member to mention: a small avatar, then their name and, when it
/// differs, their username on the same line.
struct MentionSuggestionRow: View {
    let participant: ChatParticipant
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ProfileAvatarView(participant: participant, dimension: Self.avatarDimension)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(participant.displayName)
                        .foregroundStyle(.primary)
                        .layoutPriority(1)
                    if let username = participant.username?.trimmed,
                       !username.isEmpty, username != participant.displayName {
                        Text(username)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Mention \(participant.displayName)")
    }

    #if os(macOS)
    private static let avatarDimension: CGFloat = 24
    #else
    private static let avatarDimension: CGFloat = 32
    #endif
}
