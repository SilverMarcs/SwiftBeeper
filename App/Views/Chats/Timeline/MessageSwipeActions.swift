import SwiftUI

/// Swipe a message right to reply to it, or one of your own left to edit it,
/// as the timeline offered when it was a `List`. Swipe actions on scroll view
/// rows need iOS and macOS 27; earlier systems keep only the context menu.
///
/// The enclosing scroll view takes `timelineSwipeActionsContainer()`, so only
/// one row stays open and scrolling or tapping elsewhere closes it.
struct MessageSwipeActions: ViewModifier {
    let message: Message
    let chat: Chat
    /// False while the composer replies to or edits a message and the rest of
    /// the timeline recedes.
    let isEnabled: Bool

    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var input
    @Environment(\.composer) private var composer

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 27, macOS 27, *) {
            content
                .swipeActions(edge: .leading) {
                    // Inside a thread every message is already a thread reply.
                    if isEnabled, let composer, !composer.target.isThread {
                        Button("Reply", systemImage: "arrowshape.turn.up.left") {
                            input.reply(to: message, in: composer)
                        }
                        .tint(.accentColor)
                        .labelStyle(.iconOnly)
                    }
                }
                .swipeActions(edge: .trailing) {
                    if isEnabled, let composer, chatStore.canEdit(message, in: chat) {
                        Button("Edit", systemImage: "pencil") {
                            input.startEditing(message, in: composer)
                        }
                        .tint(.orange)
                        .labelStyle(.iconOnly)
                    }
                }
        } else {
            content
        }
    }
}

extension View {
    /// Adds the Reply and Edit swipe actions for `message` where the system
    /// supports them.
    func messageSwipeActions(_ message: Message, in chat: Chat, isEnabled: Bool) -> some View {
        modifier(MessageSwipeActions(message: message, chat: chat, isEnabled: isEnabled))
    }
}
