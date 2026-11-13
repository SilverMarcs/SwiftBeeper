import SwiftUI

/// "Sending…", "Sent", "Delivered", "Seen" or, in a group, who has seen it,
/// below the user's message. Each step replaces the words at once, with no
/// animation.
struct DeliveryCaptionView: View {
    let indicator: DeliveryIndicator

    var body: some View {
        Text(indicator.label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.trailing)
            .padding(.trailing, 3)
            // Matches the gap a caption had inside its message's row.
            .padding(.top, 2)
            // Keeps a long list of names within the outgoing bubbles' width.
            .padding(.leading, 50)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transaction { $0.animation = nil }
    }
}
