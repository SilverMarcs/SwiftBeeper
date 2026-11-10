#if os(iOS)
import SwiftUI

/// Scrolls the timeline when the composer gains focus: to the message being
/// replied to or edited, so it sits just above the keyboard, or otherwise to
/// the newest message, which `scrollToLatest` skips for a reader who
/// scrolled back.
///
/// Focus is observed here rather than in `ChatTimelineView.body`, so a focus
/// change re-evaluates only this modifier. Interactive keyboard dismissal ends
/// with UIKit resigning the field in the same run-loop turn that commits the
/// timeline's final inset and offset correction. Rebuilding and diffing every
/// timeline row in that turn delays the correction, so the timeline settles
/// after the composer.
struct ScrollOnComposerFocus: ViewModifier {
    @State private var scrollTask: Task<Void, Never>?

    let composer: Composer
    let scrollToLatest: () -> Void
    let scrollToComposerMessage: (Message.ID) -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: composer.isFocused) { _, focused in
                scrollTask?.cancel()
                guard focused else { return }
                let composerMessageID = composer.activeMessage?.id
                // The wait lets the keyboard's safe area apply first.
                scrollTask = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(1))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, composer.activeMessage?.id == composerMessageID else { return }
                    if let composerMessageID {
                        scrollToComposerMessage(composerMessageID)
                    } else {
                        scrollToLatest()
                    }
                }
            }
            // Another conversation's composer takes over this viewport.
            .onChange(of: composer.target) {
                scrollTask?.cancel()
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
        _ composer: Composer,
        scrollToLatest: @escaping () -> Void,
        scrollToComposerMessage: @escaping (Message.ID) -> Void
    ) -> some View {
        modifier(ScrollOnComposerFocus(
            composer: composer,
            scrollToLatest: scrollToLatest,
            scrollToComposerMessage: scrollToComposerMessage
        ))
    }
}
#endif
