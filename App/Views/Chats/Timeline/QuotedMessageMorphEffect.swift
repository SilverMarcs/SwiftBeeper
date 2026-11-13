import SwiftUI

/// Moves a quoted message's copy in the chain from its own row in the
/// timeline, and back again. Until settled, the copy sits over that row's
/// bottom edge, `originMaxY` in the timeline content's space; settling
/// animates it to its place in the chain. A copy with no row on screen to
/// come from fades in and out instead.
struct QuotedMessageMorphEffect: ViewModifier {
    let originMaxY: CGFloat?
    let isSettled: Bool

    func body(content: Content) -> some View {
        content
            .visualEffect { [originMaxY, isSettled] content, proxy in
                let offset = isSettled ? 0 : originMaxY.map { $0 - proxy.frame(in: .timelineContent).maxY } ?? 0
                return content.offset(y: offset)
            }
            .opacity(isSettled || originMaxY != nil ? 1 : 0)
    }
}
