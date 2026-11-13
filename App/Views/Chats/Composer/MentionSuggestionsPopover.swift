#if os(macOS)
import SwiftUI

/// The mention suggestions in a popover below the macOS field.
struct MentionSuggestionsPopover: View {
    let participants: [ChatParticipant]
    let select: (ChatParticipant) -> Void

    var body: some View {
        MentionSuggestionsList(participants: participants, maximumHeight: 220, select: select)
            .frame(width: 260)
    }
}
#endif
