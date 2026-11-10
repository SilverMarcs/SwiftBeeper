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
        case .heading(let level, let attributed):
            MessageHeadingView(level: level, text: attributed)
        case .list(let items):
            MessageListView(items: items)
        case .code(let code):
            MessageCodeBlockView(code: code)
        case .rule:
            Divider()
        }
    }
}
