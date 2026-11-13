import SwiftUI

/// Stacks a bubble's text over its link preview card. The bubble widens to
/// a card's preferred width when its text is narrower, and the card always
/// spans the bubble. A card with no height yet, still loading, takes no
/// space and leaves the bubble hugging its text.
struct MessageLinkPreviewLayout: Layout {
    /// The card's width when the text is narrower, matching media bubbles.
    static let preferredCardWidth = MediaBubbleSize.maxWidth - 2 * ChatVisualStyle.bubbleHorizontalPadding
    private static let spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let textSize = text.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        guard let card = subviews.dropFirst().first else { return textSize }
        let width = max(textSize.width, min(proposal.width ?? Self.preferredCardWidth, Self.preferredCardWidth))
        let cardHeight = card.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        guard cardHeight > 0 else { return textSize }
        return CGSize(width: width, height: textSize.height + Self.spacing + cardHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let text = subviews.first else { return }
        let textProposal = ProposedViewSize(width: bounds.width, height: nil)
        text.place(at: bounds.origin, anchor: .topLeading, proposal: textProposal)
        guard let card = subviews.dropFirst().first else { return }
        // The text fits within the bounds' width, so its height there is the
        // height it was sized with.
        let textHeight = text.sizeThatFits(textProposal).height
        card.place(
            at: CGPoint(x: bounds.minX, y: bounds.minY + textHeight + Self.spacing),
            anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: nil)
        )
    }
}
