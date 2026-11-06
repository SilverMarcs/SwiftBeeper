import SwiftUI

/// Washes outgoing bubbles with a translucent tint of the chat network's color,
/// drawn as a gradient, so primary text stays legible in both color schemes.
/// Dark mode uses a much stronger wash, since a faint tint of a deep brand
/// color vanishes on black. Incoming bubbles take the neutral subtle fill.
struct BubbleBackgroundModifier: ViewModifier {
    let isOutgoing: Bool
    @Environment(\.outgoingBubbleColor) private var outgoingBubbleColor
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if isOutgoing {
            let gradient = outgoingBubbleColor.gradient
            content.background(colorScheme == .dark ? AnyShapeStyle(gradient.secondary) : AnyShapeStyle(gradient.quinary))
        } else {
            content.subtleBackground()
        }
    }
}
