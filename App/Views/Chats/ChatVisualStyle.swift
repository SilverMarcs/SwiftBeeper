import SwiftUI

enum ChatVisualStyle {
    #if os(macOS)
    static let bubbleHorizontalPadding: CGFloat = 12
    static let bubbleVerticalPadding: CGFloat = 8
    static let bubbleCornerRadius: CGFloat = 15
    #else
    static let bubbleHorizontalPadding: CGFloat = 13
    static let bubbleVerticalPadding: CGFloat = 10
    static let bubbleCornerRadius: CGFloat = 20
    #endif

    static func reactionFill(isSelected: Bool) -> AnyShapeStyle {
        if isSelected {
            return AnyShapeStyle(.tint.secondary)
        }
        return AnyShapeStyle(.quinary)
    }

    static func replyPreviewFill(isOutgoing: Bool) -> AnyShapeStyle {
        if isOutgoing {
            return AnyShapeStyle(.tint.quaternary)
        }
        return AnyShapeStyle(.quinary)
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

private struct BubbleBackgroundModifier: ViewModifier {
    let isOutgoing: Bool
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if isOutgoing {
            content.background(AnyShapeStyle(Color.accentColor.gradient))
        } else {
            content.background(colorScheme == .dark ? AnyShapeStyle(.background.tertiary) : AnyShapeStyle(.background.secondary))
        }
    }
}

private struct MessageBubbleChromeModifier: ViewModifier {
    let isOutgoing: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, ChatVisualStyle.bubbleHorizontalPadding)
            .padding(.vertical, ChatVisualStyle.bubbleVerticalPadding)
            .bubbleBackground(isOutgoing: isOutgoing)
            .clipShape(.rect(cornerRadius: ChatVisualStyle.bubbleCornerRadius))
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
        modifier(MessageBubbleChromeModifier(isOutgoing: isOutgoing))
    }
}
