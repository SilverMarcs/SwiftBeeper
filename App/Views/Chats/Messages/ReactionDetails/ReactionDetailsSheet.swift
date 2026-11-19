import SwiftUI

/// Everyone who reacted to a message, with their reaction, filtered to all
/// reactions or one of them.
struct ReactionDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ChatStore.self) private var chatStore

    let details: ReactionDetails

    /// The reaction listed, or nil for all of them.
    @State private var selectedKey: String?
    @State private var sheetWidth: CGFloat = 320

    /// The toolbar's close button and margins, left beside the picker.
    private static let closeButtonAllowance: CGFloat = 100

    init(details: ReactionDetails) {
        self.details = details
        _selectedKey = State(initialValue: details.reactionKey)
    }

    var body: some View {
        NavigationStack {
            List(reactions) { reaction in
                ReactionDetailsRow(
                    reaction: reaction,
                    participant: (reaction.participant ?? details.chat.participant(with: reaction.participantID)).map {
                        chatStore.displayedParticipant($0, in: details.chat)
                    }
                )
            }
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ReactionDetailsFilterPicker(
                        groups: details.message.groupedReactions,
                        selection: $selectedKey,
                        maxWidth: max(sheetWidth - Self.closeButtonAllowance, 0)
                    )
                }
                // The picker's own capsule; the item's glass would span its
                // full frame.
                .sharedBackgroundVisibility(.hidden)
                InfoSheetCloseButton { dismiss() }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { sheetWidth = $0 }
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        .presentationDetents([.medium])
        #if os(macOS)
        .frame(minWidth: 320, minHeight: 280)
        #endif
    }

    private var reactions: [Reaction] {
        let reactions = details.message.visibleReactions
        guard let selectedKey else { return reactions }
        return reactions.filter { $0.reactionKey == selectedKey }
    }
}
