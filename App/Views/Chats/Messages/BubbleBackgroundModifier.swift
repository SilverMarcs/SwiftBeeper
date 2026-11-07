import SwiftUI

/// Fills outgoing bubbles with the chat network's color and incoming ones subtly.
/// In light mode the brand color is eased slightly toward gray, since a fully
/// saturated fill reads harsh against a white timeline; white text stays legible.
struct BubbleBackgroundModifier: ViewModifier {
    let isOutgoing: Bool
    @Environment(\.outgoingBubbleColor) private var outgoingBubbleColor
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if isOutgoing {
            content.background(fill.gradient)
        } else {
            content.subtleBackground()
        }
    }

    private var fill: Color {
        guard colorScheme == .light else { return outgoingBubbleColor }
        return outgoingBubbleColor.mix(with: Color(white: 0.55), by: 0.12)
    }
}
