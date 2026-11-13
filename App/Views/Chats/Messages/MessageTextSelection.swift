import SwiftUI

extension View {
    /// Text selection for a message body. On macOS the body becomes selectable
    /// only once the reader tries to select it; see `SelectableMessages`.
    /// - Parameter id: The message, or nil for text that is never selected,
    ///   such as the typing indicator.
    func messageTextSelection(id: String?) -> some View {
        modifier(MessageTextSelection(id: id))
    }
}

/// Turns on text selection once a click-drag starts on the text, so the next
/// drag selects. On macOS a drag gesture sees only a pressed mouse or
/// trackpad click; scrolling and the Reply and Edit swipes are two-finger
/// scroll events, so they never arm a bubble. The gesture runs alongside the
/// timeline's own, without claiming the drag.
private struct MessageTextSelection: ViewModifier {
    let id: String?
    @Environment(\.selectableMessages) private var selectableMessages

    func body(content: Content) -> some View {
        #if os(macOS)
        if let id, let selectableMessages {
            if selectableMessages.contains(id) {
                content.textSelection(.enabled)
            } else {
                content.simultaneousGesture(
                    // Past a click's jitter, so a click on a link doesn't arm it.
                    DragGesture(minimumDistance: 4).onChanged { _ in
                        selectableMessages.arm(id)
                    }
                )
            }
        } else if id != nil {
            content.textSelection(.enabled)
        } else {
            content
        }
        #else
        if id != nil {
            content.textSelection(.enabled)
        } else {
            content
        }
        #endif
    }
}
