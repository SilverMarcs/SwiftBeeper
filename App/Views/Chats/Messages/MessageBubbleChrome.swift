import SwiftUI

struct MessageBubbleChrome: ViewModifier {
    let isOutgoing: Bool

    func body(content: Content) -> some View {
        content
            // Fade only the contents; the matched background must remain visible.
            .modifier(TypingBubbleContentReveal())
            .padding(.horizontal, ChatVisualStyle.bubbleHorizontalPadding)
            .padding(.vertical, ChatVisualStyle.bubbleVerticalPadding)
            .background {
                Color.clear
                    .bubbleBackground(isOutgoing: isOutgoing)
                    .clipShape(.rect(cornerRadius: ChatVisualStyle.bubbleCornerRadius))
                    .modifier(TypingBubbleGeometry())
            }
            .clipShape(.rect(cornerRadius: ChatVisualStyle.bubbleCornerRadius))
    }
}
