import SwiftUI

extension View {
    /// Hides this part of a row while a tapped quote's chain has it. A part
    /// that moved hides and returns at once, under the copy that moves; one
    /// that fades follows the chain's own animation. Hidden, it takes no
    /// taps, which go to the chain or the timeline around it.
    func quotedFocusHandoff(_ handoff: QuotedFocusHandoff) -> some View {
        opacity(handoff == .kept ? 1 : 0)
            .transaction(value: handoff) { transaction in
                if handoff == .moved { transaction.animation = nil }
            }
            .allowsHitTesting(handoff == .kept)
    }
}
