import SwiftUI

extension View {
    /// Text selection for a message body. On macOS the body becomes selectable
    /// only once the reader points at it or tries to select it; see
    /// `SelectableMessages`.
    /// - Parameter id: The message, or nil for text that is never selected,
    ///   such as the typing indicator.
    func messageTextSelection(id: String?) -> some View {
        modifier(MessageTextSelection(id: id))
    }
}

/// Turns on text selection once the pointer rests on the text, so a click,
/// double-click or drag selects as it would in always-selectable text. A
/// pointer the timeline scrolls past doesn't stay long enough to arm the
/// bubbles moving under it. A click-drag that starts before the pause ends
/// arms the bubble too, so the next drag selects. On macOS a drag gesture
/// sees only a pressed mouse or trackpad click; scrolling and the Reply and
/// Edit swipes are two-finger scroll events, so they never arm a bubble.
/// The gestures run alongside the timeline's own, without claiming them.
private struct MessageTextSelection: ViewModifier {
    let id: String?
    @Environment(\.selectableMessages) private var selectableMessages
    #if os(macOS)
    @State private var hoverTask: Task<Void, Never>?
    #endif

    /// How long the pointer rests on a bubble before it becomes selectable.
    private static let hoverDelay: Duration = .milliseconds(240)

    func body(content: Content) -> some View {
        #if os(macOS)
        if let id, let selectableMessages {
            if selectableMessages.contains(id) {
                content
                    .textSelection(.enabled)
                    .messageSelectionGroup()
                    // Keeps the text exactly where it was before it armed.
                    .environment(\.drawsMessageTextLines, true)
            } else {
                content
                    .onHover { hovering in
                        hoverTask?.cancel()
                        guard hovering else { return }
                        hoverTask = Task { @MainActor in
                            try? await Task.sleep(for: Self.hoverDelay)
                            guard !Task.isCancelled else { return }
                            selectableMessages.arm(id)
                        }
                    }
                    .simultaneousGesture(
                        // Past a click's jitter, so a click on a link doesn't arm it.
                        DragGesture(minimumDistance: 4).onChanged { _ in
                            selectableMessages.arm(id)
                        }
                    )
                    .onDisappear {
                        hoverTask?.cancel()
                    }
            }
        } else if id != nil {
            content.textSelection(.enabled).messageSelectionGroup()
        } else {
            content
        }
        #else
        if id != nil {
            content.textSelection(.enabled).messageSelectionGroup()
        } else {
            content
        }
        #endif
    }
}
