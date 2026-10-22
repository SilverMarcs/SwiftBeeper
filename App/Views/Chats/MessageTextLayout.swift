import SwiftUI

/// Keep a fitting text width from rounding down when a stack proposes it again.
/// Losing a fraction of a point can otherwise move the final word to a new line.
struct MessageTextLayout: Layout {
    let displayScale: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let size = text.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(
            width: (size.width * displayScale).rounded(.up) / displayScale,
            height: (size.height * displayScale).rounded(.up) / displayScale
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}
