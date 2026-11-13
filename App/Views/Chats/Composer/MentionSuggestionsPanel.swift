#if os(iOS)
import SwiftUI

/// The mention suggestions on iPhone and iPad: a glass panel floating just
/// above the composer bar, as wide as the focused bar, over the timeline.
struct MentionSuggestionsPanel: View {
    let participants: [ChatParticipant]
    let select: (ChatParticipant) -> Void

    var body: some View {
        MentionSuggestionsList(participants: participants, maximumHeight: 240, select: select)
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
            .glassEffect(.regular, in: .rect(cornerRadius: Self.cornerRadius))
            .padding(.horizontal, ComposerBarLayout.focusedMargin)
    }

    private static let cornerRadius: CGFloat = 20
}
#endif
