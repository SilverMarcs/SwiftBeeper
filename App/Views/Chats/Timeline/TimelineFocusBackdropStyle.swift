import SwiftUI

/// Behind the timeline's rows while it focuses on a shown quote or a reply's
/// target: the space around the focused messages, where a tap returns to the
/// timeline. Receded rows let taps through to it. `label` is only for
/// accessibility.
struct TimelineFocusBackdropStyle: ButtonStyle {
    let label: LocalizedStringKey

    func makeBody(configuration: Configuration) -> some View {
        Color.clear
            .contentShape(.rect)
            .accessibilityElement()
            .accessibilityLabel(Text(label))
            .accessibilityAddTraits(.isButton)
    }
}
