import SwiftUI

struct OpeningChatView: View {
    var body: some View {
        ProgressView("Opening chat…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Opening chat")
    }
}
