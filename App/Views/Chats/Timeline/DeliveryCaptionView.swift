import SwiftUI

/// "Sending…", "Sent", "Delivered", "Seen" or, in a group, who has seen it,
/// below the user's message, on the trailing side; in a group, who has seen
/// someone else's newest message, in line with its bubbles. Who has seen it
/// shows as a pill of their avatars; everything else, "Seen by all"
/// included, as words. Status changes crossfade in place.
struct DeliveryCaptionView: View {
    let indicator: DeliveryIndicator
    /// Resolves readers' avatars.
    let chat: Chat
    var isOutgoing = true

    /// Past a group sender's avatar and the gap after it, to the bubbles' edge.
    private static let incomingLeadingInset: CGFloat = 28 + 6 + 3
    private static let outgoingTrailingInset: CGFloat = 3

    var body: some View {
        ZStack(alignment: isOutgoing ? .trailing : .leading) {
            Group {
                if case .seenBy(let readers) = indicator {
                    SeenByPillView(readers: readers, chat: chat)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(indicator.label)
                } else {
                    Text(indicator.label)
                        .chatFont(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(isOutgoing ? .trailing : .leading)
                }
            }
            .id(indicator.label)
            .transition(.opacity)
        }
        .padding(isOutgoing ? .trailing : .leading, isOutgoing ? Self.outgoingTrailingInset : Self.incomingLeadingInset)
        // Matches the gap a caption had inside its message's row.
        .padding(.top, 2)
        // Keeps a long caption within the bubbles' width.
        .padding(isOutgoing ? .leading : .trailing, 50)
        .frame(maxWidth: .infinity, alignment: isOutgoing ? .trailing : .leading)
        // Opacity alone also keeps the change gentle with Reduce Motion.
        .animation(.easeInOut(duration: 0.18), value: indicator)
    }
}
