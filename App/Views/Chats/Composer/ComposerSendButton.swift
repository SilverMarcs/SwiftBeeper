#if os(macOS)
import SwiftUI

/// The inline composer's Send button, which saves instead while editing.
struct ComposerSendButton: View {
    let isEditing: Bool
    let isSaving: Bool
    let isDisabled: Bool
    let submit: () -> Void

    var body: some View {
        Button(action: submit) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label(isEditing ? "Save" : "Send", systemImage: isEditing ? "checkmark" : "arrow.up")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .bold()
            }
        }
        .opacity(isDisabled ? 0.35 : 0.85)
        .controlSize(.large)
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .allowsHitTesting(!isDisabled)
        .offset(y: -2)
    }
}
#endif
