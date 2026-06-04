import SwiftUI

enum ChatVisualStyle {
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
        #if os(macOS)
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .bubbleBackground(isOutgoing: isOutgoing)
            .clipShape(.rect(cornerRadius: 15))
        #else
        content
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .bubbleBackground(isOutgoing: isOutgoing)
            .clipShape(.rect(cornerRadius: 20))
        #endif
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
