import SwiftUI

/// Moves a copy shown for a tapped quote, a quoted message's bubble or the
/// reply's sender's name or avatar, from where it sat in the timeline, and
/// back again. Until settled, the copy sits over that spot, its bottom edge
/// at `originMaxY` in the timeline content's space; settling animates it to
/// its own place. A copy with nowhere on screen to come from fades in and
/// out instead.
struct QuotedMessageMorphEffect: ViewModifier {
    let originMaxY: CGFloat?
    /// False sends the copy back as the chain closes.
    let isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False for the first frame, so the copy starts over its origin.
    @State private var hasAppeared = false

    func body(content: Content) -> some View {
        let isSettled = hasAppeared && isPresented
        let origin = reduceMotion ? nil : originMaxY
        content
            .visualEffect { [origin, isSettled] content, proxy in
                let offset = isSettled ? 0 : origin.map { $0 - proxy.frame(in: .timelineContent).maxY } ?? 0
                return content.offset(y: offset)
            }
            .opacity(isSettled || origin != nil ? 1 : 0)
            .onAppear {
                withAnimation(ChatVisualStyle.quotedMessageAnimation(reduceMotion: reduceMotion)) {
                    hasAppeared = true
                }
            }
    }
}

extension View {
    func quotedMessageMorph(from originMaxY: CGFloat?, isPresented: Bool) -> some View {
        modifier(QuotedMessageMorphEffect(originMaxY: originMaxY, isPresented: isPresented))
    }
}
