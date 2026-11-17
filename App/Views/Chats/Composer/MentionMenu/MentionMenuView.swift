#if os(macOS)
import SwiftUI

/// The macOS mention menu's items. `MentionMenuController` hosts it in a
/// panel with the menu material behind it.
///
/// The members come as a value rather than through `state`, so replacing
/// the hosting view's root lays the new list out at once, and the panel can
/// take its size before it moves.
struct MentionMenuView: View {
    let participants: [ChatParticipant]
    let state: MentionMenuState
    let select: (ChatParticipant) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(participants) { participant in
                MentionMenuRow(
                    participant: participant,
                    isHighlighted: participant.id == state.highlightedID,
                    highlight: { state.highlightedID = participant.id },
                    select: { select(participant) }
                )
            }
        }
        .padding(MentionMenuMetrics.inset)
        .frame(minWidth: MentionMenuMetrics.minimumWidth, maxWidth: MentionMenuMetrics.maximumWidth)
        .fixedSize()
    }
}
#endif
