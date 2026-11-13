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
        // iOS draws glass buttons as capsules already; macOS defaults to a
        // rounded rectangle.
        .buttonBorderShape(.capsule)
        .accessibilityHint("Shows chat info")
    }
}
