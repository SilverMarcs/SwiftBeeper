import SwiftUI

/// Leaves the composer's reply or edit. It sits in the toolbar in place of
/// the conversation's own button while there is one to leave.
struct ComposerCancelButton: View {
    @Environment(InputManager.self) private var input

    let composer: Composer

    var body: some View {
        Button(composer.isEditing ? "Cancel Edit" : "Cancel Reply", systemImage: "xmark") {
            input.cancelAction(in: composer)
        }
        // Red, as leaving an edit discards its changes.
        .buttonStyle(.glassProminent)
        .tint(.red)
        .keyboardShortcut(.cancelAction)
    }
}
