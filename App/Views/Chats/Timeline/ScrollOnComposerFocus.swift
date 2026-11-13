#if os(iOS)
import SwiftUI

/// Scrolls the timeline to the newest message when the composer gains focus,
/// which `scrollToLatest` skips for a reader who scrolled back. A message
/// being replied to or edited is kept above the composer by the timeline
/// itself, as the keyboard's safe area arrives.
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

    func body(content: Content) -> some View {
        content
            .onChange(of: composer.isFocused) { _, focused in
                scrollTask?.cancel()
                guard focused, composer.activeMessage == nil else { return }
                // The wait lets the keyboard's safe area apply first.
                scrollTask = Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(1))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, composer.activeMessage == nil else { return }
                    scrollToLatest()
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
    /// Scrolls to the newest message when the composer gains focus without
    /// a reply or edit.
    func scrollsOnComposerFocus(_ composer: Composer, scrollToLatest: @escaping () -> Void) -> some View {
        modifier(ScrollOnComposerFocus(composer: composer, scrollToLatest: scrollToLatest))
    }
}
#endif
