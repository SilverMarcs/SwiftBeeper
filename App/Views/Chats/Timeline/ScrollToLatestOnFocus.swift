#if os(iOS)
import SwiftUI

/// Scrolls the timeline to its newest message when the composer gains focus.
///
/// Focus is observed here rather than in `ChatTimelineView.body`, so a focus
/// change re-evaluates only this modifier. Interactive keyboard dismissal ends
/// with UIKit resigning the field in the same run-loop turn that commits the
/// timeline's final inset and offset correction. Rebuilding and diffing every
/// timeline row in that turn delays the correction, so the timeline settles
/// after the composer.
struct ScrollToLatestOnFocus: ViewModifier {
    @Environment(ChatStore.self) private var chatStore
    @Environment(InputManager.self) private var inputManager
    @State private var scrollTask: Task<Void, Never>?

    let chatID: Chat.ID
    let scrollToLatest: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: inputManager.isComposerFocused) { _, focused in
                scrollTask?.cancel()
                guard focused,
                      chatStore.activeComposerMessage == nil else { return }
                // Focus changes keep arriving after the viewport is recreated
                // for another chat. Schedule from that event, not .task(id:).
                scrollTask = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(1))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled,
                          chatStore.selectedChatID == chatID,
                          chatStore.activeComposerMessage == nil else { return }
                    scrollToLatest()
                }
            }
            .onDisappear {
                scrollTask?.cancel()
            }
    }
}

extension View {
    /// Scrolls to the newest message when the search-field or inline composer gains focus.
    func scrollsToLatestOnFocus(chatID: Chat.ID, scrollToLatest: @escaping () -> Void) -> some View {
        modifier(ScrollToLatestOnFocus(chatID: chatID, scrollToLatest: scrollToLatest))
    }
}
#endif
