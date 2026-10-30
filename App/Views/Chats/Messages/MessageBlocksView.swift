import SwiftUI

/// Message blocks stacked top to bottom. A lone block, the common case, renders
/// without a stack.
struct MessageBlocksView: View {
    let blocks: [MessageBlock]

    var body: some View {
        if blocks.count == 1, let block = blocks.first {
            MessageBlockView(block: block)
        } else {
            VStack(alignment: .leading) {
                ForEach(blocks.enumerated(), id: \.offset) { _, block in
                    MessageBlockView(block: block)
                }
            }
        }
    }
}
