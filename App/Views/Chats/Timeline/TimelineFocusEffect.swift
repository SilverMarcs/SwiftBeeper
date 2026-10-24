import SwiftUI

/// Dims and blurs timeline rows that aren't the focused composer target.
struct TimelineFocusEffect: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isFocused ? 1 : 0.35)
            .blur(radius: isFocused ? 0 : 4)
            .scaleEffect(isFocused ? 1 : 0.992)
            .allowsHitTesting(isFocused)
            .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}

extension View {
    func timelineFocus(_ isFocused: Bool) -> some View {
        modifier(TimelineFocusEffect(isFocused: isFocused))
    }
}
