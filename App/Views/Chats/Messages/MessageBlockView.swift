import SwiftUI

/// One message block. Font, color, tint, and selection come from the enclosing
/// `MessageTextView`.
struct MessageBlockView: View {
    let block: MessageBlock
    @Environment(\.drawsMessageTextLines) private var drawsLines

    var body: some View {
        switch block {
        case .text(let attributed):
            if drawsLines, attributed.characters.contains("\n") {
                MessageTextLines(text: attributed)
            } else {
                Text(attributed)
            }
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
