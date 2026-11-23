import SwiftUI

/// A message body styled for its bubble, with links in the bubble's tint.
struct MessageBlocksText: View {
    let blocks: [MessageBlock]
    let isOutgoing: Bool
    /// The message, for text selection; nil keeps the text unselectable.
    let selectionID: String?

    var body: some View {
        MessageBlocksView(blocks: blocks)
            .chatFont(.body)
            .foregroundStyle(isOutgoing ? .white : .primary)
            // Links follow the tint; white keeps contrast on the accent fill.
            .tint(isOutgoing ? .white : .accentColor)
            .messageTextSelection(id: selectionID)
            .fixedSize(horizontal: false, vertical: true)
    }
}
