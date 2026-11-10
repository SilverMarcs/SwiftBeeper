import SwiftUI

/// Beside the sender's name on a forwarded message, or in its place when the
/// row shows no name. Inherits the name's font.
struct ForwardedLabel: View {
    var body: some View {
        Label("Forwarded", systemImage: "arrowshape.turn.up.right")
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.secondary)
    }
}
