import SwiftUI

/// Clips a media, file or audio bubble to the shape its place in the
/// sender's run gives it, the same shape a text bubble there would take.
struct MessageBubbleClip: ViewModifier {
    let isOutgoing: Bool
    @Environment(\.messageBubbleJoins) private var joins

    func body(content: Content) -> some View {
        let shape = ChatVisualStyle.bubbleShape(isOutgoing: isOutgoing, joins: joins)
        content
            .clipShape(shape)
            .contentShape(shape)
    }
}

extension View {
    /// Clips to the bubble shape for this bubble's place in its sender's run.
    func messageBubbleClip(isOutgoing: Bool) -> some View {
        modifier(MessageBubbleClip(isOutgoing: isOutgoing))
    }
}
