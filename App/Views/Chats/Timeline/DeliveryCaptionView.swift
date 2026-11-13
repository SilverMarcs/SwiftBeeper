import SwiftUI

/// "Sending…", "Sent", "Delivered", "Seen" or, in a group, who has seen it,
/// below the user's message, on the trailing side; in a group, who has seen
/// someone else's newest message, in line with its bubbles. Each step
/// replaces the words at once, with no animation.
struct DeliveryCaptionView: View {
    let indicator: DeliveryIndicator
    var isOutgoing = true

    /// Past a group sender's avatar and the gap after it, to the bubbles' edge.
    private static let incomingLeadingInset: CGFloat = 28 + 6 + 3
    private static let outgoingTrailingInset: CGFloat = 3

    var body: some View {
        Text(indicator.label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(isOutgoing ? .trailing : .leading)
            .padding(isOutgoing ? .trailing : .leading, isOutgoing ? Self.outgoingTrailingInset : Self.incomingLeadingInset)
            // Matches the gap a caption had inside its message's row.
            .padding(.top, 2)
            // Keeps a long list of names within the bubbles' width.
            .padding(isOutgoing ? .leading : .trailing, 50)
            .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)
            .transaction { $0.animation = nil }
    }
}
