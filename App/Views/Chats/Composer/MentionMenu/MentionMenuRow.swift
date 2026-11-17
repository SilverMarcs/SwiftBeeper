#if os(macOS)
import SwiftUI

/// One member in the macOS mention menu, drawn as a menu item: the
/// highlight is an accent-coloured rounded rect with the text in white.
struct MentionMenuRow: View {
    let participant: ChatParticipant
    let isHighlighted: Bool
    let highlight: () -> Void
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: MentionMenuMetrics.avatarSpacing) {
                ProfileAvatarView(participant: participant, dimension: MentionMenuMetrics.avatarDimension)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(participant.displayName)
                        .foregroundStyle(isHighlighted ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .layoutPriority(1)
                    if let username = participant.username?.trimmed,
                       !username.isEmpty, username != participant.displayName {
                        Text(username)
                            .foregroundStyle(isHighlighted ? AnyShapeStyle(.white.secondary) : AnyShapeStyle(.secondary))
                    }
                }
                .lineLimit(1)
            }
            .padding(.horizontal, MentionMenuMetrics.itemPadding)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: MentionMenuMetrics.itemCornerRadius)
                        .fill(.tint)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // A menu highlights what the pointer passes over.
        .onContinuousHover { phase in
            if case .active = phase, !isHighlighted { highlight() }
        }
        .accessibilityLabel("Mention \(participant.displayName)")
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}
#endif
