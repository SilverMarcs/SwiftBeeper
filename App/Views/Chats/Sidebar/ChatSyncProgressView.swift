import SwiftUI

/// The toolbar spinner shown while the chat list catches up with the server.
struct ChatSyncProgressView: View {
    var body: some View {
        ProgressView()
            .accessibilityLabel("Updating chats")
    }
}
