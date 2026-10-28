import SwiftUI

/// Only these three shapes animate; no timer or animation state reaches the store.
struct TypingDotsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        // Reserve the exact line box used by message text, including its pixel rounding.
        MessageTextView(text: "•••", isOutgoing: false)
            .hidden()
            .overlay {
                if isVisible && scenePhase == .active && !reduceMotion {
                    PhaseAnimator([0, 1, 2, 3]) { phase in
                        TypingDotsPhaseView(highlightedDot: phase)
                    } animation: { _ in
                        .easeInOut(duration: 0.35)
                    }
                } else {
                    TypingDotsPhaseView(highlightedDot: nil)
                }
            }
            .accessibilityHidden(true)
            .onAppear { isVisible = true }
            .onDisappear { isVisible = false }
    }
}
