import SwiftUI

/// One message block. Font, color, tint, and selection come from the enclosing
/// `MessageTextView`.
struct MessageBlockView: View {
    let block: MessageBlock

    var body: some View {
        switch block {
        case .text(let attributed):
            Text(attributed)
        case .quote(let blocks):
            MessageQuoteBlockView(blocks: blocks)
        }
    }
}
