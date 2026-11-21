import SwiftUI

/// Bubble metrics and fills shared by message, reply, reaction, and attachment views.
enum ChatVisualStyle {
    /// Duration of the incoming bubble's expansion.
    static let typingBubbleExpansionDuration = 0.35

    /// How a tapped quote's messages move between their rows and the chain
    /// above the reply, and the timeline recedes around them. Reduce Motion
    /// keeps only a short fade.
    static func quotedMessageAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .smooth(duration: 0.35)
    }

    #if os(macOS)
    static let bubbleHorizontalPadding: CGFloat = 12
    static let bubbleVerticalPadding: CGFloat = 8
    static let bubbleCornerRadius: CGFloat = 15
    static let bubbleJoinedCornerRadius: CGFloat = 5
    #else
    static let bubbleHorizontalPadding: CGFloat = 13
    static let bubbleVerticalPadding: CGFloat = 10
    static let bubbleCornerRadius: CGFloat = 20
    static let bubbleJoinedCornerRadius: CGFloat = 6
    #endif

    /// How far reaction pills, ring included, reach up over the bottom of
    /// the bubbles they react to.
    static let reactionPillOverlap: CGFloat = 6
    /// The ring of the timeline's background around each reaction pill.
    static let reactionPillRingWidth: CGFloat = 2

    /// A bubble's outline: round all over, except on the sender's side
    /// (leading for incoming, trailing for outgoing), where it meets the
    /// bubbles it joins with a tighter corner.
    static func bubbleShape(isOutgoing: Bool, joins: MessageBubbleJoins) -> UnevenRoundedRectangle {
        let top = joins.contains(.above) ? bubbleJoinedCornerRadius : bubbleCornerRadius
        let bottom = joins.contains(.below) ? bubbleJoinedCornerRadius : bubbleCornerRadius
        let full = bubbleCornerRadius
        return UnevenRoundedRectangle(cornerRadii: isOutgoing
            ? RectangleCornerRadii(topLeading: full, bottomLeading: full, bottomTrailing: bottom, topTrailing: top)
            : RectangleCornerRadii(topLeading: top, bottomLeading: bottom, bottomTrailing: full, topTrailing: full))
    }
}

// MARK: - Adaptive background modifiers

private struct SubtleBackgroundModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(colorScheme == .dark ? AnyShapeStyle(.background.tertiary) : AnyShapeStyle(.background.secondary))
    }
}

extension View {
    func subtleBackground() -> some View {
        modifier(SubtleBackgroundModifier())
    }

    func bubbleBackground(isOutgoing: Bool) -> some View {
        modifier(BubbleBackgroundModifier(isOutgoing: isOutgoing))
    }

    /// Padding + background + clip shape for a text message bubble.
    /// iOS matches LynkChat's bubble chrome; macOS keeps the tighter style.
    func messageBubbleChrome(isOutgoing: Bool) -> some View {
        modifier(MessageBubbleChrome(isOutgoing: isOutgoing))
    }
}
