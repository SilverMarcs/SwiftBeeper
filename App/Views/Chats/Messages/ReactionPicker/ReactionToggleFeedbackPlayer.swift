import SwiftUI

/// An invisible view that plays the reaction toggle haptic. It alone observes
/// the toggle count, so a toggle doesn't re-render the timeline around it.
struct ReactionToggleFeedbackPlayer: View {
    let feedback: ReactionToggleFeedback

    var body: some View {
        Color.clear
            .sensoryFeedback(Self.pattern, trigger: feedback.count)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    /// A light tap on iPhone and iPad. Macs only play the patterns AppKit
    /// offers, and only on a Force Touch trackpad being touched; a mouse
    /// click plays nothing.
    private static var pattern: SensoryFeedback {
        #if os(macOS)
        .levelChange
        #else
        .impact(weight: .light)
        #endif
    }
}
