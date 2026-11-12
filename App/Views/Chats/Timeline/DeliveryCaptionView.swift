import SwiftUI

/// "Sending…", "Sent", "Delivered" or "Read" below the newest message. Each
/// step replaces the words at once, with no animation.
struct DeliveryCaptionView: View {
    let indicator: DeliveryIndicator

    var body: some View {
        Text(indicator.label)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.trailing, 3)
            // Matches the gap a caption had inside its message's row.
            .padding(.top, 2)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .transaction { $0.animation = nil }
    }
}
