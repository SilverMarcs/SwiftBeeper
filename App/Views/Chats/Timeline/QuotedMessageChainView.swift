import SwiftUI

/// The quoted messages floating above a reply whose quote was tapped, in the
/// timeline's own bubbles, spaced as the timeline spaces its rows. A message
/// whose row was on screen moves up from it, and back when the chain closes;
/// the rest come down from above the timeline's top together, and go back up
/// there. It reports where it reached, so the timeline can make room when the
/// reply sits too near the top.
struct QuotedMessageChainView: View {
    @Environment(\.revealQuotedMessageChain) private var revealQuotedMessageChain

    let presentation: QuotedMessageChainPresentation
    let chat: Chat
    var body: some View {
        let entries = presentation.entries
        VStack(spacing: 0) {
            ForEach(entries.enumerated(), id: \.element.id) { index, entry in
                MessageRowView(entry: entry, chat: chat)
                    .quotedMessageMorph(
                        from: presentation.origins[entry.id],
                        enteringFromAbove: presentation.headerHeight,
                        isPresented: presentation.isPresented
                    )
                    // Wider where the sender changes, as between timeline rows.
                    .timelineRowPadding(
                        startsSenderRun: index > entries.startIndex
                            && entries[index - 1].message.senderID != entry.message.senderID
                    )
            }
            // The reply's row starts below the last quoted message as it
            // would below that message's row in the timeline.
            VStack(spacing: 0) {
                if let message = presentation.senderName {
                    HStack(spacing: 6) {
                        Color.clear.frame(width: 28, height: 1)
                        SenderNameLabel(message: message)
                            .font(.subheadline)
                            .lineLimit(1)
                            .quotedMessageMorph(
                                from: presentation.senderNameOrigin,
                                enteringFromAbove: presentation.headerHeight,
                                isPresented: presentation.isPresented
                            )
                        Spacer(minLength: 50)
                    }
                    // As far from the reply's bubble as in its own row.
                    .padding(.bottom, MessageRowView.stackSpacing)
                }
            }
            .timelineRowTopPadding(startsSenderRun: entries.last?.message.senderID != presentation.replySenderID)
        }
        // Copies never donate identity or geometry back to the timeline.
        .environment(\.quotedFocusRole, .none)
        .environment(\.timelineRowFrames, nil)
        // Every message the chain could lead to is already in it.
        .environment(\.showQuotedMessage, ShowQuotedMessageAction { _, _ in })
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { minY in
            revealQuotedMessageChain(top: minY, count: presentation.entries.count)
        }
    }
}
