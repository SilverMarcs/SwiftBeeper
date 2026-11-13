import SwiftUI

/// A text bubble's padding, fill and outline, shaped by its place in the
/// sender's run of bubbles.
struct MessageBubbleChrome: ViewModifier {
    let isOutgoing: Bool
    @Environment(\.messageBubbleJoins) private var joins

    func body(content: Content) -> some View {
        let shape = ChatVisualStyle.bubbleShape(isOutgoing: isOutgoing, joins: joins)
        content
            // Fade only the contents; the matched background must remain visible.
            .modifier(TypingBubbleContentReveal())
            .padding(.horizontal, ChatVisualStyle.bubbleHorizontalPadding)
            .padding(.vertical, ChatVisualStyle.bubbleVerticalPadding)
            .background {
                Color.clear
                    .bubbleBackground(isOutgoing: isOutgoing)
                    .clipShape(shape)
                    .modifier(TypingBubbleGeometry())
            }
            .clipShape(shape)
    }
}
