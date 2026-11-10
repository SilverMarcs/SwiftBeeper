import SwiftUI

/// A message body styled for its bubble, with links in the bubble's tint.
/// It's selectable unless the user turned selection off.
struct MessageBlocksText: View {
    let blocks: [MessageBlock]
    let isOutgoing: Bool
    @Environment(\.selectsMessageText) private var selectsMessageText

    var body: some View {
        MessageBlocksView(blocks: blocks)
            .font(.body)
            .foregroundStyle(isOutgoing ? .white : .primary)
            // Links follow the tint; white keeps contrast on the brand fill.
            .tint(isOutgoing ? .white : .blue)
            .messageTextSelection(selectsMessageText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
