import SwiftUI

extension EnvironmentValues {
    /// Set only on a typing row and the real message that inherits that row.
    @Entry var typingBubbleNamespace: Namespace.ID? = nil
    @Entry var revealsTypingBubbleContent = false
}

/// Links the old bubble to its destination without scaling the message's text.
struct TypingBubbleGeometry: ViewModifier {
    var isEnabled = true
    @Environment(\.typingBubbleNamespace) private var namespace

    func body(content: Content) -> some View {
        if isEnabled, let namespace {
            content.matchedGeometryEffect(id: "typing-bubble", in: namespace, anchor: .bottomLeading)
        } else {
            content
        }
    }
}
