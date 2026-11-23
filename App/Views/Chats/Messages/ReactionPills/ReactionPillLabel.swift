import SwiftUI

/// A reaction and, in groups, who reacted with it; in a direct chat, how
/// many did when both did. The user's own reactions are filled with the
/// accent color.
struct ReactionPillLabel: View {
    @Environment(ChatStore.self) private var chatStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let pill: ReactionPill
    let chat: Chat

    var body: some View {
        HStack(spacing: 4) {
            ReactionGlyph(pill.group.appearance, textStyle: .subheadline, isOnAccent: pill.isOwn)

            if !chat.isSingleChat {
                ReactionPillAvatars(pill: pill, chat: chat)
            } else if pill.group.count > 1 {
                Text(pill.group.count, format: .number)
                    // Rolls with the pills' animation; see `ReactionPillsView`.
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: Double(pill.group.count)))
                    .foregroundStyle(pill.isOwn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            }
        }
        .font(.subheadline)
        .reactionPillChrome(isOwn: pill.isOwn)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let names = pill.group.participantIDs.map { id in
            isSelf(id) ? "You" : pill.participant(with: id, in: chat)?.displayName ?? "Someone"
        }
        return "\(pill.group.spokenName), \(names.formatted(.list(type: .and)))"
    }

    private func isSelf(_ id: String) -> Bool {
        pill.participant(with: id, in: chat)?.isSelf == true || id == chatStore.currentUserProfile?.id
    }
}
