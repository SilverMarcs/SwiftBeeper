import SwiftUI

/// A reaction and, in groups, who reacted with it; in a direct chat, how
/// many did when both did. The user's own reactions are filled with the
/// accent color.
struct ReactionPillLabel: View {
    @Environment(ChatStore.self) private var chatStore

    let pill: ReactionPill
    let chat: Chat

    var body: some View {
        HStack(spacing: 4) {
            Text(pill.group.reactionKey)

            if !chat.isSingleChat {
                ReactionPillAvatars(participantIDs: pill.group.participantIDs, chat: chat, isOwn: pill.isOwn)
            } else if pill.group.count > 1 {
                Text(pill.group.count, format: .number)
                    .foregroundStyle(pill.isOwn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background { ReactionPillFill(isOwn: pill.isOwn) }
        .clipShape(.capsule)
        .contentShape(.capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let names = pill.group.participantIDs.map { id in
            isSelf(id) ? "You" : chat.participant(with: id)?.displayName ?? "Someone"
        }
        return "\(pill.group.reactionKey), \(names.formatted(.list(type: .and)))"
    }

    private func isSelf(_ id: String) -> Bool {
        chat.participant(with: id)?.isSelf == true || id == chatStore.currentUserProfile?.id
    }
}
