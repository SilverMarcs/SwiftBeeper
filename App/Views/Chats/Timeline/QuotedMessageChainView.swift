import SwiftUI

/// The quoted messages floating above a reply whose quote was tapped, in the
/// timeline's own bubbles. A message whose row was on screen moves up from
/// it, and back when the chain closes; the rest fade. It reports where it
/// reached, so the timeline can make room when the reply sits too near the
/// top.
struct QuotedMessageChainView: View {
    @Environment(\.revealQuotedMessageChain) private var revealQuotedMessageChain

    let presentation: QuotedMessageChainPresentation
    let chat: Chat
    var body: some View {
        VStack(spacing: 0) {
            ForEach(presentation.entries) { entry in
                MessageRowView(entry: entry, chat: chat)
                    .quotedMessageMorph(from: presentation.origins[entry.id], isPresented: presentation.isPresented)
                    .timelineRowPadding(startsSenderRun: false)
            }
            if let message = presentation.senderName {
                HStack(spacing: 6) {
                    Color.clear.frame(width: 28, height: 1)
                    SenderNameLabel(message: message)
                        .font(.subheadline)
                        .lineLimit(1)
                        .quotedMessageMorph(from: presentation.senderNameOrigin, isPresented: presentation.isPresented)
                    Spacer(minLength: 50)
                }
                .padding(.vertical, 2)
            }
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
