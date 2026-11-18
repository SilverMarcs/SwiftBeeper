import SwiftUI

/// A compact incoming bubble of typing dots, one line of the preview's text
/// tall, so it reads as part of a chat row's preview rather than a message.
struct ChatRowTypingBubble: View {
    @ScaledMetric(relativeTo: .body) private var horizontalPadding = 7.0

    var body: some View {
        ZStack {
            // Takes the height of one line of the row's preview font.
            Text(verbatim: " ")
                .lineLimit(1, reservesSpace: false)
                .hidden()
            TypingDotsAnimationView(size: .compact)
        }
        .padding(.horizontal, horizontalPadding)
        .bubbleBackground(isOutgoing: false)
        .clipShape(.capsule)
        .accessibilityHidden(true)
    }
}
