import SwiftUI

/// Fills outgoing bubbles with the app's accent color and incoming ones subtly.
/// A bookmarked message turns orange.
struct BubbleBackgroundModifier: ViewModifier {
    let isOutgoing: Bool
    @Environment(\.isBookmarkedBubble) private var isBookmarked
    @Environment(\.colorScheme) private var colorScheme

    /// Orange for bookmarked bubbles: yours filled with it, others washed
    /// with it over their subtle fill.
    private static let bookmarkFill = Color(red: 0.93, green: 0.48, blue: 0.12)

    func body(content: Content) -> some View {
        Group {
            if isOutgoing {
                content.background(isBookmarked ? Self.bookmarkFill.gradient : Color.accentColor.gradient)
            } else {
                content
                    .background {
                        // Only bookmarked bubbles pay for the extra layer.
                        if isBookmarked {
                            Self.bookmarkFill
                                .opacity(colorScheme == .dark ? 0.14 : 0.16)
                                .transition(.opacity)
                        }
                    }
                    .subtleBackground()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isBookmarked)
    }
}
