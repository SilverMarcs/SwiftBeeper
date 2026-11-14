import SwiftUI

/// Moves a copy shown for a tapped quote, a quoted message's bubble or the
/// reply's sender's name or avatar, from where it sat in the timeline, and
/// back again. Until settled, the copy sits over that spot, its bottom edge
/// at `originMaxY` in the timeline content's space; settling animates it to
/// its own place. A copy with nowhere on screen to come from either comes
/// down from above the top of the timeline, with the rest of its chain, or
/// fades in and out.
struct QuotedMessageMorphEffect: ViewModifier {
    let originMaxY: CGFloat?
    /// For a copy with no origin that comes down from above the timeline,
    /// rather than fading, how far above the timeline's top edge the chain's
    /// bottom starts. Only for the chain's copies, which sit above the reply
    /// as their rows do, and measure where the chain ends in
    /// `.quotedMessageChainBottom`. Nil fades the copy instead.
    let entryHeight: CGFloat?
    /// False sends the copy back as the chain closes.
    let isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False for the first frame, so the copy starts over its origin.
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        let isSettled = hasAppeared && isPresented
        let origin = reduceMotion ? nil : originMaxY
        let entryHeight = origin == nil && !reduceMotion ? entryHeight : nil
        content
            .visualEffect { [origin, entryHeight, isSettled] content, proxy in
                var offset: CGFloat = 0
                if isSettled {
                    offset = 0
                } else if let origin {
                    offset = origin - proxy.frame(in: .timelineContent).maxY
                } else if let entryHeight {
                    // Lifts the chain by as much as puts its bottom edge
                    // that far above the timeline's visible top, the same
                    // for every copy, so they keep their spacing coming down.
                    let chainBottom = proxy.frame(in: .scrollView).maxY
                        - proxy.frame(in: .quotedMessageChainBottom).maxY
                    offset = -max(chainBottom + entryHeight, 0)
                }
                return content.offset(y: offset)
            }
            .opacity(isSettled || origin != nil || entryHeight != nil ? 1 : 0)
            .onAppear {
                withAnimation(ChatVisualStyle.quotedMessageAnimation(reduceMotion: reduceMotion)) {
                    hasAppeared = true
                }
            }
    }
}

extension View {
    func quotedMessageMorph(from originMaxY: CGFloat?, enteringFromAbove entryHeight: CGFloat? = nil, isPresented: Bool) -> some View {
        modifier(QuotedMessageMorphEffect(originMaxY: originMaxY, entryHeight: entryHeight, isPresented: isPresented))
    }
}
