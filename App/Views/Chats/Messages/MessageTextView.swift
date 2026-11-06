import SwiftUI

/// The pending row, confirmed row, and send animation use identical text metrics.
struct MessageTextView: View {
    let text: String
    let isOutgoing: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        MessageTextLayout(displayScale: displayScale) {
            MessageBlocksView(blocks: text.messageBlocks)
                .font(.body)
                .foregroundStyle(.primary)
                // Both sides sit on light washes, so links stay blue.
                .tint(.blue)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Keep a fitting text width from rounding down when a stack proposes it again.
/// Losing a fraction of a point can otherwise move the final word to a new line.
private struct MessageTextLayout: Layout {
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
