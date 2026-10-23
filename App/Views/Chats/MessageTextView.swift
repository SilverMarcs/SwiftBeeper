import SwiftUI

/// The pending row, confirmed row, and send animation use identical text metrics.
struct MessageTextView: View {
    let text: String
    let isOutgoing: Bool
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        MessageTextLayout(displayScale: displayScale) {
            Text(text.messageAttributed)
                .font(.body)
                .foregroundStyle(isOutgoing ? .white : .primary)
                // Links follow the tint; white keeps contrast on the accent fill.
                .tint(isOutgoing ? .white : .blue)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
