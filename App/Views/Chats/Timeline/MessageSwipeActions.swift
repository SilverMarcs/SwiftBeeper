import SwiftUI

/// Swipe a message right to reply to it, as the timeline offered when it was
/// a `List`. Editing stays in the context menu. Swipe actions on scroll view
/// rows need iOS and macOS 27; earlier systems keep only the context menu.
///
/// The enclosing scroll view takes `timelineSwipeActionsContainer()`, so only
/// one row stays open and scrolling or tapping elsewhere closes it.
struct MessageSwipeActions: ViewModifier {
    let message: Message
    /// False while the composer replies to or edits a message and the rest of
    /// the timeline recedes.
    let isEnabled: Bool

    @Environment(InputManager.self) private var input
    @Environment(\.composer) private var composer
    #if os(iOS)
    @Environment(\.timelineTapRecognizer) private var timelineTapRecognizer
    #endif

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27, macOS 27, *) {
            content
                .swipeActions(edge: .leading) {
                    // Inside a thread every message is already a thread reply.
                    if isEnabled, let composer, !composer.target.isThread {
                        Button("Reply", systemImage: "arrowshape.turn.up.left") {
                            input.reply(to: message, in: composer, afterContextMenu: false)
                        }
                        .tint(.accentColor)
                        .labelStyle(.iconOnly)
                    }
                } onPresentationChanged: { presented in
                    #if os(iOS)
                    timelineTapRecognizer?.setSwipeActionsPresented(presented, for: message.id)
                    #endif
                }
                #if os(iOS)
                .onDisappear {
                    timelineTapRecognizer?.setSwipeActionsPresented(false, for: message.id)
                }
                #endif
        } else {
            content
        }
    }
}

extension View {
    /// Adds the Reply swipe action for `message` where the system supports it.
    func messageSwipeActions(_ message: Message, isEnabled: Bool) -> some View {
        modifier(MessageSwipeActions(message: message, isEnabled: isEnabled))
    }
}
