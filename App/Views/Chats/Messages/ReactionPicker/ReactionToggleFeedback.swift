import SwiftUI

/// Counts the user's own reaction toggles, so the timeline plays one haptic
/// for each. Pills, the context menu's quick reactions, and the emoji picker
/// all bump it; reactions arriving from others never do.
///
/// The timeline owns it rather than the control that toggled: the context
/// menu dismisses on selection, and a pill whose last reactor withdraws
/// leaves the timeline.
@MainActor
@Observable
final class ReactionToggleFeedback {
    /// The trigger the timeline's haptic watches.
    private(set) var count = 0

    /// Plays the toggle haptic once.
    func play() {
        count += 1
    }
}

extension EnvironmentValues {
    /// The open timeline's toggle haptic; nil outside a timeline.
    @Entry var reactionToggleFeedback: ReactionToggleFeedback?
}
