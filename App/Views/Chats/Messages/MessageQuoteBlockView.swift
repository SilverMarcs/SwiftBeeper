import SwiftUI

/// Quoted text, dimmed and set off by a leading bar. Both derive from the
/// bubble's foreground style, so they work on incoming and outgoing bubbles.
struct MessageQuoteBlockView: View {
    let blocks: [MessageBlock]

    var body: some View {
        MessageBlocksView(blocks: blocks)
            .foregroundStyle(.secondary)
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 3)
            }
    }
}
