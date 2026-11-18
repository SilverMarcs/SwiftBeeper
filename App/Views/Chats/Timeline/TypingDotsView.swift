import SwiftUI

/// The dots in a timeline typing bubble, sized to one line of message text.
struct TypingDotsView: View {
    @ScaledMetric(relativeTo: .body) private var minimumWidth = 32.0

    var body: some View {
        // Reserve the exact line box used by message text, including its pixel rounding.
        MessageTextView(text: "•••", isOutgoing: false)
            .hidden()
            .frame(minWidth: minimumWidth)
            .overlay {
                TypingDotsAnimationView(size: .regular)
            }
            .accessibilityHidden(true)
    }
}
