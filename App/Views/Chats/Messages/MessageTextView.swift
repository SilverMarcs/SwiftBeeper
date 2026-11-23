import SwiftUI

/// The pending row, confirmed row, and send animation use identical text metrics.
/// A long body shows a preview until expanded; see `MessageCollapse`.
struct MessageTextView: View {
    let text: String
    let isOutgoing: Bool
    /// Identifies the message to the timeline's `ExpandedMessages` and
    /// `SelectableMessages`. Nil always shows the whole text and never
    /// selects it.
    var expansionID: String?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.expandedMessages) private var expandedMessages
    @Environment(\.selfMentionUserID) private var selfMentionUserID

    var body: some View {
        // The user's own messages don't need their mentions of themselves found.
        let highlightedUserID = isOutgoing ? nil : selfMentionUserID
        MessageTextLayout(displayScale: displayScale) {
            if let expansionID, let expandedMessages, let preview = text.collapsedMessageBlocks(highlightingMentionOf: highlightedUserID) {
                let isExpanded = expandedMessages.contains(expansionID)
                VStack(alignment: .trailing, spacing: 3) {
                    MessageBlocksText(
                        blocks: isExpanded ? text.messageBlocks(highlightingMentionOf: highlightedUserID) : preview,
                        isOutgoing: isOutgoing,
                        selectionID: expansionID
                    )
                    Button(isExpanded ? "Show Less" : "Show More") {
                        expandedMessages.toggle(expansionID)
                    }
                    .buttonBorderShape(.capsule)
                    .chatFont(.body)
                    // Muted like the text, not the bubble's link tint.
                    .foregroundStyle(isOutgoing ? .white : .primary)
                }
            } else {
                MessageBlocksText(blocks: text.messageBlocks(highlightingMentionOf: highlightedUserID), isOutgoing: isOutgoing, selectionID: expansionID)
            }
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
