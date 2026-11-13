import SwiftUI

/// The quoted messages floating above a reply whose quote was tapped, in the
/// timeline's own bubbles. It reports where it reached, so the timeline can
/// make room when the reply sits too near the top.
struct QuotedMessageChainView: View {
    @Environment(\.revealQuotedMessageChain) private var revealQuotedMessageChain

    let entries: [TimelineEntry]
    let chat: Chat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                MessageRowView(entry: entry, chat: chat)
                    .timelineRowPadding(startsSenderRun: false)
            }
        }
        // Every message the chain could lead to is already in it.
        .environment(\.showQuotedMessage, ShowQuotedMessageAction { _, _ in })
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { minY in
            revealQuotedMessageChain(top: minY, count: entries.count)
        }
    }
}
