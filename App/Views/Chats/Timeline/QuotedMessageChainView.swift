import SwiftUI

/// The quoted messages floating above a reply whose quote was tapped, in the
/// timeline's own bubbles. A message whose row was on screen moves up from
/// it, and back when the chain closes; the rest fade. It reports where it
/// reached, so the timeline can make room when the reply sits too near the
/// top.
struct QuotedMessageChainView: View {
    @Environment(\.revealQuotedMessageChain) private var revealQuotedMessageChain
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let presentation: QuotedMessageChainPresentation
    let chat: Chat
    /// False for the first frame, so the copies start over their rows.
    @State private var hasAppeared = false

    var body: some View {
        let isSettled = hasAppeared && presentation.isPresented
        VStack(spacing: 0) {
            ForEach(presentation.entries) { entry in
                MessageRowView(entry: entry, chat: chat)
                    .timelineRowPadding(startsSenderRun: false)
                    .modifier(QuotedMessageMorphEffect(
                        originMaxY: presentation.origins[entry.id],
                        isSettled: isSettled
                    ))
            }
        }
        // Every message the chain could lead to is already in it.
        .environment(\.showQuotedMessage, ShowQuotedMessageAction { _, _ in })
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { minY in
            revealQuotedMessageChain(top: minY, count: presentation.entries.count)
        }
        .onAppear {
            withAnimation(ChatVisualStyle.quotedMessageAnimation(reduceMotion: reduceMotion)) {
                hasAppeared = true
            }
        }
    }
}
