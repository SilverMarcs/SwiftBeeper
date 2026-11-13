import SwiftUI

/// The quoted-message overlay's backdrop: a full-bleed blur of the timeline
/// that closes the overlay when tapped. The button's label is only for
/// accessibility.
struct QuotedMessageBackdropStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Rectangle()
            .fill(.regularMaterial)
            .ignoresSafeArea()
            .accessibilityElement()
            .accessibilityLabel(Text("Close"))
            .accessibilityAddTraits(.isButton)
    }
}
