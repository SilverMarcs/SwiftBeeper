import SwiftUI

/// Reserve the final text layout and briefly fade in newly arrived content.
struct TypingBubbleContentReveal: ViewModifier {
    @Environment(\.revealsTypingBubbleContent) private var shouldReveal
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(!shouldReveal || isVisible ? 1 : 0)
            .animation(
                shouldReveal
                    ? .easeIn(duration: 0.08)
                    : nil,
                value: isVisible
            )
            .onAppear { isVisible = true }
    }
}
