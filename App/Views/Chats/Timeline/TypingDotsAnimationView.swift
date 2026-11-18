import SwiftUI

/// The three dots, cycling while on screen in an active scene. Only these
/// shapes animate; no timer or animation state reaches the store.
struct TypingDotsAnimationView: View {
    let size: TypingDotsSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    var body: some View {
        Group {
            if isVisible && scenePhase == .active && !reduceMotion {
                PhaseAnimator([0, 1, 2, 3]) { phase in
                    TypingDotsPhaseView(highlightedDot: phase, size: size)
                } animation: { _ in
                    .easeInOut(duration: 0.35)
                }
            } else {
                TypingDotsPhaseView(highlightedDot: nil, size: size)
            }
        }
        .accessibilityHidden(true)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}
