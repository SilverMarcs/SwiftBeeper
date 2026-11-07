import SwiftUI

/// The inline composers' Send button, which saves instead while editing.
struct ComposerSendButton: View {
    @Environment(\.outgoingBubbleColor) private var outgoingBubbleColor

    let isEditing: Bool
    let isSaving: Bool
    let isDisabled: Bool
    let submit: () -> Void

    var body: some View {
        Button(action: submit) {
            if isSaving {
                ProgressView()
                    #if os(macOS)
                    .controlSize(.small)
                    #endif
            } else {
                Label(isEditing ? "Save" : "Send", systemImage: isEditing ? "checkmark" : "arrow.up")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .bold()
            }
        }
        .opacity(isDisabled ? 0.35 : 0.85)
        #if os(macOS)
        .controlSize(.large)
        #endif
        .buttonStyle(.glassProminent)
        .tint(outgoingBubbleColor)
        .buttonBorderShape(.circle)
        .allowsHitTesting(!isDisabled)
        .offset(y: -2)
    }
}
