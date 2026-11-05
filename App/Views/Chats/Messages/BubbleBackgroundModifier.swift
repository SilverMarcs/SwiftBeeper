import SwiftUI

/// Fills outgoing bubbles with the chat network's color and incoming ones subtly.
struct BubbleBackgroundModifier: ViewModifier {
    let isOutgoing: Bool
    @Environment(\.outgoingBubbleColor) private var outgoingBubbleColor

    func body(content: Content) -> some View {
        if isOutgoing {
            content.background(outgoingBubbleColor.gradient)
        } else {
            content.subtleBackground()
        }
    }
}
