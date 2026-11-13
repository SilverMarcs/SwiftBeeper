import SwiftUI

/// Returns a timeline showing an older stretch of the conversation, such as
/// a search result's, to the newest messages.
struct JumpToLatestButton: View {
    let action: () -> Void

    var body: some View {
        Button("Jump to Latest", systemImage: "arrow.down", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .padding()
    }
}
