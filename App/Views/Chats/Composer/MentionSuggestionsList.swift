import SwiftUI

/// The members matching a mention being typed, as tight rows that scroll
/// once there are more than fit in `maximumHeight`.
struct MentionSuggestionsList: View {
    let participants: [ChatParticipant]
    let maximumHeight: CGFloat
    let select: (ChatParticipant) -> Void

    /// The rows' own height, so the list is only as tall as they are.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(participants) { participant in
                    MentionSuggestionRow(participant: participant) {
                        select(participant)
                    }
                }
            }
            .padding(.vertical, 6)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: min(contentHeight, maximumHeight))
    }
}
