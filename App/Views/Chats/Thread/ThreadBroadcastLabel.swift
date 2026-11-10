import SwiftUI

/// Beside the sender's name on a thread reply also sent to the chat, or in
/// its place when the row shows no name. Inherits the name's font.
struct ThreadBroadcastLabel: View {
    /// Whether the sender's name precedes the label on the same line.
    let followsName: Bool

    var body: some View {
        Text(followsName ? "replied to a thread" : "Replied to a thread")
            .foregroundStyle(.secondary)
    }
}
