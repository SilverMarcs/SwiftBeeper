import SwiftUI

/// A row naming a kind of shared content and how many the chat holds.
struct ChatInfoMediaRow: View {
    let kind: ChatMediaKind
    let count: Int?

    var body: some View {
        NavigationLink(value: ChatInfoDestination.media(kind)) {
            LabeledContent {
                if let count {
                    Text(count, format: .number)
                }
            } label: {
                Label {
                    Text(kind.title)
                } icon: {
                    Image(systemName: kind.systemImage)
                }
            }
        }
    }
}
