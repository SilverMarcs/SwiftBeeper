import SwiftUI

/// Fills outgoing bubbles with the app's accent color and incoming ones subtly.
struct BubbleBackgroundModifier: ViewModifier {
    let isOutgoing: Bool

    func body(content: Content) -> some View {
        if isOutgoing {
            content.background(Color.accentColor.gradient)
        } else {
            content.subtleBackground()
        }
    }
}
