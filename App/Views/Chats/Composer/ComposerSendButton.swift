import SwiftUI

/// The inline composer's Send button, which saves instead while editing.
struct ComposerSendButton: View {
    @Environment(InputManager.self) private var input
    @Environment(ChatStore.self) private var chatStore

    let submit: () -> Void

    var body: some View {
        Button(action: submit) {
            if chatStore.isSavingEdit {
                ProgressView()
                    #if os(macOS)
                    .controlSize(.small)
                    #endif
            } else {
                Label(input.isEditing ? "Save" : "Send", systemImage: input.isEditing ? "checkmark" : "arrow.up")
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .bold()
            }
        }
        .opacity(input.sendButtonDisabled ? 0.35 : 0.85)
        #if os(macOS)
        .controlSize(.large)
        #endif
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .allowsHitTesting(!input.sendButtonDisabled)
        .offset(y: -2)
    }
}
