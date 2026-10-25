#if os(iOS)
import SwiftUI

/// Scrolls the timeline when the composer gains focus: to the message being
/// replied to or edited, so it sits just above the keyboard, or otherwise to
/// the newest message.
///
/// Focus is observed here rather than in `ChatTimelineView.body`, so a focus
/// change re-evaluates only this modifier. Interactive keyboard dismissal ends
/// with UIKit resigning the field in the same run-loop turn that commits the
/// timeline's final inset and offset correction. Rebuilding and diffing every
/// timeline row in that turn delays the correction, so the timeline settles
/// after the composer.
struct ScrollOnComposerFocus: ViewModifier {
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    @State private var scrollTask: Task<Void, Never>?

    let chatID: Chat.ID
    let scrollToLatest: () -> Void
    let scrollToComposerMessage: (Message.ID) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: inputManager.isComposerFocused) { _, focused in
                scrollTask?.cancel()
                guard focused else { return }
                let composerMessageID = chatStore.activeComposerMessage?.id
                // Focus changes keep arriving after the viewport is recreated
                // for another chat. Schedule from that event, not .task(id:).
                // The wait lets the keyboard's safe area apply first.
                scrollTask = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(1))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled,
                          chatStore.selectedChatID == chatID,
                          chatStore.activeComposerMessage?.id == composerMessageID else { return }
                    if let composerMessageID {
                        scrollToComposerMessage(composerMessageID)
                    } else {
                        scrollToLatest()
                    }
                }
            }
            .onDisappear {
                scrollTask?.cancel()
            }
    }
}

extension View {
    /// Scrolls to the reply/edit target, or the newest message, when the
    /// search-field or inline composer gains focus.
    func scrollsOnComposerFocus(
        chatID: Chat.ID,
        scrollToLatest: @escaping () -> Void,
        scrollToComposerMessage: @escaping (Message.ID) -> Void
    ) -> some View {
        modifier(ScrollOnComposerFocus(
            chatID: chatID,
            scrollToLatest: scrollToLatest,
            scrollToComposerMessage: scrollToComposerMessage
        ))
    }
}
#endif
