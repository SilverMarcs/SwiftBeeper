#if os(iOS)
import SwiftUI

/// Send, in the slot at the end of the composer bar's field, once there's
/// something to send. Saves instead while editing.
///
/// A solid circle rather than glass: inside the composer's glass container,
/// glass this close would melt into the field around it.
struct ComposerBarSendButton: View {
    let isEditing: Bool
    let isSaving: Bool
    let isEnabled: Bool
    let send: () -> Void

    @ScaledMetric(relativeTo: .body) private var diameter = 34

    var body: some View {
        Button(isEditing ? "Save" : "Send", systemImage: isEditing ? "checkmark" : "arrow.up", action: send)
            .buttonStyle(ComposerBarSendButtonStyle(diameter: diameter, isBusy: isSaving))
            .opacity(isEnabled || isSaving ? 1 : 0.35)
            .allowsHitTesting(isEnabled)
    }
}
#endif
