import SwiftUI

/// Everyone who reacted to a message, with their reaction.
struct ReactionDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss

    let details: ReactionDetails

    var body: some View {
        NavigationStack {
            List(details.message.visibleReactions) { reaction in
                ReactionDetailsRow(
                    reaction: reaction,
                    participant: details.chat.participant(with: reaction.participantID)
                )
            }
            .navigationTitle("Reactions")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                InfoSheetCloseButton { dismiss() }
            }
        }
        .presentationDetents([.medium])
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 280)
        #endif
    }
}
