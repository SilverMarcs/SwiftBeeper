import SwiftUI

struct MentionSuggestionsPopover: View {
    let participants: [ChatParticipant]
    let select: (ChatParticipant) -> Void

    var body: some View {
        ScrollView {
            VStack {
                ForEach(participants) { participant in
                    MentionSuggestionRow(participant: participant) {
                        select(participant)
                    }
                }
            }
            .padding()
        }
        .frame(idealWidth: 300, maxHeight: 320)
        .fixedSize(horizontal: true, vertical: false)
        .presentationCompactAdaptation(.popover)
    }
}
