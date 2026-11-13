import SwiftUI

/// The chat's name in a glass capsule under the navigation bar, as in
/// Messages. Opens chat info.
struct ChatHeaderNameButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .font(.subheadline.bold())
        }
        .buttonStyle(.glass)
        .accessibilityHint("Shows chat info")
    }
}
