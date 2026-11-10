import SwiftUI

/// Bulleted or numbered items. The marker sits in its own column, so wrapped
/// lines line up under the item's text rather than under the bullet.
struct MessageListView: View {
    let items: [MessageListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items.enumerated(), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.marker)
                        .monospacedDigit()
                        .accessibilityHidden(true)
                    MessageBlocksView(blocks: item.blocks)
                }
            }
        }
    }
}
